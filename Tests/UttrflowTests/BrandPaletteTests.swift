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
        #expect(BrandPalette.Onboarding.brandAurora == BrandPalette.Redesign.auroraStops)
        #expect(BrandPalette.Onboarding.caret == BrandPalette.Teal.deep)
    }
}

/// Every tone that draws text is read, so it clears WCAG AA on every surface it is drawn on.
@Suite("The text tone ramp")
struct TextToneContrastTests {
    /// The tones that reach text, strongest first; nothing dimmer than `dim` may carry words.
    static let tones: [(String, BrandTone)] = [
        ("primary", BrandPalette.Text.primary),
        ("muted", BrandPalette.Text.muted),
        ("dim", BrandPalette.Text.dim),
    ]

    /// Every surface text sits on, the rail included: the sidebar draws its version and badges there.
    static let surfaces: [(String, BrandTone)] = [
        ("ground", BrandPalette.Surface.ground),
        ("card", BrandPalette.Surface.card),
        ("control", BrandPalette.Surface.control),
        ("rail", BrandPalette.Surface.rail),
    ]

    @Test("every text tone clears 4.5:1 on every surface, in both appearances")
    func tonesClearAA() {
        for (tone, colour) in Self.tones {
            for (surface, ground) in Self.surfaces {
                for (appearance, pair) in [
                    ("dark", (colour.dark, ground.dark)), ("light", (colour.light, ground.light)),
                ] {
                    let measured = contrastRatio(pair.0, pair.1)
                    #expect(measured >= 4.5, "\(tone) on \(appearance) \(surface) is \(measured)")
                }
            }
        }
    }

    @Test("the ramp only ever weakens, so a dimmer name is never the stronger colour")
    func rampIsOrdered() {
        let dark = Self.tones.map { relativeLuminance($0.1.dark) }
        let light = Self.tones.map { relativeLuminance($0.1.light) }

        // Strength is lightness on a dark desktop and darkness on a light one.
        #expect(dark == dark.sorted(by: >))
        #expect(light == light.sorted(by: <))
        #expect(relativeLuminance(BrandPalette.Text.ghost) < dark.last ?? 0)
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

    @Test("every text ink clears 4.5:1 on a card, the ground and its own pill wash, in both appearances")
    func inksClearAA() {
        let surfaces = [BrandPalette.Surface.card, BrandPalette.Surface.ground]
        for (name, ink) in Self.inks {
            for surface in surfaces {
                for (colour, ground) in [(ink.dark, surface.dark), (ink.light, surface.light)] {
                    let plain = contrastRatio(colour, ground)
                    let washed = blend(colour, over: ground, share: Self.pillWash)
                    let pill = contrastRatio(colour, washed)
                    #expect(plain >= 4.5, "\(name) on \(String(ground, radix: 16)) is \(plain)")
                    #expect(pill >= 4.5, "\(name) pill on \(String(ground, radix: 16)) is \(pill)")
                }
            }
        }
    }

    @Test("the fixed fills the inks replace fail on a light card, which is why text does not use them")
    func fillsFailAsText() {
        let card = BrandPalette.Surface.card.light
        #expect(contrastRatio(BrandPalette.Semantic.warning, card) < 4.5)
        #expect(contrastRatio(BrandPalette.Semantic.success, card) < 4.5)
        #expect(contrastRatio(BrandPalette.Semantic.recording, card) < 4.5)
    }

    @Test("the page header's kicker ink clears 4.5:1 on the redesigned window, where the fixed teal does not")
    func kickerClearsAAOnWindow() {
        let window = BrandPalette.Redesign.windowGround
        let ink = BrandPalette.Teal.ink
        #expect(contrastRatio(ink.light, window.light) >= 4.5)
        #expect(contrastRatio(ink.dark, window.dark) >= 4.5)
        #expect(contrastRatio(BrandPalette.Teal.primary, window.light) < 4.5)
    }

    @Test("the contrast arithmetic agrees with the known extremes")
    func arithmetic() {
        #expect(abs(contrastRatio(0x00_0000, 0xFF_FFFF) - 21) < 0.001)
        #expect(contrastRatio(0x12_3456, 0x12_3456) == 1)
        #expect(blend(0xFF_FFFF, over: 0x00_0000, share: 0.5) == 0x80_8080)
    }
}

/// The redesign's tokens are read against the grounds they will sit on.
@Suite("The redesign tokens")
struct RedesignTokenTests {
    typealias R = BrandPalette.Redesign

    /// A layer composited over a ground, per appearance.
    static func composite(_ layer: BrandLayer, over ground: BrandTone) -> BrandTone {
        BrandTone(
            dark: blend(layer.tone.dark, over: ground.dark, share: layer.darkOpacity),
            light: blend(layer.tone.light, over: ground.light, share: layer.lightOpacity))
    }

    /// The page and a card on it, in both appearances.
    static let grounds: [(String, BrandTone)] = [
        ("page", R.pageGround),
        ("window", R.windowGround),
        ("card", composite(R.cardFill, over: R.windowGround)),
    ]

    @Test("holds the page and window grounds and the aurora stops")
    func keyValues() {
        #expect(R.pageGround == BrandTone(dark: 0x0B_0C10, light: 0xF2_F1EC))
        #expect(R.windowGround.dark == 0x0C_0D14)
        #expect(R.auroraStops == [0x7A_3FD1, 0x4B_3FC0, 0x1F_8FB0, 0x2F_E0CF])
        #expect(R.cardFill.lightOpacity == 1)
        #expect(R.sidebarIsland.tone.light == 0x12_101E)
    }

    @Test("every text tone clears 4.5:1 on the page, the window and a card, in both appearances")
    func textClearsAA() {
        let texts: [(String, BrandTone)] = [
            ("strong", R.textStrong),
            ("soft", Self.composite(R.textSoft, over: R.windowGround)),
            ("quiet", Self.composite(R.textQuiet, over: R.windowGround)),
        ]
        for (name, text) in texts {
            for (surface, ground) in Self.grounds {
                let dark = contrastRatio(text.dark, ground.dark)
                let light = contrastRatio(text.light, ground.light)
                #expect(dark >= 4.5, "\(name) on dark \(surface) is \(dark)")
                #expect(light >= 4.5, "\(name) on light \(surface) is \(light)")
            }
        }
    }

    @Test("every role accent clears the 3:1 a mark needs on the page and a card")
    func accentsClearMarks() {
        for accent in [R.dictationAccent, R.suggestionAccent, R.clipboardAccent, R.infoAccent] {
            for (surface, ground) in Self.grounds {
                #expect(contrastRatio(accent.dark, ground.dark) >= 3, "dark \(surface)")
                #expect(contrastRatio(accent.light, ground.light) >= 3, "light \(surface)")
            }
        }
    }

    @Test("the settings accents clear 3:1 as marks, and their inks 4.5:1 as words, on the page and a card")
    func settingsAccentsAreLegible() {
        let marks = [
            R.mintAccent, R.neutralAccent, R.dictationDeep, BrandPalette.Semantic.criticalInk,
            BrandPalette.Semantic.successInk,
        ]
        for accent in marks {
            for (surface, ground) in Self.grounds {
                #expect(contrastRatio(accent.dark, ground.dark) >= 3, "dark \(surface)")
                #expect(contrastRatio(accent.light, ground.light) >= 3, "light \(surface)")
            }
        }
        for ink in [R.destructiveInk, R.badgeInk] {
            for (surface, ground) in Self.grounds {
                #expect(contrastRatio(ink.dark, ground.dark) >= 4.5, "dark \(surface)")
                #expect(contrastRatio(ink.light, ground.light) >= 4.5, "light \(surface)")
            }
        }
        #expect(contrastRatio(R.primaryInk.dark, R.primaryFill.dark) >= 4.5)
        #expect(contrastRatio(R.primaryInk.light, R.primaryFill.light) >= 4.5)
    }

    /// The floating button's glass over a dark desktop and a light one, as `Docs/app-dock.md` measures against.
    static let dockGlass = composite(R.dockGlass, over: BrandTone(dark: 0x26_2626, light: 0xEE_EEEE))

    @Test("the floating button's ink clears 4.5:1 on its glass, and the meter 3:1, in both appearances")
    func dockGlassIsLegible() {
        let glass = Self.dockGlass
        #expect(contrastRatio(R.textStrong.dark, glass.dark) >= 4.5)
        #expect(contrastRatio(R.textStrong.light, glass.light) >= 4.5)
        #expect(contrastRatio(R.dockMeter.dark, glass.dark) >= 3)
        #expect(contrastRatio(R.dockMeter.light, glass.light) >= 3)
    }

    @Test("the floating button's glass is dark when dark and light when light")
    func dockGlassFollowsTheAppearance() {
        #expect(relativeLuminance(Self.dockGlass.dark) < 0.05)
        #expect(relativeLuminance(Self.dockGlass.light) > 0.8)
    }

    @Test("the avatar's initials clear 4.5:1 on both ends of its disc")
    func avatarInkClearsAA() {
        #expect(contrastRatio(R.avatarInk, BrandPalette.Purple.light) >= 4.5)
        #expect(contrastRatio(R.avatarInk, BrandPalette.Teal.primary) >= 4.5)
    }

    /// The clipboard panel's glass over a dark desktop and a light one, as the floating button's is measured.
    static let panelGlass = composite(R.Panel.glass, over: BrandTone(dark: 0x26_2626, light: 0xEE_EEEE))

    /// Every ground the panel sets words on: the glass, the search field's film and a popover.
    static let panelGrounds: [(String, BrandTone)] = [
        ("glass", panelGlass),
        ("film", composite(R.Panel.film, over: panelGlass)),
        ("popover", composite(R.Panel.popover, over: panelGlass)),
    ]

    @Test("the panel's text tones clear 4.5:1 on its glass, its film and a popover, in both appearances")
    func panelTextClearsAA() {
        for (name, text) in [("label", R.Panel.label), ("soft", R.Panel.soft), ("dim", R.Panel.dim)] {
            for (surface, ground) in Self.panelGrounds {
                let dark = contrastRatio(text.dark, ground.dark)
                let light = contrastRatio(text.light, ground.light)
                #expect(dark >= 4.5, "\(name) on dark \(surface) is \(dark)")
                #expect(light >= 4.5, "\(name) on light \(surface) is \(light)")
            }
        }
    }

    @Test("the panel's glyph floor and its inks clear the 3:1 a mark needs on its glass")
    func panelMarksClearNonText() {
        let marks = [
            R.Panel.ghost, R.Panel.accentInk, R.Panel.accent, R.Panel.key, R.Panel.destructive,
            R.infoAccent, R.suggestionAccent,
        ]
        for mark in marks {
            #expect(contrastRatio(mark.dark, Self.panelGlass.dark) >= 3)
            #expect(contrastRatio(mark.light, Self.panelGlass.light) >= 3)
        }
    }

    @Test("the panel's accent reads as text on its glass, where the empty list offers it as a button")
    func panelAccentInkClearsAA() {
        #expect(contrastRatio(R.Panel.accentInk.dark, Self.panelGlass.dark) >= 4.5)
        #expect(contrastRatio(R.Panel.accentInk.light, Self.panelGlass.light) >= 4.5)
    }

    @Test("the chosen segment's ink and a confirm button's ink clear 4.5:1 on their fills")
    func panelFillInksClearAA() {
        let pairs = [(R.Panel.segmentInk, R.Panel.segment), (R.Panel.onAccent, R.Panel.accent)]
        for (ink, fill) in pairs {
            #expect(contrastRatio(ink.dark, fill.dark) >= 4.5)
            #expect(contrastRatio(ink.light, fill.light) >= 4.5)
        }
    }

    @Test("the panel's glass is dark when dark and light when light")
    func panelGlassFollowsTheAppearance() {
        #expect(relativeLuminance(Self.panelGlass.dark) < 0.05)
        #expect(relativeLuminance(Self.panelGlass.light) > 0.8)
    }

    @Test("the neutral chip ink clears the 3:1 a mark needs on the page and a card")
    func neutralAccentClearsMarks() {
        for (surface, ground) in Self.grounds {
            #expect(contrastRatio(R.neutralAccent.dark, ground.dark) >= 3, "dark \(surface)")
            #expect(contrastRatio(R.neutralAccent.light, ground.light) >= 3, "light \(surface)")
        }
    }

    @Test("the badge ink clears 4.5:1 on its own teal wash, in both appearances")
    func badgeInkClearsAA() {
        let wash = Self.composite(
            BrandLayer(tone: R.dictationAccent, darkOpacity: 0.16, lightOpacity: 0.16),
            over: Self.composite(R.cardFill, over: R.windowGround))
        #expect(contrastRatio(R.badgeInk.dark, wash.dark) >= 4.5)
        #expect(contrastRatio(R.badgeInk.light, wash.light) >= 4.5)
    }

    @Test("the sidebar island stays dark in the light appearance")
    func islandStaysDark() {
        #expect(relativeLuminance(R.sidebarIsland.tone.light) < 0.02)
        #expect(contrastRatio(R.textStrong.dark, R.sidebarIsland.tone.light) >= 4.5)
    }
}
