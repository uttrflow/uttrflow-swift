// The main window's greys and the appearance-aware colour helpers.

import AppKit
import SwiftUI

/// The window's own surfaces, named rather than system greys. See Docs/app-main-window.md.
extension Color {
    /// The page behind everything.
    static let mainBackground = Color(nsColor: .orbit(dark: 0x0B_0C10, light: 0xF3_F2F7))
    /// A panel on the page: the clipboard rail, the cards the other pages are made of.
    static let mainCard = Color(nsColor: .orbit(dark: 0x0E_1016, light: 0xFF_FFFF))
    /// Hairlines. Low enough to separate without ruling the page into boxes.
    static let mainSeparator = Color(nsColor: .orbit(dark: 0x1E_212A, light: 0xE2_E0EA))
    /// The row under the pointer.
    static let mainHover = Color(nsColor: .orbitAlpha(dark: 0xFF_FFFF, light: 0x00_0000, alpha: 0.05))
    /// The rail: a step darker than the page in both appearances, so it reads as the edge of the window.
    static let railGround = Color(nsColor: .orbit(dark: 0x08_090C, light: 0xEA_E9F0))
    /// The lit rail icon's tile.
    static let railSelection = Color(nsColor: .orbitAlpha(dark: 0xFF_FFFF, light: 0x00_0000, alpha: 0.07))
    static let railIcon = Color.secondary

    /// The three text tones, set once at the root so every label under it resolves to the design's greys.
    static let mainText = Color(nsColor: .orbit(dark: 0xF4_F4F6, light: 0x17_1320))
    static let mainMuted = Color(nsColor: .orbit(dark: 0x8B_90A0, light: 0x6F_6880))
    static let mainDim = Color(nsColor: .orbit(dark: 0x56_5B68, light: 0xA4_9DB3))
}

/// A hairline in the design's own colour; `Divider()` is a white wash bright enough to make a list a table.
struct MainDivider: View {
    var body: some View {
        Rectangle()
            .fill(Color.mainSeparator)
            .frame(height: 1)
            .accessibilityHidden(true)
    }
}

extension NSColor {
    /// One colour per appearance, resolved when drawn; in code, because this package has no asset catalogue.
    static func orbit(dark: UInt32, light: UInt32) -> NSColor {
        NSColor(name: nil) { appearance in
            NSColor(rgb: appearance.isDark ? dark : light)
        }
    }

    /// The same, for the two places the design asks for a wash rather than a colour.
    static func orbitAlpha(dark: UInt32, light: UInt32, alpha: CGFloat) -> NSColor {
        NSColor(name: nil) { appearance in
            NSColor(rgb: appearance.isDark ? dark : light).withAlphaComponent(alpha)
        }
    }

    /// `0x0B0C10` as an sRGB colour, so the value in the code is the value on the screen.
    convenience init(rgb: UInt32) {
        self.init(
            srgbRed: CGFloat((rgb >> 16) & 0xFF) / 255,
            green: CGFloat((rgb >> 8) & 0xFF) / 255,
            blue: CGFloat(rgb & 0xFF) / 255,
            alpha: 1)
    }
}

extension Color {
    /// `0x0B0C10` as a fixed sRGB colour, the same in both appearances.
    init(rgb: UInt32) {
        self.init(
            .sRGB, red: Double((rgb >> 16) & 0xFF) / 255, green: Double((rgb >> 8) & 0xFF) / 255,
            blue: Double(rgb & 0xFF) / 255)
    }
}

extension NSAppearance {
    /// Whether this appearance is dark, including the accessibility variants `name == .darkAqua` misses.
    var isDark: Bool {
        bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
    }
}
