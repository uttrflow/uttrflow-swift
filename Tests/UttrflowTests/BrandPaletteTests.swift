// Tests for the brand palette.

import Foundation
import Testing

@testable import Uttrflow

@Suite("The brand palette")
struct BrandPaletteTests {
    @Test("holds the primary teal and the secondary purple the brand is drawn in")
    func keyValues() {
        #expect(BrandPalette.Teal.primary == 0x29_C0B4)
        #expect(BrandPalette.Purple.secondary == 0x61_399F)
        #expect(BrandPalette.Purple.secondaryMiddle == 0x3E_368A)
        #expect(BrandPalette.Purple.secondaryEnd == 0x2A_5B72)
    }

    @Test("a fixed tone carries the same value in both appearances")
    func fixedTone() {
        let tone = BrandTone(0x12_151C)

        #expect(tone.dark == 0x12_151C)
        #expect(tone.light == 0x12_151C)
    }

    @Test("a pair that shares a member with the ramp points at that member")
    func pairsReuseTheRamp() {
        #expect(BrandPalette.Teal.ink.dark == BrandPalette.Teal.bright)
        #expect(BrandPalette.Teal.calloutWash.light == BrandPalette.Teal.wash)
        #expect(BrandPalette.Surface.control.dark == BrandPalette.Surface.raised)
        #expect(BrandPalette.Surface.onboardingControl.dark == BrandPalette.Surface.raised)
    }
}

/// Text drawn in a semantic colour is read, so it clears WCAG AA wherever it is drawn.
@Suite("The semantic text inks")
struct SemanticInkContrastTests {
    /// Every ink that draws text, by name.
    static let inks: [(String, BrandTone)] = [
        ("warning", BrandPalette.Semantic.warningInk),
        ("success", BrandPalette.Semantic.successInk),
        ("critical", BrandPalette.Semantic.criticalInk),
        ("accent", BrandPalette.Teal.ink),
    ]

    /// The share of the ink in a pill's wash, as `MainTone.background` draws it.
    static let pillWash = 0.16

    /// The WCAG 2.x relative luminance of an sRGB hex.
    static func luminance(_ hex: UInt32) -> Double {
        func linear(_ channel: UInt32) -> Double {
            let value = Double(channel) / 255
            return value <= 0.04045 ? value / 12.92 : pow((value + 0.055) / 1.055, 2.4)
        }
        return 0.2126 * linear(hex >> 16 & 0xFF) + 0.7152 * linear(hex >> 8 & 0xFF)
            + 0.0722 * linear(hex & 0xFF)
    }

    /// The WCAG 2.x contrast ratio between two sRGB hexes.
    static func contrast(_ first: UInt32, _ second: UInt32) -> Double {
        let (a, b) = (luminance(first), luminance(second))
        return (max(a, b) + 0.05) / (min(a, b) + 0.05)
    }

    /// `ink` laid over `ground` at `share` opacity, channel by channel.
    static func wash(_ ink: UInt32, over ground: UInt32, share: Double) -> UInt32 {
        [16, 8, 0].reduce(0) { total, shift in
            let top = Double(ink >> UInt32(shift) & 0xFF)
            let bottom = Double(ground >> UInt32(shift) & 0xFF)
            return total | UInt32((top * share + bottom * (1 - share)).rounded()) << UInt32(shift)
        }
    }

    @Test("every text ink clears 4.5:1 on a card, the ground and its own pill wash, in both appearances")
    func inksClearAA() {
        let surfaces = [BrandPalette.Surface.card, BrandPalette.Surface.ground]
        for (name, ink) in Self.inks {
            for surface in surfaces {
                for (colour, ground) in [(ink.dark, surface.dark), (ink.light, surface.light)] {
                    let plain = Self.contrast(colour, ground)
                    let pill = Self.contrast(colour, Self.wash(colour, over: ground, share: Self.pillWash))
                    #expect(plain >= 4.5, "\(name) on \(String(ground, radix: 16)) is \(plain)")
                    #expect(pill >= 4.5, "\(name) pill on \(String(ground, radix: 16)) is \(pill)")
                }
            }
        }
    }

    @Test("the fixed fills the inks replace fail on a light card, which is why text does not use them")
    func fillsFailAsText() {
        let card = BrandPalette.Surface.card.light
        #expect(Self.contrast(BrandPalette.Semantic.warning, card) < 4.5)
        #expect(Self.contrast(BrandPalette.Semantic.success, card) < 4.5)
        #expect(Self.contrast(BrandPalette.Semantic.recording, card) < 4.5)
    }

    @Test("the contrast arithmetic agrees with the known extremes")
    func arithmetic() {
        #expect(abs(Self.contrast(0x00_0000, 0xFF_FFFF) - 21) < 0.001)
        #expect(Self.contrast(0x12_3456, 0x12_3456) == 1)
        #expect(Self.wash(0xFF_FFFF, over: 0x00_0000, share: 0.5) == 0x80_8080)
    }
}
