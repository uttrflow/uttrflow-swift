// Every colour the app draws, by role; the only file in `Sources/` that holds a hex value.

/// One colour as a dark and a light sRGB hex; a fixed colour carries the same value in both.
struct BrandTone: Sendable, Equatable {
    let dark: UInt32
    let light: UInt32
    let highContrastDark: UInt32?
    let highContrastLight: UInt32?

    init(dark: UInt32, light: UInt32, highContrastDark: UInt32? = nil, highContrastLight: UInt32? = nil) {
        self.dark = dark
        self.light = light
        self.highContrastDark = highContrastDark
        self.highContrastLight = highContrastLight
    }

    /// A colour that does not change with the appearance.
    init(_ fixed: UInt32) {
        self.init(dark: fixed, light: fixed)
    }
}

/// A tone drawn at an opacity that can differ between the appearances.
struct BrandLayer: Sendable, Equatable {
    let tone: BrandTone
    let darkOpacity: Double
    let lightOpacity: Double
    let highContrastDarkOpacity: Double?
    let highContrastLightOpacity: Double?

    init(
        tone: BrandTone, darkOpacity: Double, lightOpacity: Double,
        highContrastDarkOpacity: Double? = nil, highContrastLightOpacity: Double? = nil
    ) {
        self.tone = tone
        self.darkOpacity = darkOpacity
        self.lightOpacity = lightOpacity
        self.highContrastDarkOpacity = highContrastDarkOpacity
        self.highContrastLightOpacity = highContrastLightOpacity
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
        /// The accent as a mark on a surface that follows the appearance.
        static let ink = BrandTone(dark: bright, light: 0x0E_6B64)
        /// The callout ground behind secondary ink.
        static let calloutWash = BrandTone(dark: 0x10_1E1D, light: wash)
        /// The onboarding and settings rail, top to bottom.
        static let railTop: UInt32 = 0x0E_4F49
        static let railMiddle: UInt32 = 0x09_3B37
        static let railBottom: UInt32 = 0x06_2725
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
        /// The rail beside the page, a step darker than it.
        static let rail = BrandTone(dark: 0x08_090C, light: 0xEA_E9F0)
        /// The base of a hover or selection wash, applied with an alpha.
        static let wash = BrandTone(
            dark: 0xFF_FFFF, light: 0x00_0000, highContrastDark: 0xFF_FFFF, highContrastLight: 0x00_0000)
    }

    /// Hairlines.
    enum Line {
        static let separator = BrandTone(
            dark: 0x1E_212A, light: 0xE2_E0EA, highContrastDark: 0x76_7C8C, highContrastLight: 0x76_6B8D)
    }

    /// The text tones, strongest first.
    enum Text {
        static let primary = BrandTone(dark: 0xF4_F4F6, light: 0x17_1320)
        static let muted = BrandTone(
            dark: 0x8B_90A0, light: 0x64_5B76, highContrastDark: 0xC1_C4CE, highContrastLight: 0x4D_445F)
        /// The dimmest tone words may use; 4.5:1 on the rail leaves it close to `muted` in the light.
        static let dim = BrandTone(
            dark: 0x7A_7F8E, light: 0x6D_6481, highContrastDark: 0xB0_B4C0, highContrastLight: 0x54_4A69)
        /// Below the dimmest text tone, for glyphs that lift when looked at; a mark's floor is 3:1.
        static let ghost: UInt32 = 0x65_6E80
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
        static let cautionInk = BrandTone(dark: 0xFF_B05C, light: 0x94_3C00)
        /// A warning as text, clearing 4.5:1 on a card, the ground and its own 16% wash.
        static let warningInk = BrandTone(dark: cautionInk.dark, light: 0x8F_4800)
        /// Success as text and the dock's tick: 4.5:1 on a card, the ground and its 16% wash, 3:1 on glass.
        static let successInk = BrandTone(dark: 0x5C_D97E, light: 0x17_6A2F)
        /// A failure as text, clearing 4.5:1 on a card, the ground and its own 16% wash.
        static let criticalInk = BrandTone(dark: 0xFF_6B6E, light: 0xB0_161A)
        /// The dock's failure disc, deep enough that its white glyph clears 3:1. See `Docs/app-dock.md`.
        static let warningFill: UInt32 = 0xC2_5E00
    }

    /// The redesign's tokens, drawn by the screens already moved to it. See `Docs/redesign-tokens.md`.
    enum Redesign {
        /// The page behind everything.
        static let pageGround = BrandTone(dark: 0x0B_0C10, light: 0xF2_F1EC)
        /// The window body the page sits in.
        static let windowGround = BrandTone(dark: 0x0C_0D14, light: 0xF2_F1EC)
        /// A card: a faint white film when dark, solid white when light.
        static let cardFill = BrandLayer(tone: BrandTone(0xFF_FFFF), darkOpacity: 0.035, lightOpacity: 1)
        /// The hairline around a card.
        static let hairline = BrandLayer(
            tone: BrandTone(dark: 0xFF_FFFF, light: 0xDE_DCD4), darkOpacity: 0.08, lightOpacity: 1)
        /// The sidebar island, which stays dark in the light appearance.
        static let sidebarIsland = BrandLayer(
            tone: BrandTone(dark: 0x10_0F1C, light: 0x12_101E), darkOpacity: 0.92, lightOpacity: 1)
        /// The island's headings and quiet words, white at the opacity that clears 4.5:1 on it.
        static let islandQuiet = BrandLayer(tone: BrandTone(0xFF_FFFF), darkOpacity: 0.55, lightOpacity: 0.55)
        /// Headline and body text.
        static let textStrong = BrandTone(dark: 0xFF_FFFF, light: 0x10_1316)
        /// Secondary text.
        static let textSoft = BrandLayer(
            tone: BrandTone(dark: 0xFF_FFFF, light: 0x5C_6866), darkOpacity: 0.72, lightOpacity: 1)
        /// The quietest text.
        static let textQuiet = BrandLayer(
            tone: BrandTone(dark: 0xFF_FFFF, light: 0x5C_6866), darkOpacity: 0.55, lightOpacity: 1)
        /// Captions, headings and hints in the page's ink, clearing 4.5:1 on the page, a card and their films.
        static let textFaint = BrandLayer(tone: textStrong, darkOpacity: 0.55, lightOpacity: 0.66)
        /// Dictation's accent.
        static let dictationAccent = BrandTone(dark: 0x5F_E0D3, light: 0x12_8077)
        /// The accent for AI suggestions.
        static let suggestionAccent = BrandTone(dark: 0xC4_9BF5, light: 0x7A_4FC4)
        /// The clipboard's accent.
        static let clipboardAccent = BrandTone(dark: 0xFF_B05C, light: 0xB5_650F)
        /// The clipboard's amber as words, deepened in the light to clear 4.5:1 on the page and a card.
        static let clipboardInk = BrandTone(dark: clipboardAccent.dark, light: Semantic.warningInk.light)
        /// The accent for information.
        static let infoAccent = BrandTone(dark: 0x6B_B4F5, light: 0x1E_6FC4)
        /// The aurora gradient's stops, first to last, in both appearances.
        static let auroraStops: [UInt32] = [0x7A_3FD1, 0x4B_3FC0, 0x1F_8FB0, 0x2F_E0CF]
        /// The floating button's glass over the system material: violet-black when dark, frosted white when light.
        static let dockGlass = BrandLayer(
            tone: BrandTone(dark: 0x10_0D1E, light: 0xFF_FFFF), darkOpacity: 0.72, lightOpacity: 0.9)
        /// The hairline round the floating button's glass.
        static let dockGlassEdge = BrandLayer(
            tone: BrandTone(dark: 0xFF_FFFF, light: 0x10_1316), darkOpacity: 0.14, lightOpacity: 0.1)
        /// The floating button's shadow, lighter on a light desktop.
        static let dockShadow = BrandLayer(
            tone: BrandTone(dark: 0x00_0000, light: 0x10_1316), darkOpacity: 0.5, lightOpacity: 0.22)
        /// The listening meter: white on the dark glass, dictation teal on the light.
        static let dockMeter = BrandTone(dark: textStrong.dark, light: dictationAccent.light)
        /// The initials on the avatar's lilac-to-teal disc.
        static let avatarInk: UInt32 = 0x08_131A
        /// A lettered app tile's saturation and brightness; its hue comes from the app's name.
        static let appTileTone = (saturation: 0.55, brightness: 0.62)
        /// The avatar disc's lilac end on a page, deepened in the light.
        static let avatarLilac = BrandTone(dark: Purple.light, light: suggestionAccent.light)
        /// The avatar disc's teal end on a page, deepened in the light.
        static let avatarTeal = BrandTone(dark: Teal.primary, light: Teal.deep)
        /// The faint ring round a large avatar.
        static let avatarRing = BrandLayer(tone: textStrong, darkOpacity: 0.08, lightOpacity: 0.072)
        /// The profile banner's ground under its aurora, dark in both appearances.
        static let bannerGround = BrandTone(0x10_101A)
        /// The name on the profile banner, white in both appearances because the banner stays dark.
        static let bannerInk = BrandTone(0xFF_FFFF)
        /// The address under the name on the profile banner.
        static let bannerSoft = BrandLayer(tone: bannerInk, darkOpacity: 0.75, lightOpacity: 0.75)
        /// A glass panel's white film, which all but vanishes on the light page.
        static let glassFill = BrandLayer(tone: BrandTone(0xFF_FFFF), darkOpacity: 0.05, lightOpacity: 0.05)
        /// The white hairline round a glass panel, which all but vanishes on the light page.
        static let glassEdge = BrandLayer(tone: BrandTone(0xFF_FFFF), darkOpacity: 0.09, lightOpacity: 0.09)
        /// The rule between the rows of a glass panel.
        static let glassRule = BrandLayer(tone: textStrong, darkOpacity: 0.07, lightOpacity: 0.063)
        /// Sign out's words and glyph.
        static let signOutInk = BrandTone(dark: 0xFF_8A8C, light: Semantic.criticalInk.light)
        /// Sign out's red wash.
        static let signOutWash = BrandLayer(
            tone: BrandTone(Semantic.criticalInk.dark), darkOpacity: 0.12, lightOpacity: 0.12)
        /// Sign out's red edge.
        static let signOutEdge = BrandLayer(
            tone: BrandTone(Semantic.criticalInk.dark), darkOpacity: 0.3, lightOpacity: 0.3)
        /// The home hero card's ground, under its two aurora glows.
        static let heroGround = BrandTone(dark: 0x0E_111A, light: 0xFF_FFFF)
        /// The hero's mono waveform: white in the dark, ink in the light.
        static let waveformInk = BrandLayer(tone: textStrong, darkOpacity: 0.88, lightOpacity: 0.79)
        /// A quiet control's fill: a View button, a ⋯ button.
        static let controlFill = BrandLayer(
            tone: BrandTone(
                dark: textStrong.dark, light: textStrong.light,
                highContrastDark: 0xFF_FFFF, highContrastLight: 0xD8_D5E0),
            darkOpacity: 0.06, lightOpacity: 0.04,
            highContrastDarkOpacity: 0.28, highContrastLightOpacity: 0.28)
        /// A quiet control's edge.
        static let controlEdge = BrandLayer(
            tone: BrandTone(
                dark: textStrong.dark, light: textStrong.light,
                highContrastDark: 0x9B_A1B2, highContrastLight: 0x6A_607E),
            darkOpacity: 0.14, lightOpacity: 0.14,
            highContrastDarkOpacity: 1, highContrastLightOpacity: 1)
        /// The unfilled track of a stat tile's ring.
        static let ringTrack = BrandLayer(tone: textStrong, darkOpacity: 0.1, lightOpacity: 0.1)
        /// The faint rim of a home card or row when dark; none when light, where white on the page is enough.
        static let cardEdge = BrandLayer(tone: BrandTone(0xFF_FFFF), darkOpacity: 0.08, lightOpacity: 0)
        /// Words on a button filled with an accent, near-black in both appearances.
        static let onAccentInk = BrandTone(dark: 0x0B_0C10, light: 0x10_1316)
        /// A primary button's fill: white when dark, ink when light.
        static let primaryFill = BrandTone(dark: 0xFF_FFFF, light: 0x10_1316)
        /// The words on a primary button.
        static let primaryInk = BrandTone(dark: 0x0B_0C10, light: 0xFE_FEFE)
        /// The words on a destructive button, over its own red wash.
        static let destructiveInk = BrandTone(dark: 0xFF_8A8C, light: 0xB0_161A)
        /// A secondary button's fill.
        static let quietFill = BrandLayer(tone: textStrong, darkOpacity: 0.08, lightOpacity: 0.072)
        /// A confirmation sheet's glass.
        static let sheetGlass = BrandLayer(
            tone: BrandTone(dark: 0x12_1020, light: 0xFE_FEFC), darkOpacity: 0.96, lightOpacity: 0.93)
        /// A corner notice's glass, a little clearer than a sheet's.
        static let toastGlass = BrandLayer(
            tone: BrandTone(dark: 0x12_1020, light: 0xFE_FEFC), darkOpacity: 0.9, lightOpacity: 0.93)
        /// The veil over a window while a sheet asks its question.
        static let scrim = BrandLayer(
            tone: BrandTone(dark: 0x05_050A, light: 0xF2_F1EC), darkOpacity: 0.55, lightOpacity: 0.55)
        /// The shadow under a sheet or a corner notice.
        static let floatShadow = BrandLayer(
            tone: BrandTone(0x00_0000), darkOpacity: 0.7, lightOpacity: 0.12)

        /// The clipboard panel's glass and inks. See `Docs/app-quick-panel.md`.
        enum Panel {
            /// The panel's glass over the system material: violet-black when dark, paper when light.
            static let glass = BrandLayer(
                tone: BrandTone(dark: 0x09_090F, light: 0xFA_F9F6), darkOpacity: 0.92, lightOpacity: 0.94)
            /// The rim round the glass.
            static let edge = BrandLayer(tone: film.tone, darkOpacity: 0.14, lightOpacity: 0.126)
            /// The search field's and microphone's film on the glass.
            static let film = BrandLayer(
                tone: BrandTone(dark: 0xFF_FFFF, light: 0x10_1316), darkOpacity: 0.045, lightOpacity: 0.0405)
            /// A hovered row, and the segmented control's track.
            static let lift = BrandLayer(tone: film.tone, darkOpacity: 0.06, lightOpacity: 0.054)
            /// The rules between the panel's bands and round its controls.
            static let line = BrandLayer(tone: film.tone, darkOpacity: 0.1, lightOpacity: 0.09)
            /// The ⋯ menu's and a sheet's glass.
            static let popover = BrandLayer(
                tone: BrandTone(dark: 0x16_1424, light: 0xFE_FEFC), darkOpacity: 0.94, lightOpacity: 0.93)
            /// A sheet's text field and diff, sunk below the popover.
            static let well = BrandTone(dark: 0x0B_0C10, light: 0xFF_FFFF)
            /// The chosen segment of the kind filter, and the ink on it.
            static let segment = BrandTone(dark: 0xFF_FFFF, light: 0x10_1316)
            static let segmentInk = BrandTone(dark: 0x0B_0C10, light: 0xFE_FEFE)
            /// The panel's three text tones, strongest first, and a glyph's quieter floor.
            static let label = BrandTone(dark: 0xF4_F4F6, light: 0x10_1316)
            static let soft = BrandTone(dark: 0x8B_90A0, light: 0x5C_6866)
            static let dim = BrandTone(dark: 0x7A_7F8E, light: 0x6D_6481)
            static let ghost = BrandTone(dark: 0x65_6E80, light: 0x8A_8F9C)
            /// The selection ring, the chosen tab and a sheet's confirm fill.
            static let accent = BrandTone(dark: 0x29_C0B4, light: dictationAccent.light)
            /// The accent as a foreground on the glass.
            static let accentInk = dictationAccent
            /// Ink on an accent fill: deep teal when dark, white when light.
            static let onAccent = BrandTone(dark: 0x04_332F, light: 0xFF_FFFF)
            /// An alias chip and a credential's tile.
            static let key = BrandTone(dark: 0xF0_BE63, light: 0x9A_6400)
            /// Delete under the pointer.
            static let destructive = BrandTone(dark: 0xFF_8D28, light: 0x8F_4800)
            /// The aurora rising from the panel's top edge, drawn at this opacity in both appearances.
            static let auroraOpacity = 0.22
        }
        /// The grey a quiet source chip wears, such as a word that shipped with the app.
        static let neutralAccent = BrandTone(dark: 0xA7_ACB8, light: 0x5E_6470)
        /// The pale teal ink of a small "New" badge on its teal wash.
        static let badgeInk = BrandTone(dark: 0xAF_F3EC, light: 0x0E_645D)
        /// The well an editor's text field is sunk into.
        static let fieldWell = BrandLayer(
            tone: BrandTone(dark: 0x00_0000, light: 0x10_1316), darkOpacity: 0.25, lightOpacity: 0.045)

        /// Mint, a second teal for rows beside dictation's own.
        static let mintAccent = BrandTone(dark: 0x8F_F5EC, light: 0x12_8077)
        /// The deep end of a switch's teal gradient.
        static let dictationDeep = BrandTone(dark: 0x29_C0B4, light: 0x12_8077)
        /// The day number on a busy Insights calendar tile, deep teal on the bright teal in both appearances.
        static let calendarDeepInk: UInt32 = 0x04_332F
    }

    /// The onboarding window's tokens; it is drawn dark in every appearance. See `Docs/app-onboarding.md`.
    enum Onboarding {
        /// The window behind the aurora.
        static let windowGround: UInt32 = 0x08_070F
        /// The aurora's stops for each mood, first to last; the gradient closes on its first stop.
        static let brandAurora = Redesign.auroraStops
        static let liveAurora: [UInt32] = [0x14_B3A6, 0x2F_E0CF, 0x1F_8FB0, 0x8F_F5EC]
        static let waitingAurora: [UInt32] = [0x4B_3FC0, 0x8A_4FE0, 0x2A_6FA0]
        static let warningAurora: [UInt32] = [0x61_399F, 0x8A_3E6B, 0xC2_5E00, 0x3E_368A]
        static let failureAurora: [UInt32] = [0x3E_368A, 0x7A_2436, 0xB0_161A, 0x2A_1B3D]
        static let offlineAurora: [UInt32] = [0x2A_2D36, 0x3A_3F4A, 0x1E_2128]
        static let doneAurora: [UInt32] = [0x2F_E0CF, 0x8F_F5EC, 0x1F_8FB0, 0x7A_3FD1]
        /// The card's glass tint over the blurred aurora.
        static let glass: UInt32 = 0x10_0D1E
        /// The pale teal a heading's gradient ends in, and the pointer's ink.
        static let glow: UInt32 = 0xAF_F3EC
        /// The logo's wordmark and mark.
        static let logoInk: UInt32 = 0xF2_F1EC
        /// The logo tile, top to bottom.
        static let tileTop: UInt32 = 0x1D_2024
        static let tileBottom: UInt32 = 0x10_1215
        /// Ink on a white round button.
        static let buttonInk: UInt32 = 0x0B_0C10
        /// The card's text field: its ink, its placeholder and its caret.
        static let fieldInk: UInt32 = 0x10_1316
        static let fieldPlaceholder: UInt32 = 0x9A_A09E
        static let caret = Teal.deep
        /// A badge's dark disc, and the amber-tinted one for something switched off.
        static let badgeGround: UInt32 = 0x14_1224
        static let cautionBadgeGround: UInt32 = 0x28_1405
        /// The failure badge's disc, lit end to deep end, and the stopped ring.
        static let failureLit: UInt32 = 0xFF_8A8C
        static let failureDeep: UInt32 = 0xE0_262B
        /// The failure badge's shadow.
        static let failureShadow: UInt32 = 0xFF_383C
        /// The warm end of the welcome's heading, and a confetti colour.
        static let welcomeGlow: UInt32 = 0xFF_E3A8
        /// An unlit keycap on the first try's keyboard, top to bottom.
        static let keyTop: UInt32 = 0x30_343F
        static let keyBottom: UInt32 = 0x1C_1F27
    }
}

extension BrandPalette.Redesign {
    /// The menu bar popover's tokens, each as the design draws it dark and light.
    enum MenuBar {
        private typealias R = BrandPalette.Redesign

        /// The glass over the system material: violet-black when dark, frosted white when light.
        static let glass = BrandLayer(
            tone: BrandTone(dark: 0x10_0D1E, light: 0xFF_FFFF), darkOpacity: 0.62, lightOpacity: 0.85)
        /// The hairline round the glass.
        static let glassEdge = BrandLayer(tone: R.textStrong, darkOpacity: 0.13, lightOpacity: 0.14)
        /// The drop shadow, violet-tinted on a light desktop.
        static let shadow = BrandLayer(
            tone: BrandTone(dark: 0x00_0000, light: 0x28_1E50), darkOpacity: 0.7, lightOpacity: 0.28)
        /// The tile the mark sits on.
        static let tile = BrandTone(dark: 0x0B_0C10, light: 0xFF_FFFF)
        /// Ink on a filled disc or pill.
        static let fillInk = BrandTone(dark: 0x0B_0C10, light: 0xFE_FEFE)
        /// The talk hint.
        static let hint = BrandLayer(tone: R.textStrong, darkOpacity: 0.7, lightOpacity: 0.63)
        /// A round button's label.
        static let buttonLabel = BrandLayer(
            tone: BrandTone(dark: 0xFF_FFFF, light: 0x5C_6866), darkOpacity: 0.7, lightOpacity: 1)
        /// The line under a status title.
        static let detail = BrandLayer(tone: R.textStrong, darkOpacity: 0.55, lightOpacity: 0.66)
        /// A row's words.
        static let row = BrandLayer(tone: R.textStrong, darkOpacity: 0.85, lightOpacity: 0.765)
        /// A section label and a row's glyph.
        static let quiet = BrandLayer(tone: R.textStrong, darkOpacity: 0.5, lightOpacity: 0.62)
        /// The progress track and the tile's edge.
        static let track = BrandLayer(tone: R.textStrong, darkOpacity: 0.12, lightOpacity: 0.108)
        /// The rule between sections.
        static let rule = BrandLayer(tone: R.textStrong, darkOpacity: 0.1, lightOpacity: 0.09)
        /// A quiet round button's disc.
        static let buttonFill = BrandLayer(tone: R.textStrong, darkOpacity: 0.1, lightOpacity: 0.06)
        /// Talk's disc while it cannot listen: a fixed mid-grey under a white mic when light, faded white when dark.
        static let talkOff = BrandLayer(
            tone: BrandTone(dark: 0xFF_FFFF, light: 0x8B_90A0), darkOpacity: 0.35, lightOpacity: 1)
        /// A round button's edge.
        static let buttonEdge = BrandLayer(tone: R.textStrong, darkOpacity: 0.14, lightOpacity: 0.1)
        /// The keycap behind the shortcut.
        static let keycap = BrandLayer(tone: R.textStrong, darkOpacity: 0.12, lightOpacity: 0.07)
        /// A row under the pointer.
        static let hover = BrandLayer(tone: R.textStrong, darkOpacity: 0.07, lightOpacity: 0.05)
        /// The aurora glow's strength behind the header.
        static let glowOpacity = (dark: 0.55, light: 0.22)
    }
}
