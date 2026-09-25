import Darwin
import Foundation

public enum ResultFIFO {
    public static let maximumResultBytes = 64 * 1024
    private static let directory = "/private/var/run/lisstech-billboard"

    public static func createOwnedBy(uid: uid_t, gid: gid_t) throws -> String {
        if mkdir(directory, 0o711) != 0 && errno != EEXIST {
            throw BillboardError.transport("Unable to create result-pipe directory: \(errnoDescription()).")
        }

        var directoryInfo = stat()
        guard lstat(directory, &directoryInfo) == 0,
              (directoryInfo.st_mode & S_IFMT) == S_IFDIR,
              directoryInfo.st_uid == 0 else {
            throw BillboardError.transport("Result-pipe directory is not a root-owned directory.")
        }
        guard chmod(directory, 0o711) == 0 else {
            throw BillboardError.transport("Unable to secure result-pipe directory: \(errnoDescription()).")
        }

        let path = "\(directory)/\(UUID().uuidString.lowercased()).fifo"
        guard mkfifo(path, 0o600) == 0 else {
            throw BillboardError.transport("Unable to create result pipe: \(errnoDescription()).")
        }
        guard chown(path, uid, gid) == 0 else {
            unlink(path)
            throw BillboardError.transport("Unable to assign result pipe to the console user: \(errnoDescription()).")
        }
        return path
    }

    public static func write(result: BillboardResult, to path: String) throws {
        var info = stat()
        guard lstat(path, &info) == 0,
              (info.st_mode & S_IFMT) == S_IFIFO,
              info.st_uid == geteuid() else {
            throw BillboardError.transport("Result path is not a pipe owned by the current user.")
        }

        let data = try BillboardJSON.encoder().encode(result)
        guard data.count <= maximumResultBytes else {
            throw BillboardError.transport("Result exceeds the 64 KB pipe limit.")
        }

        let descriptor = open(path, O_WRONLY)
        guard descriptor >= 0 else {
            throw BillboardError.transport("Unable to open result pipe: \(errnoDescription()).")
        }
        defer { close(descriptor) }

        try data.withUnsafeBytes { rawBuffer in
            guard let baseAddress = rawBuffer.baseAddress else { return }
            var written = 0
            while written < rawBuffer.count {
                let count = Darwin.write(
                    descriptor,
                    baseAddress.advanced(by: written),
                    rawBuffer.count - written)
                if count < 0 {
                    if errno == EINTR { continue }
                    throw BillboardError.transport("Unable to write result pipe: \(errnoDescription()).")
                }
                written += count
            }
        }
    }

    public static func read(
        from path: String,
        timeoutSeconds: Int,
        isPeerRunning: (() -> Bool)? = nil
    ) throws -> Data {
        let descriptor = open(path, O_RDONLY | O_NONBLOCK)
        guard descriptor >= 0 else {
            throw BillboardError.transport("Unable to open result pipe: \(errnoDescription()).")
        }
        defer { close(descriptor) }

        let deadline = Date().addingTimeInterval(TimeInterval(timeoutSeconds))
        var output = Data()
        var hasReceivedData = false
        var buffer = [UInt8](repeating: 0, count: 4096)

        while Date() < deadline {
            var item = pollfd(fd: descriptor, events: Int16(POLLIN | POLLHUP), revents: 0)
            let remaining = max(1, Int(deadline.timeIntervalSinceNow * 1000))
            let pollResult = poll(&item, 1, Int32(min(remaining, 1000)))
            if pollResult < 0 {
                if errno == EINTR { continue }
                throw BillboardError.transport("Result pipe polling failed: \(errnoDescription()).")
            }
            if pollResult == 0 {
                if isPeerRunning?() == false {
                    throw BillboardError.transport("Billboard exited before returning a result.")
                }
                continue
            }

            let count = buffer.withUnsafeMutableBytes { rawBuffer in
                Darwin.read(descriptor, rawBuffer.baseAddress, rawBuffer.count)
            }
            if count > 0 {
                hasReceivedData = true
                output.append(contentsOf: buffer.prefix(count))
                if output.count > maximumResultBytes {
                    throw BillboardError.transport("Result exceeds the 64 KB pipe limit.")
                }
                if (try? JSONSerialization.jsonObject(with: output)) != nil {
                    return output
                }
                continue
            }
            if count == 0 && hasReceivedData {
                return output
            }
            if count < 0 && errno != EAGAIN && errno != EINTR {
                throw BillboardError.transport("Unable to read result pipe: \(errnoDescription()).")
            }
            if !hasReceivedData, isPeerRunning?() == false {
                throw BillboardError.transport("Billboard exited before returning a result.")
            }
            usleep(20_000)
        }

        throw BillboardError.transport("Timed out waiting for the interactive user response.")
    }

    public static func remove(_ path: String) {
        unlink(path)
    }

    private static func errnoDescription() -> String {
        String(cString: strerror(errno))
    }
}
