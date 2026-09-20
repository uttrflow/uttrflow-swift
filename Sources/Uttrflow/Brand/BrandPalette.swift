// Every colour the app draws, by role; the only file in `Sources/` that holds a hex value.

/// One colour as a dark and a light sRGB hex; a fixed colour carries the same value in both.
struct BrandTone: Sendable, Equatable {
    let dark: UInt32
    let light: UInt32

    init(dark: UInt32, light: UInt32) {
        self.dark = dark
        self.light = light
    }

    /// A colour that does not change with the appearance.
    init(_ fixed: UInt32) {
        self.init(dark: fixed, light: fixed)
    }
}

/// The single source of truth for colour. See `Docs/app-main-window.md`.
enum BrandPalette {
    /// The brand teal and the ramp derived from it.
    enum Teal {
        /// The live accent: what is selected, what is running, the focused field.
        static let primary: UInt32 = 0x29_C0B4
        /// The accent as a foreground on the dark surfaces.
        static let bright: UInt32 = 0x5F_E0D3
        /// Controls and graphics with no text on them.
        static let light: UInt32 = 0x39_D0C4
        /// The lit end of a brand-filled badge.
        static let glow: UInt32 = 0x33_D6C7
        /// Fills that carry white text.
        static let deep: UInt32 = 0x12_8077
        /// The lit top of a filled control.
        static let deepLit: UInt32 = 0x17_968C
        /// Deepened until white sits legibly on it, for the monogram.
        static let deeper: UInt32 = 0x0A_5F73
        static let tint: UInt32 = 0x9E_DCD7
        static let wash: UInt32 = 0xEF_F8F7
        /// Ink on a teal fill.
        static let inkOnFill: UInt32 = 0x04_332F
        /// Ink for the mark inside the dock's teal disc.
        static let inkOnDisc: UInt32 = 0x04_100F
        /// The accent as a mark on a surface that follows the appearance.
        static let ink = BrandTone(dark: bright, light: 0x0E_6B64)
        /// The waveform, deepened on a light desktop.
        static let waveform = BrandTone(dark: 0x00_C3D0, light: 0x06_7A87)
        /// The callout ground behind secondary ink.
        static let calloutWash = BrandTone(dark: 0x10_1E1D, light: wash)
        /// The onboarding and settings rail, top to bottom.
        static let railTop: UInt32 = 0x0E_4F49
        static let railMiddle: UInt32 = 0x09_3B37
        static let railBottom: UInt32 = 0x06_2725
        /// The tick cut out of the rail's ground.
        static let railTick: UInt32 = 0x06_3A35
    }

    /// The brand purple: the secondary gradient and its light tone.
    enum Purple {
        static let secondary: UInt32 = 0x61_399F
        static let secondaryMiddle: UInt32 = 0x3E_368A
        static let secondaryEnd: UInt32 = 0x2A_5B72
        /// Code in the quick panel.
        static let light: UInt32 = 0xC4_9BF5
    }

    /// The window greys, darkest ground to most lifted.
    enum Surface {
        /// The page behind everything.
        static let ground = BrandTone(dark: 0x0B_0C10, light: 0xF3_F2F7)
        /// A panel or card on the page.
        static let card = BrandTone(dark: 0x0E_1016, light: 0xFF_FFFF)
        /// A card lifted one step.
        static let raised: UInt32 = 0x12_151C
        /// The microphone's well on the stage.
        static let well: UInt32 = 0x12_141C
        /// A control on a card.
        static let control = BrandTone(dark: raised, light: 0xF1_F0F5)
        /// A control on the onboarding page.
        static let onboardingControl = BrandTone(dark: raised, light: 0xFF_FFFF)
        /// The rail beside the page, a step darker than it.
        static let rail = BrandTone(dark: 0x08_090C, light: 0xEA_E9F0)
        /// The base of a hover or selection wash, applied with an alpha.
        static let wash = BrandTone(dark: 0xFF_FFFF, light: 0x00_0000)
    }

    /// Hairlines.
    enum Line {
        static let separator = BrandTone(dark: 0x1E_212A, light: 0xE2_E0EA)
    }

    /// The text tones, strongest first.
    enum Text {
        static let primary = BrandTone(dark: 0xF4_F4F6, light: 0x17_1320)
        static let muted = BrandTone(dark: 0x8B_90A0, light: 0x6F_6880)
        static let dim = BrandTone(dark: 0x56_5B68, light: 0xA4_9DB3)
        /// Below the dimmest tone, for glyphs that lift when looked at.
        static let ghost: UInt32 = 0x3A_3F4A
    }

    /// Colours that mean something.
    enum Semantic {
        static let link: UInt32 = 0x6B_B4F5
        /// Keys, and a warning that is not a failure.
        static let key: UInt32 = 0xF0_BE63
        static let recording: UInt32 = 0xFF_383C
        static let success: UInt32 = 0x34_C759
        static let warning: UInt32 = 0xFF_8D28
        /// Ink on a page reporting a failure.
        static let cautionInk = BrandTone(dark: 0xFF_B05C, light: 0x9A_4E00)
        /// A warning as text, clearing 4.5:1 on a card, the ground and its own 16% wash.
        static let warningInk = BrandTone(dark: cautionInk.dark, light: 0x8F_4800)
        /// Success as text, clearing 4.5:1 on a card, the ground and its own 16% wash,
        /// which is also the dock's tick and so clears 3:1 against the glass.
        static let successInk = BrandTone(dark: 0x5C_D97E, light: 0x17_6A2F)
        /// A failure as text, clearing 4.5:1 on a card, the ground and its own 16% wash.
        static let criticalInk = BrandTone(dark: 0xFF_6B6E, light: 0xB0_161A)
        /// The dock's failure disc, deep enough that its white glyph clears 3:1. See `Docs/app-dock.md`.
        static let warningFill: UInt32 = 0xC2_5E00
    }
}
