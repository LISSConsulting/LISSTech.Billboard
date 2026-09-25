import Darwin
import XCTest
@testable import BillboardShared

final class TransportAndImageTests: XCTestCase {
    func testImageValidationAcceptsPNGAndRejectsNonImageData() throws {
        let png = Data(base64Encoded:
            "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNk+A8AAQUBAScY42YAAAAASUVORK5CYII=")!
        let image = try SafeImageLoader.validateAndCreateImage(data: png, maxPixelSize: 64)
        XCTAssertGreaterThan(image.size.width, 0)
        XCTAssertThrowsError(
            try SafeImageLoader.validateAndCreateImage(data: Data("not an image".utf8), maxPixelSize: 64))
    }

    func testRemoteURLPolicyRejectsUnsafeDestinationsBeforeDNS() {
        XCTAssertThrowsError(try RemoteURLPolicy.validate(URL(string: "http://example.com/a.png")!))
        XCTAssertThrowsError(try RemoteURLPolicy.validate(URL(string: "https://user:pass@example.com/a.png")!))
        XCTAssertThrowsError(try RemoteURLPolicy.validate(URL(string: "https://localhost/a.png")!))
        XCTAssertThrowsError(try RemoteURLPolicy.validate(URL(string: "https://example.com:8443/a.png")!))
    }

    func testFIFOTransfersCompleteResult() throws {
        let path = FileManager.default.temporaryDirectory
            .appendingPathComponent("billboard-\(UUID().uuidString).fifo").path
        XCTAssertEqual(mkfifo(path, 0o600), 0)
        defer { unlink(path) }

        let expected = BillboardResult(
            button: "Send",
            value: "send",
            index: 0,
            input: "typed response")
        let writer = expectation(description: "writer")
        DispatchQueue.global().async {
            defer { writer.fulfill() }
            XCTAssertNoThrow(try ResultFIFO.write(result: expected, to: path))
        }

        let data = try ResultFIFO.read(from: path, timeoutSeconds: 2)
        let actual = try BillboardJSON.decoder().decode(BillboardResult.self, from: data)
        XCTAssertEqual(actual.value, "send")
        XCTAssertEqual(actual.input, "typed response")
        wait(for: [writer], timeout: 2)
    }
}
