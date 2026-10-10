// The main window's greys and the appearance-aware colour helpers.

import AppKit
import SwiftUI

/// The window's own surfaces, named rather than system greys. See Docs/app-main-window.md.
extension Color {
    /// The page behind everything.
    static let mainBackground = Color(nsColor: .orbit(BrandPalette.Surface.ground))
    /// A panel on the page: the clipboard rail, the cards the other pages are made of.
    static let mainCard = Color(nsColor: .orbit(BrandPalette.Surface.card))
    /// Hairlines. Low enough to separate without ruling the page into boxes.
    static let mainSeparator = Color(nsColor: .orbit(BrandPalette.Line.separator))
    /// The row under the pointer.
    static let mainHover = Color(
        nsColor: .orbitAlpha(
            BrandPalette.Surface.wash, alpha: 0.05, highContrastAlpha: 0.14))
    /// The rail: a step darker than the page in both appearances, so it reads as the edge of the window.
    static let railGround = Color(nsColor: .orbit(BrandPalette.Surface.rail))
    /// The lit rail icon's tile.
    static let railSelection = Color(
        nsColor: .orbitAlpha(
            BrandPalette.Surface.wash, alpha: 0.07, highContrastAlpha: 0.18))
    static let railIcon = Color.secondary

    /// The three text tones, set once at the root so every label under it resolves to the design's greys.
    static let mainText = Color(nsColor: .orbit(BrandPalette.Text.primary))
    static let mainMuted = Color(nsColor: .orbit(BrandPalette.Text.muted))
    static let mainDim = Color(nsColor: .orbit(BrandPalette.Text.dim))
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
    static func orbit(
        dark: UInt32, light: UInt32, highContrastDark: UInt32? = nil, highContrastLight: UInt32? = nil
    ) -> NSColor {
        orbit(
            BrandTone(
                dark: dark, light: light, highContrastDark: highContrastDark,
                highContrastLight: highContrastLight))
    }

    /// The same, for the two places the design asks for a wash rather than a colour.
    static func orbitAlpha(
        dark: UInt32, light: UInt32, highContrastDark: UInt32? = nil, highContrastLight: UInt32? = nil,
        alpha: CGFloat, highContrastAlpha: CGFloat? = nil
    ) -> NSColor {
        orbitAlpha(
            BrandTone(
                dark: dark, light: light, highContrastDark: highContrastDark,
                highContrastLight: highContrastLight),
            alpha: alpha, highContrastAlpha: highContrastAlpha)
    }

    /// A palette tone, resolved per appearance.
    static func orbit(_ tone: BrandTone) -> NSColor {
        NSColor(name: nil) { orbit(tone, in: $0.orbitVariant) }
    }

    /// A palette tone as one appearance variant draws it.
    static func orbit(_ tone: BrandTone, in variant: NSAppearance.Name) -> NSColor {
        NSColor(
            rgb: variant.highContrastValue(dark: tone.highContrastDark, light: tone.highContrastLight)
                ?? (variant.isDarkVariant ? tone.dark : tone.light))
    }

    /// A palette tone as a wash.
    static func orbitAlpha(_ tone: BrandTone, alpha: CGFloat, highContrastAlpha: CGFloat? = nil) -> NSColor {
        NSColor(name: nil) {
            orbitAlpha(tone, alpha: alpha, highContrastAlpha: highContrastAlpha, in: $0.orbitVariant)
        }
    }

    /// A palette wash as one appearance variant draws it.
    static func orbitAlpha(
        _ tone: BrandTone, alpha: CGFloat, highContrastAlpha: CGFloat? = nil, in variant: NSAppearance.Name
    ) -> NSColor {
        orbit(tone, in: variant).withAlphaComponent(
            variant.highContrastValue(dark: highContrastAlpha, light: highContrastAlpha) ?? alpha)
    }

    /// A palette layer, resolved per appearance at that appearance's own opacity.
    static func orbit(_ layer: BrandLayer) -> NSColor {
        NSColor(name: nil) { orbit(layer, in: $0.orbitVariant) }
    }

    /// A palette layer as one appearance variant draws it.
    static func orbit(_ layer: BrandLayer, in variant: NSAppearance.Name) -> NSColor {
        let opacity =
            variant.highContrastValue(
                dark: layer.highContrastDarkOpacity, light: layer.highContrastLightOpacity)
            ?? (variant.isDarkVariant ? layer.darkOpacity : layer.lightOpacity)
        return orbit(layer.tone, in: variant).withAlphaComponent(opacity)
    }

    /// A hex as an sRGB colour, so the value in the code is the value on the screen.
    convenience init(rgb: UInt32) {
        self.init(
            srgbRed: CGFloat((rgb >> 16) & 0xFF) / 255,
            green: CGFloat((rgb >> 8) & 0xFF) / 255,
            blue: CGFloat(rgb & 0xFF) / 255,
            alpha: 1)
    }
}

extension Color {
    /// A hex as a fixed sRGB colour, the same in both appearances.
    init(rgb: UInt32) {
        self.init(
            .sRGB, red: Double((rgb >> 16) & 0xFF) / 255, green: Double((rgb >> 8) & 0xFF) / 255,
            blue: Double(rgb & 0xFF) / 255)
    }
}

extension NSColor {
    /// The settings callout's ground, dark on dark: a fixed near-white hid the ink. See #147.
    static let settingsCalloutWash = NSColor.orbit(BrandPalette.Teal.calloutWash)
}

extension NSAppearance {
    /// Which of the four palette variants this appearance draws with; `NSAppearance(named:)` never builds a high-contrast one.
    var orbitVariant: NSAppearance.Name {
        bestMatch(from: [
            .aqua, .darkAqua, .accessibilityHighContrastAqua, .accessibilityHighContrastDarkAqua,
        ]) ?? .aqua
    }

    /// Whether this appearance is dark, including the accessibility variants `name == .darkAqua` misses.
    var isDark: Bool {
        orbitVariant.isDarkVariant
    }
}

extension NSAppearance.Name {
    /// The value for this variant's high contrast, or nil when contrast is not increased.
    func highContrastValue<Value>(dark: Value?, light: Value?) -> Value? {
        switch self {
        case .accessibilityHighContrastAqua: light
        case .accessibilityHighContrastDarkAqua: dark
        default: nil
        }
    }

    /// Whether this palette variant is one of the two dark ones.
    var isDarkVariant: Bool {
        self == .darkAqua || self == .accessibilityHighContrastDarkAqua
    }
}
