import XCTest
@testable import BillboardShared

final class RichTextTests: XCTestCase {
    func testMarkdownImagesBecomeInertAltText() {
        let sanitized = RichTextRenderer.sanitizeImages("Before ![diagram](https://example.com/a.png) after")
        XCTAssertEqual(sanitized, "Before [Image: diagram] after")
    }

    func testUnsafeLinksDoNotRemainClickable() {
        let rendered = RichTextRenderer.render("[bad](file:///etc/passwd) [good](https://example.com/help)")
        let links = rendered.runs.compactMap(\.link)
        XCTAssertEqual(links, [URL(string: "https://example.com/help")!])
    }

    func testBareHTTPSURLBecomesClickableButHTTPDoesNot() {
        let rendered = RichTextRenderer.render("https://example.com/help and http://example.com/plain")
        let links = rendered.runs.compactMap(\.link)
        XCTAssertTrue(links.contains(URL(string: "https://example.com/help")!))
        XCTAssertFalse(links.contains(URL(string: "http://example.com/plain")!))
    }

    func testTextDirectionUsesFirstStrongCharacter() {
        XCTAssertEqual(TextDirectionService.direction(for: "123 مرحبا بالعالم"), .rightToLeft)
        XCTAssertEqual(TextDirectionService.direction(for: "Status الحالة"), .leftToRight)
        XCTAssertEqual(TextDirectionService.languageCode(for: "שלום"), "he")
        XCTAssertEqual(TextDirectionService.languageCode(for: "مرحبا"), "ar")
    }
}
