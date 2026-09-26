// Tests that the dock's status colours clear the contrast minimums on both desktops.

import Foundation
import Testing

@testable import Uttrflow

/// The WCAG relative luminance of an sRGB hex.
private func luminance(_ hex: UInt32) -> Double {
    let channels = [(hex >> 16) & 0xFF, (hex >> 8) & 0xFF, hex & 0xFF].map { Double($0) / 255 }
    let linear = channels.map { $0 <= 0.039_28 ? $0 / 12.92 : pow(($0 + 0.055) / 1.055, 2.4) }
    return 0.2126 * linear[0] + 0.7152 * linear[1] + 0.0722 * linear[2]
}

/// The WCAG contrast ratio between two sRGB hexes, lighter over darker.
private func ratio(_ first: UInt32, _ second: UInt32) -> Double {
    let (a, b) = (luminance(first), luminance(second))
    return (max(a, b) + 0.05) / (min(a, b) + 0.05)
}

/// The glass over a light desktop and over a dark one, as `Docs/app-dock.md` measures against.
private let lightGlass: UInt32 = 0xEE_EEEE
private let darkGlass: UInt32 = 0x26_2626
private let white: UInt32 = 0xFF_FFFF

/// An sRGB hex painted over another at the given opacity, rounded per channel.
private func composed(_ top: UInt32, _ opacity: Double, over bottom: UInt32) -> UInt32 {
    [16, 8, 0].reduce(0) { hex, shift in
        let (a, b) = (Double((top >> shift) & 0xFF), Double((bottom >> shift) & 0xFF))
        return hex | UInt32((a * opacity + b * (1 - opacity)).rounded()) << shift
    }
}

/// The keycap's `.primary.opacity(0.14)` over each glass: black on light, white on dark.
private let lightKeycap = composed(0x00_0000, 0.14, over: lightGlass)
private let darkKeycap = composed(white, 0.14, over: darkGlass)

@Suite("The dock's status colours are legible on either desktop")
struct DockContrastTests {
    @Test("the formula matches the published extremes")
    func formula() {
        #expect(abs(ratio(0x00_0000, white) - 21) < 0.01)
        #expect(ratio(white, white) == 1)
    }

    @Test("the failure disc's white glyph clears 3:1, and the disc clears 3:1 against the glass")
    func failureBadge() {
        let fill = BrandPalette.Semantic.warningFill
        #expect(ratio(white, fill) >= 3)
        #expect(ratio(fill, lightGlass) >= 3)
        #expect(ratio(fill, darkGlass) >= 3)
    }

    @Test("the copied keycap's text clears 4.5:1 against its composed surface")
    func keycapText() {
        let ink = BrandPalette.Semantic.cautionInk
        #expect(ratio(ink.light, lightKeycap) >= 4.5)
        #expect(ratio(ink.dark, darkKeycap) >= 4.5)
    }

    @Test("the inserted tick clears 3:1 on a light desktop and a dark one")
    func insertedTick() {
        let tick = BrandPalette.Semantic.successInk
        #expect(ratio(tick.light, lightGlass) >= 3)
        #expect(ratio(tick.dark, darkGlass) >= 3)
    }

    /// The tones these replace on the dock, which is the failure the issue measured.
    @Test("the bright tones they replace fail on a light desktop")
    func brightTonesFail() {
        #expect(ratio(white, BrandPalette.Semantic.warning) < 3)
        #expect(ratio(BrandPalette.Semantic.warning, lightGlass) < 4.5)
        #expect(ratio(BrandPalette.Semantic.success, lightGlass) < 3)
    }
}
