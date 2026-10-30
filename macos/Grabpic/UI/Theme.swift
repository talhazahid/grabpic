import SwiftUI
import AppKit

/// Shared visual tokens from DESIGN.md, expressed in macOS points.
enum Theme {
    static let canvas = Color(hex: 0x14151B)
    static let sidebar = Color(hex: 0x191A22)
    static let heroTop = Color(hex: 0x2B2740)
    static let heroBottom = Color(hex: 0x232030)
    static let card = Color(hex: 0x1D1E28)
    static let cardRaised = Color(hex: 0x232430)
    static let cardHover = Color(hex: 0x242532)
    static let selection = Color(hex: 0x343049)
    static let shortcutField = Color(hex: 0x2B283B)
    static let ink = Color(hex: 0xEEEFF5)
    static let muted = Color(hex: 0xA3A4B5)
    static let accent = Color(hex: 0xA294FA)
    static let border = Color(hex: 0x30313E)
    static let borderStrong = Color(hex: 0x353645)
    static let heroBody = Color(hex: 0xC1BCD8)
    static let heroMeta = Color(hex: 0xADA3D0)
    static let thumb = Color(hex: 0x292A36)
    static let success = Color(hex: 0x8FD3B6)
    static let warning = Color(hex: 0xE3B77E)

    static let cardRadius: CGFloat = 12
    static let controlRadius: CGFloat = 8
    static let sidebarWidth: CGFloat = 212

    static func font(_ size: CGFloat) -> Font {
        .system(size: size, weight: .regular, design: .default)
    }

    static func uppercase(_ size: CGFloat = 10) -> Font {
        .system(size: size, weight: .regular, design: .default)
    }
}

extension Color {
    init(hex: UInt32) {
        self.init(
            .sRGB,
            red: Double((hex >> 16) & 0xFF) / 255,
            green: Double((hex >> 8) & 0xFF) / 255,
            blue: Double(hex & 0xFF) / 255,
            opacity: 1
        )
    }
}

extension NSColor {
    static let gpCanvas = NSColor(srgbRed: 0x14 / 255, green: 0x15 / 255, blue: 0x1B / 255, alpha: 1)
    static let gpInk = NSColor(srgbRed: 0xEE / 255, green: 0xEF / 255, blue: 0xF5 / 255, alpha: 1)
    static let gpMuted = NSColor(srgbRed: 0xA3 / 255, green: 0xA4 / 255, blue: 0xB5 / 255, alpha: 1)
    static let gpAccent = NSColor(srgbRed: 0xA2 / 255, green: 0x94 / 255, blue: 0xFA / 255, alpha: 1)
    static let gpPill = NSColor(srgbRed: 0x23 / 255, green: 0x24 / 255, blue: 0x30 / 255, alpha: 0.94)
}
