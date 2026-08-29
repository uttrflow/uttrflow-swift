import AppKit
import SwiftUI

/// The window's own surfaces.
///
/// These were `windowBackgroundColor`, `controlBackgroundColor` and
/// `underPageBackgroundColor` — Apple's neutral greys — and against the design they were
/// wrong in three ways at once. In dark aqua they render `#1E1E1E`, a good deal lighter
/// than the `#0B0C10` the artboards are drawn on and neutral where the design is cool;
/// and `underPageBackgroundColor` is *lighter* than the window, so the rail lifted off
/// the page where the design sinks it.
///
/// Named values rather than system ones, then, for the same reason the ring's colours
/// are named: this window's grounds are part of the design, not a place to inherit
/// whatever the platform's document windows happen to use. The light variant is derived
/// from the same decisions rather than being the system's again — the rail one step
/// darker than the page, the card one step lighter.
extension Color {
    /// The page behind everything.
    static let mainBackground = Color(nsColor: .orbit(dark: 0x0B_0C10, light: 0xF3_F2F7))
    /// A panel on the page: the clipboard rail, the cards the other pages are made of.
    static let mainCard = Color(nsColor: .orbit(dark: 0x0E_1016, light: 0xFF_FFFF))
    /// Hairlines. Low enough to separate without ruling the page into boxes.
    static let mainSeparator = Color(nsColor: .orbit(dark: 0x1E_212A, light: 0xE2_E0EA))
    /// The row under the pointer.
    static let mainHover = Color(nsColor: .orbitAlpha(dark: 0xFF_FFFF, light: 0x00_0000, alpha: 0.05))
    /// The rail: a step darker than the page in the dark, a step darker in the light too,
    /// so it reads as the edge of the window either way.
    static let railGround = Color(nsColor: .orbit(dark: 0x08_090C, light: 0xEA_E9F0))
    /// The lit rail icon's tile.
    static let railSelection = Color(nsColor: .orbitAlpha(dark: 0xFF_FFFF, light: 0x00_0000, alpha: 0.07))
    static let railIcon = Color.secondary

    /// The three text tones, applied once at the window's root so that every
    /// `.primary`, `.secondary` and `.tertiary` under it resolves to these.
    ///
    /// The system's are neutral greys; the design's carry the same cool cast as the
    /// grounds they sit on, which is what stops a caption reading as slightly warm
    /// against a slightly blue panel. Setting all three at the root rather than colouring
    /// each label means a page cannot opt out of the palette by accident.
    static let mainText = Color(nsColor: .orbit(dark: 0xF4_F4F6, light: 0x17_1320))
    static let mainMuted = Color(nsColor: .orbit(dark: 0x8B_90A0, light: 0x6F_6880))
    static let mainDim = Color(nsColor: .orbit(dark: 0x56_5B68, light: 0xA4_9DB3))
}

/// A hairline in the design's own colour.
///
/// `Divider()` draws the system's separator, which is a white wash: on `#0B0C10` it is
/// brighter than the `#1E212A` the artboards rule the page with, and bright enough that
/// a list of ten rows reads as a table.
struct MainDivider: View {
    var body: some View {
        Rectangle()
            .fill(Color.mainSeparator)
            .frame(height: 1)
            .accessibilityHidden(true)
    }
}

extension NSColor {
    /// One colour per appearance, resolved when it is drawn rather than when it is made.
    ///
    /// `NSColor(name:dynamicProvider:)` rather than an asset catalogue: this package has
    /// no catalogue, and a value in code is the only form the tests and the design notes
    /// can both point at.
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

    /// `0x0B0C10` as a colour. sRGB rather than device, so the value in the code is the
    /// value on the screen.
    convenience init(rgb: UInt32) {
        self.init(
            srgbRed: CGFloat((rgb >> 16) & 0xFF) / 255,
            green: CGFloat((rgb >> 8) & 0xFF) / 255,
            blue: CGFloat(rgb & 0xFF) / 255,
            alpha: 1)
    }
}

extension NSAppearance {
    /// Whether this appearance is one of the dark ones, including the accessibility
    /// variants — which `name == .darkAqua` alone would answer wrongly.
    var isDark: Bool {
        bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
    }
}
