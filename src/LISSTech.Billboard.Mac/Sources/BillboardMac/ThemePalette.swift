import SwiftUI
import BillboardShared

struct ThemePalette {
    let background: [Color]
    let primary: Color
    let body: Color
    let accent: Color
    let accentHover: Color
    let accentText: Color
    let border: Color
    let header: Color
    let input: Color
    let isDark: Bool
    let animated: Bool

    static func resolve(_ requested: ThemeMode, scheme: ColorScheme) -> ThemePalette {
        let theme: ThemeMode = requested == .auto
            ? (scheme == .dark ? .dark : .light)
            : requested
        switch theme {
        case .auto:
            return resolve(.dark, scheme: scheme)
        case .light:
            return ThemePalette(
                background: [Color(hex: 0xF7F8FC), Color(hex: 0xE9EEF8)],
                primary: Color(hex: 0x111111),
                body: Color(hex: 0x444444),
                accent: Color(hex: 0x2E71B8),
                accentHover: Color(hex: 0x3A80C8),
                accentText: .white,
                border: Color(hex: 0x8CAFD2),
                header: Color(hex: 0xDFEAF6),
                input: .white.opacity(0.82),
                isDark: false,
                animated: false)
        case .dark:
            return ThemePalette(
                background: [Color(hex: 0x171923), Color(hex: 0x20283A)],
                primary: .white,
                body: .white.opacity(0.76),
                accent: Color(hex: 0x4C91D8),
                accentHover: Color(hex: 0x63A4E6),
                accentText: .white,
                border: Color(hex: 0x315C88),
                header: .white.opacity(0.07),
                input: .black.opacity(0.22),
                isDark: true,
                animated: false)
        case .starryNight:
            return ThemePalette(
                background: [Color(hex: 0x0A1733), Color(hex: 0x1E4D73), Color(hex: 0x53632B)],
                primary: Color(hex: 0xFFF3BF),
                body: Color(hex: 0xD9E6F2),
                accent: Color(hex: 0xE0B84B),
                accentHover: Color(hex: 0xF0C95A),
                accentText: .black,
                border: Color(hex: 0xD9B44A),
                header: Color(hex: 0x79A7D3).opacity(0.18),
                input: .black.opacity(0.24),
                isDark: true,
                animated: true)
        case .waterLilies:
            return ThemePalette(
                background: [Color(hex: 0xF2E9D8), Color(hex: 0xC7D8C0), Color(hex: 0xAFC8D7), Color(hex: 0xB8A5C2)],
                primary: Color(hex: 0x24362F),
                body: Color(hex: 0x40574E),
                accent: Color(hex: 0x6D7F73),
                accentHover: Color(hex: 0x7F9487),
                accentText: .white,
                border: Color(hex: 0x6E8F82),
                header: Color(hex: 0x8E6B8A).opacity(0.24),
                input: .white.opacity(0.72),
                isDark: false,
                animated: true)
        case .greatWave:
            return ThemePalette(
                background: [Color(hex: 0x0A2942), Color(hex: 0x145A78), Color(hex: 0x527E88), Color(hex: 0x5F7772)],
                primary: Color(hex: 0xFFF8E8),
                body: Color(hex: 0xD9E8EC),
                accent: Color(hex: 0xE8DDBD),
                accentHover: Color(hex: 0xF5EBD0),
                accentText: .black,
                border: Color(hex: 0xE8DDBD),
                header: Color(hex: 0x6CB4C6).opacity(0.18),
                input: .black.opacity(0.24),
                isDark: true,
                animated: true)
        }
    }
}

extension Color {
    init(hex: UInt32) {
        self.init(
            red: Double((hex >> 16) & 0xFF) / 255,
            green: Double((hex >> 8) & 0xFF) / 255,
            blue: Double(hex & 0xFF) / 255)
    }
}
