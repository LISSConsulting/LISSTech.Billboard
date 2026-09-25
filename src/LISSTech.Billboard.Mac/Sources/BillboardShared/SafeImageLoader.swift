import AppKit
import CryptoKit
import Darwin
import Foundation
import ImageIO

public enum SafeImageLoader {
    public static let maximumBytes = 8 * 1024 * 1024
    public static let maximumDimension = 8192
    public static let maximumPixels = 16_000_000
    public static let maximumGIFFrames = 60

    public static func load(source: String, maxPixelSize: Int) async throws -> NSImage {
        let data: Data
        if let url = URL(string: source), url.scheme != nil {
            guard url.scheme?.lowercased() == "https" else {
                throw BillboardError.image("Remote artwork must use HTTPS.")
            }
            try RemoteURLPolicy.validate(url)
            if let cached = try? Data(contentsOf: cacheURL(for: source), options: .mappedIfSafe),
               let image = try? validateAndCreateImage(data: cached, maxPixelSize: maxPixelSize) {
                return image
            }
            data = try await RemoteImageDownload.download(url)
            let image = try validateAndCreateImage(data: data, maxPixelSize: maxPixelSize)
            try persist(data: data, source: source)
            return image
        }

        let fileURL = URL(fileURLWithPath: source).standardizedFileURL
        let values = try fileURL.resourceValues(forKeys: [.isRegularFileKey, .fileSizeKey])
        guard values.isRegularFile == true,
              let size = values.fileSize,
              size > 0,
              size <= maximumBytes else {
            throw BillboardError.image("Local artwork is missing or exceeds the 8 MB limit.")
        }
        data = try Data(contentsOf: fileURL, options: .mappedIfSafe)
        return try validateAndCreateImage(data: data, maxPixelSize: maxPixelSize)
    }

    public static func validateAndCreateImage(data: Data, maxPixelSize: Int) throws -> NSImage {
        guard !data.isEmpty, data.count <= maximumBytes else {
            throw BillboardError.image("Image size is outside the supported range.")
        }
        let expectedType = try detectType(data)
        guard let source = CGImageSourceCreateWithData(
            data as CFData,
            [kCGImageSourceShouldCache: false] as CFDictionary),
              CGImageSourceGetStatus(source) == .statusComplete,
              let actualType = CGImageSourceGetType(source) as String?,
              actualType == expectedType else {
            throw BillboardError.image("Image data does not match its declared format.")
        }

        let frameCount = CGImageSourceGetCount(source)
        guard frameCount > 0 else {
            throw BillboardError.image("Image contains no frames.")
        }
        if expectedType == "com.compuserve.gif" && frameCount > maximumGIFFrames {
            throw BillboardError.image("GIF contains too many frames.")
        }

        var totalPixels = 0
        for index in 0..<frameCount {
            guard let properties = CGImageSourceCopyPropertiesAtIndex(source, index, nil) as? [CFString: Any],
                  let width = properties[kCGImagePropertyPixelWidth] as? Int,
                  let height = properties[kCGImagePropertyPixelHeight] as? Int,
                  width > 0,
                  height > 0,
                  width <= maximumDimension,
                  height <= maximumDimension else {
                throw BillboardError.image("Image dimensions are invalid or exceed 8192 pixels.")
            }
            let pixels = width.multipliedReportingOverflow(by: height)
            guard !pixels.overflow else {
                throw BillboardError.image("Image dimensions overflow the safety limit.")
            }
            totalPixels += pixels.partialValue
            guard totalPixels <= maximumPixels else {
                throw BillboardError.image("Image frames exceed the 16-megapixel safety limit.")
            }
        }

        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceThumbnailMaxPixelSize: max(1, min(maxPixelSize, 2048)),
            kCGImageSourceShouldCacheImmediately: true
        ]
        guard let cgImage = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else {
            throw BillboardError.image("Image decoder rejected the artwork.")
        }
        return NSImage(cgImage: cgImage, size: .zero)
    }

    private static func detectType(_ data: Data) throws -> String {
        let bytes = [UInt8](data.prefix(12))
        if bytes.count >= 8 && Array(bytes[0..<8]) == [0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A] {
            return "public.png"
        }
        if bytes.count >= 3 && bytes[0] == 0xFF && bytes[1] == 0xD8 && bytes[2] == 0xFF {
            return "public.jpeg"
        }
        if bytes.count >= 6,
           bytes[0] == 0x47, bytes[1] == 0x49, bytes[2] == 0x46,
           bytes[3] == 0x38, bytes[4] == 0x37 || bytes[4] == 0x39,
           bytes[5] == 0x61 {
            return "com.compuserve.gif"
        }
        throw BillboardError.image("Only PNG, JPEG, and GIF artwork is supported.")
    }

    private static func cacheURL(for source: String) -> URL {
        let digest = SHA256.hash(data: Data(source.utf8)).map { String(format: "%02x", $0) }.joined()
        return FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("com.lisstech.billboard/Images", isDirectory: true)
            .appendingPathComponent(digest + ".img")
    }

    private static func persist(data: Data, source: String) throws {
        let destination = cacheURL(for: source)
        try FileManager.default.createDirectory(
            at: destination.deletingLastPathComponent(),
            withIntermediateDirectories: true,
            attributes: [.posixPermissions: 0o700])
        let temporary = destination.deletingLastPathComponent()
            .appendingPathComponent(UUID().uuidString + ".tmp")
        try data.write(to: temporary, options: .atomic)
        try? FileManager.default.removeItem(at: destination)
        try FileManager.default.moveItem(at: temporary, to: destination)
    }
}

public enum RemoteURLPolicy {
    public static func validate(_ url: URL) throws {
        guard url.scheme?.lowercased() == "https",
              url.user == nil,
              url.password == nil,
              url.port == nil || url.port == 443,
              let host = url.host?.lowercased(),
              host.contains(".") || host.contains(":"),
              !host.hasSuffix(".local"),
              !host.hasSuffix(".internal") else {
            throw BillboardError.image("Remote artwork URL is not allowed.")
        }

        var addresses: UnsafeMutablePointer<addrinfo>?
        guard getaddrinfo(host, nil, nil, &addresses) == 0, let first = addresses else {
            throw BillboardError.image("Remote artwork host did not resolve.")
        }
        defer { freeaddrinfo(first) }

        var foundAddress = false
        var current: UnsafeMutablePointer<addrinfo>? = first
        while let entry = current {
            defer { current = entry.pointee.ai_next }
            guard let address = entry.pointee.ai_addr else { continue }
            if entry.pointee.ai_family == AF_INET {
                let value = address.withMemoryRebound(to: sockaddr_in.self, capacity: 1) { pointer in
                    var address = pointer.pointee.sin_addr
                    return withUnsafeBytes(of: &address) { Array($0) }
                }
                foundAddress = true
                guard isPublicIPv4(value) else {
                    throw BillboardError.image("Remote artwork host resolved to a non-public address.")
                }
            } else if entry.pointee.ai_family == AF_INET6 {
                let value = address.withMemoryRebound(to: sockaddr_in6.self, capacity: 1) { pointer in
                    var address = pointer.pointee.sin6_addr
                    return withUnsafeBytes(of: &address) { Array($0) }
                }
                foundAddress = true
                guard isPublicIPv6(value) else {
                    throw BillboardError.image("Remote artwork host resolved to a non-public address.")
                }
            }
        }
        guard foundAddress else {
            throw BillboardError.image("Remote artwork host has no usable IP address.")
        }
    }

    private static func isPublicIPv4(_ bytes: [UInt8]) -> Bool {
        guard bytes.count == 4 else { return false }
        return bytes[0] != 0 && bytes[0] != 10 && bytes[0] != 127 &&
            !(bytes[0] == 100 && (64...127).contains(bytes[1])) &&
            !(bytes[0] == 169 && bytes[1] == 254) &&
            !(bytes[0] == 172 && (16...31).contains(bytes[1])) &&
            !(bytes[0] == 192 && bytes[1] == 168) &&
            !(bytes[0] == 192 && bytes[1] == 0 && bytes[2] == 0) &&
            !(bytes[0] == 192 && bytes[1] == 0 && bytes[2] == 2) &&
            !(bytes[0] == 198 && (bytes[1] == 18 || bytes[1] == 19)) &&
            !(bytes[0] == 198 && bytes[1] == 51 && bytes[2] == 100) &&
            !(bytes[0] == 203 && bytes[1] == 0 && bytes[2] == 113) &&
            bytes[0] < 224
    }

    private static func isPublicIPv6(_ bytes: [UInt8]) -> Bool {
        guard bytes.count == 16 else { return false }
        let mappedIPv4 = bytes[0..<10].allSatisfy { $0 == 0 } &&
            bytes[10] == 0xFF && bytes[11] == 0xFF
        if mappedIPv4 {
            return isPublicIPv4(Array(bytes[12..<16]))
        }
        let unspecified = bytes.allSatisfy { $0 == 0 }
        let loopback = bytes.dropLast().allSatisfy { $0 == 0 } && bytes.last == 1
        let linkLocal = bytes[0] == 0xFE && (bytes[1] & 0xC0) == 0x80
        let uniqueLocal = (bytes[0] & 0xFE) == 0xFC
        let multicast = bytes[0] == 0xFF
        let documentation = Array(bytes[0...3]) == [0x20, 0x01, 0x0D, 0xB8]
        let transition = (bytes[0] == 0x20 && bytes[1] == 0x02) ||
            Array(bytes[0...3]) == [0x20, 0x01, 0x00, 0x00] ||
            Array(bytes[0...11]) == [0x00, 0x64, 0xFF, 0x9B, 0, 0, 0, 0, 0, 0, 0, 0]
        return !unspecified && !loopback && !linkLocal && !uniqueLocal &&
            !multicast && !documentation && !transition
    }
}
private final class RemoteImageDownload: NSObject, URLSessionDataDelegate {
    private var continuation: CheckedContinuation<Data, Error>?
    private var buffer = Data()
    private var session: URLSession?

    static func download(_ url: URL) async throws -> Data {
        try await withCheckedThrowingContinuation { continuation in
            let delegate = RemoteImageDownload()
            delegate.continuation = continuation
            let configuration = URLSessionConfiguration.ephemeral
            configuration.timeoutIntervalForRequest = 15
            configuration.timeoutIntervalForResource = 20
            configuration.httpAdditionalHeaders = [
                "User-Agent": "LISSTech-Billboard-macOS/1.0",
                "Accept": "image/png,image/jpeg,image/gif",
                "Accept-Encoding": "identity"
            ]
            let session = URLSession(configuration: configuration, delegate: delegate, delegateQueue: nil)
            delegate.session = session
            session.dataTask(with: url).resume()
        }
    }

    func urlSession(
        _ session: URLSession,
        task: URLSessionTask,
        willPerformHTTPRedirection response: HTTPURLResponse,
        newRequest request: URLRequest,
        completionHandler: @escaping (URLRequest?) -> Void
    ) {
        do {
            guard let url = request.url else {
                throw BillboardError.image("Remote artwork redirect has no URL.")
            }
            try RemoteURLPolicy.validate(url)
            completionHandler(request)
        } catch {
            completionHandler(nil)
            finish(.failure(error))
        }
    }

    func urlSession(
        _ session: URLSession,
        dataTask: URLSessionDataTask,
        didReceive response: URLResponse,
        completionHandler: @escaping (URLSession.ResponseDisposition) -> Void
    ) {
        if response.expectedContentLength > SafeImageLoader.maximumBytes {
            completionHandler(.cancel)
            finish(.failure(BillboardError.image("Remote artwork exceeds the 8 MB limit.")))
        } else {
            completionHandler(.allow)
        }
    }

    func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive data: Data) {
        guard buffer.count + data.count <= SafeImageLoader.maximumBytes else {
            dataTask.cancel()
            finish(.failure(BillboardError.image("Remote artwork exceeds the 8 MB limit.")))
            return
        }
        buffer.append(data)
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        if let error {
            finish(.failure(error))
            return
        }
        guard let response = task.response as? HTTPURLResponse,
              (200...299).contains(response.statusCode) else {
            finish(.failure(BillboardError.image("Remote artwork server returned an error.")))
            return
        }
        finish(.success(buffer))
    }

    private func finish(_ result: Result<Data, Error>) {
        guard let continuation else { return }
        self.continuation = nil
        continuation.resume(with: result)
        session?.finishTasksAndInvalidate()
        session = nil
    }
}
