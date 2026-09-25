import Foundation

public enum RichTextRenderer {
    private static let imageExpression = try! NSRegularExpression(
        pattern: #"!\[([^\]]*)\]\([^\)]*\)"#)

    public static func render(_ markdown: String) -> AttributedString {
        let source = sanitizeImages(markdown)
        var attributed = (try? AttributedString(
            markdown: source,
            options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace)))
            ?? AttributedString(source)

        var invalidRanges: [Range<AttributedString.Index>] = []
        for run in attributed.runs {
            guard let link = run.link else { continue }
            if !isAllowedLink(link) {
                invalidRanges.append(run.range)
            }
        }
        for range in invalidRanges {
            attributed[range].link = nil
        }

        addBareHTTPSLinks(to: &attributed)
        return attributed
    }

    public static func sanitizeImages(_ markdown: String) -> String {
        let range = NSRange(markdown.startIndex..<markdown.endIndex, in: markdown)
        return imageExpression.stringByReplacingMatches(
            in: markdown,
            range: range,
            withTemplate: "[Image: $1]")
    }

    public static func isAllowedLink(_ url: URL) -> Bool {
        guard let scheme = url.scheme?.lowercased(),
              scheme == "https" || scheme == "http",
              url.user == nil,
              url.password == nil,
              url.absoluteString.count <= 2048 else {
            return false
        }
        return url.host?.isEmpty == false
    }

    private static func addBareHTTPSLinks(to attributed: inout AttributedString) {
        let plain = String(attributed.characters)
        guard let detector = try? NSDataDetector(
            types: NSTextCheckingResult.CheckingType.link.rawValue) else {
            return
        }
        let matches = detector.matches(
            in: plain,
            range: NSRange(plain.startIndex..<plain.endIndex, in: plain))

        for match in matches {
            guard let url = match.url,
                  url.scheme?.lowercased() == "https",
                  isAllowedLink(url),
                  let stringRange = Range(match.range, in: plain) else {
                continue
            }
            let lowerOffset = plain.distance(from: plain.startIndex, to: stringRange.lowerBound)
            let upperOffset = plain.distance(from: plain.startIndex, to: stringRange.upperBound)
            guard let lower = attributed.characters.index(
                attributed.characters.startIndex,
                offsetBy: lowerOffset,
                limitedBy: attributed.characters.endIndex),
                  let upper = attributed.characters.index(
                    attributed.characters.startIndex,
                    offsetBy: upperOffset,
                    limitedBy: attributed.characters.endIndex) else {
                continue
            }
            attributed[lower..<upper].link = url
        }
    }
}
