import AppKit
import SwiftUI
import Testing

@testable import Uttrflow

/// Colours are drawn, so most of what they do cannot be tested here. Two things can, and
/// both are the kind of mistake that ships: a hex unpacked into the wrong channel, and a
/// dynamic colour that answers with the wrong appearance's value. Either one is invisible
/// in the code and obvious on screen, which is the wrong way round.
@MainActor
@Suite("The window's palette")
struct OrbitPaletteTests {
    private func components(_ colour: NSColor, in appearance: NSAppearance.Name) -> [CGFloat] {
        var resolved: [CGFloat] = []
        NSAppearance(named: appearance)?.performAsCurrentDrawingAppearance {
            let srgb = colour.usingColorSpace(.sRGB) ?? colour
            resolved = [
                srgb.redComponent, srgb.greenComponent, srgb.blueComponent,
                srgb.alphaComponent,
            ]
        }
        return resolved.map { ($0 * 255).rounded() / 255 }
    }

    @Test("unpacks a hex into red, green and blue in that order")
    func hexChannels() {
        let colour = NSColor(rgb: 0x0B_0C10).usingColorSpace(.sRGB)

        let red: CGFloat = 0x0B / 255
        let green: CGFloat = 0x0C / 255
        let blue: CGFloat = 0x10 / 255

        #expect(colour?.redComponent == red)
        #expect(colour?.greenComponent == green)
        #expect(colour?.blueComponent == blue)
        #expect(colour?.alphaComponent == 1)
    }

    @Test("answers with the dark value in the dark and the light one in the light")
    func resolvesPerAppearance() {
        let colour = NSColor.orbit(dark: 0x0B_0C10, light: 0xF3_F2F7)

        let dark: [CGFloat] = [0x0B / 255, 0x0C / 255, 0x10 / 255, 1]
        let light: [CGFloat] = [0xF3 / 255, 0xF2 / 255, 0xF7 / 255, 1]

        #expect(components(colour, in: .darkAqua) == dark)
        #expect(components(colour, in: .aqua) == light)
    }

    @Test("carries the alpha through on a wash")
    func washKeepsItsAlpha() {
        let wash = NSColor.orbitAlpha(dark: 0xFF_FFFF, light: 0x00_0000, alpha: 0.05)
        let dark = components(wash, in: .darkAqua)
        let light = components(wash, in: .aqua)

        #expect(dark[0] == 1)
        #expect(light[0] == 0)
        // Rounded rather than exact: an eight-bit channel cannot hold 0.05 precisely.
        #expect(abs(dark[3] - 0.05) < 0.01)
        #expect(abs(light[3] - 0.05) < 0.01)
    }

    /// `name == .darkAqua` would answer this wrongly: somebody running the high-contrast
    /// dark appearance would get the light palette on a dark desktop.
    @Test("counts the accessibility dark appearances as dark")
    func accessibilityDarkIsDark() {
        #expect(NSAppearance(named: .darkAqua)?.isDark == true)
        #expect(NSAppearance(named: .accessibilityHighContrastDarkAqua)?.isDark == true)
        #expect(NSAppearance(named: .aqua)?.isDark == false)
        #expect(NSAppearance(named: .accessibilityHighContrastAqua)?.isDark == false)
    }

    /// The rail sinks into the window and the card lifts off it. Stated as a test because
    /// the three greys are within a few points of each other, and a pair swapped in the
    /// table would look like a rendering bug rather than a typo.
    @Test("the rail is darker than the page, and a card lighter")
    func surfacesStack() {
        func luminance(_ colour: Color) -> CGFloat {
            let resolved = NSColor(colour).usingColorSpace(.sRGB) ?? .black
            return resolved.redComponent + resolved.greenComponent + resolved.blueComponent
        }
        NSAppearance(named: .darkAqua)?.performAsCurrentDrawingAppearance {
            #expect(luminance(.railGround) < luminance(.mainBackground))
            #expect(luminance(.mainCard) > luminance(.mainBackground))
            #expect(luminance(.mainSeparator) > luminance(.mainCard))
            #expect(luminance(.mainText) > luminance(.mainMuted))
            #expect(luminance(.mainMuted) > luminance(.mainDim))
        }
    }
}
