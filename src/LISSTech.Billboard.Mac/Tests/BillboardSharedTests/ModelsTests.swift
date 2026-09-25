import XCTest
@testable import BillboardShared

final class ModelsTests: XCTestCase {
    func testDecodingAppliesDefaultsAndNormalizesQuestionButton() throws {
        let data = Data(#"{"Type":"QUESTION","Title":"Restart","Message":"Save work","Modal":true}"#.utf8)
        var config = try BillboardJSON.decoder().decode(BillboardConfig.self, from: data)

        XCTAssertEqual(config.type, .question)
        XCTAssertEqual(config.theme, .auto)
        XCTAssertEqual(config.effectiveTimeout, 0)
        XCTAssertTrue(config.buttons.isEmpty)

        try config.validateAndNormalize()
        XCTAssertEqual(config.buttons.count, 1)
        XCTAssertEqual(config.buttons[0].label, "OK")
        XCTAssertEqual(config.buttons[0].value, "ok")
        XCTAssertEqual(config.buttons[0].style, .primary)
    }

    func testInputRequiresModalAndValidMaximumLength() {
        var toast = BillboardConfig(
            type: .question,
            title: "Response",
            message: "Enter a response",
            input: InputDefinition(required: true))
        XCTAssertThrowsError(try toast.validateAndNormalize())

        var modal = BillboardConfig(
            type: .question,
            title: "Response",
            message: "Enter a response",
            modal: true,
            input: InputDefinition(defaultValue: "four", maxLength: 3))
        XCTAssertThrowsError(try modal.validateAndNormalize())
    }

    func testSnakeCaseResultRoundTripPreservesInput() throws {
        let timestamp = Date(timeIntervalSince1970: 1_700_000_000)
        let result = BillboardResult(
            button: "Send",
            value: "send",
            index: 0,
            dismissed: false,
            timeout: false,
            deferSeconds: 3600,
            input: "مرحبا",
            timestamp: timestamp)

        let data = try BillboardJSON.encoder().encode(result)
        let json = String(decoding: data, as: UTF8.self)
        XCTAssertTrue(json.contains("\"defer\":3600"))
        XCTAssertTrue(json.contains("\"input\":\"مرحبا\""))

        let decoded = try BillboardJSON.decoder().decode(BillboardResult.self, from: data)
        XCTAssertEqual(decoded.input, result.input)
        XCTAssertEqual(decoded.deferSeconds, result.deferSeconds)
        XCTAssertEqual(decoded.timestamp, timestamp)
    }
}
