import Foundation

public enum BillboardTextDirection: Sendable, Equatable {
    case leftToRight
    case rightToLeft
}

public enum TextDirectionService {
    public static func direction(for text: String) -> BillboardTextDirection {
        for scalar in text.unicodeScalars {
            if isRightToLeft(scalar.value) {
                return .rightToLeft
            }
            if scalar.properties.isAlphabetic {
                return .leftToRight
            }
        }
        return .leftToRight
    }

    public static func languageCode(for text: String) -> String {
        for scalar in text.unicodeScalars {
            if (0x0590...0x05FF).contains(scalar.value) {
                return "he"
            }
            if isArabic(scalar.value) {
                return "ar"
            }
        }
        return "en"
    }

    private static func isRightToLeft(_ value: UInt32) -> Bool {
        (0x0590...0x08FF).contains(value) ||
        (0xFB1D...0xFDFF).contains(value) ||
        (0xFE70...0xFEFF).contains(value)
    }

    private static func isArabic(_ value: UInt32) -> Bool {
        (0x0600...0x08FF).contains(value) ||
        (0xFB50...0xFDFF).contains(value) ||
        (0xFE70...0xFEFF).contains(value)
    }
}
