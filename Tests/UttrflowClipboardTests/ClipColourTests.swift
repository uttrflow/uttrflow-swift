// Tests for reading a colour clip's value.

import Testing

@testable import UttrflowClipboard

@Suite("Which colour a colour clip is")
struct ClipColourTests {
    /// A tenth of a byte: HSL goes through a division by thirty, so it misses hex by a few ulps.
    private static let tolerance = 1.0 / 2550

    private func expect(
        _ text: String, is expected: ClipColour,
        sourceLocation: SourceLocation = #_sourceLocation
    ) {
        guard let actual = ClipKindDetector.colour(in: text) else {
            Issue.record("\(text) was read as no colour at all", sourceLocation: sourceLocation)
            return
        }
        let differences = [
            actual.red - expected.red, actual.green - expected.green,
            actual.blue - expected.blue, actual.alpha - expected.alpha,
        ]
        #expect(
            differences.allSatisfy { abs($0) <= Self.tolerance },
            "\(text) read as \(actual), expected \(expected)",
            sourceLocation: sourceLocation)
    }

    // MARK: - Hex

    /// The shorthand doubles its digits rather than padding them: `#f0a` is `#ff00aa`.
    @Test("reads hex")
    func hex() {
        expect("#fff", is: ClipColour(red: 1, green: 1, blue: 1, alpha: 1))
        expect("#000", is: ClipColour(red: 0, green: 0, blue: 0, alpha: 1))
        expect("#f0a", is: ClipColour(red: 1, green: 0, blue: 170 / 255, alpha: 1))
        expect("#ff00aa", is: ClipColour(red: 1, green: 0, blue: 170 / 255, alpha: 1))
        expect("#FF00AA", is: ClipColour(red: 1, green: 0, blue: 170 / 255, alpha: 1))
        expect("#808080", is: ClipColour(red: 128 / 255, green: 128 / 255, blue: 128 / 255, alpha: 1))
    }

    /// Eight digits is how a tool writes a partly see-through colour, and the alpha is the visible mistake.
    @Test("reads the alpha out of four- and eight-digit hex")
    func hexAlpha() {
        expect("#ffffffff", is: ClipColour(red: 1, green: 1, blue: 1, alpha: 1))
        expect("#00000000", is: ClipColour(red: 0, green: 0, blue: 0, alpha: 0))
        expect("#f0a8", is: ClipColour(red: 1, green: 0, blue: 170 / 255, alpha: 136 / 255))
        expect("#ff00aacc", is: ClipColour(red: 1, green: 0, blue: 170 / 255, alpha: 204 / 255))
    }

    // MARK: - rgb() and hsl()

    @Test("reads rgb and rgba")
    func rgb() {
        expect("rgb(0, 128, 255)", is: ClipColour(red: 0, green: 128 / 255, blue: 1, alpha: 1))
        expect("RGB(0,128,255)", is: ClipColour(red: 0, green: 128 / 255, blue: 1, alpha: 1))
        expect(
            "rgb(   0 ,128,   255 )",
            is: ClipColour(red: 0, green: 128 / 255, blue: 1, alpha: 1))
        expect("rgba(0, 128, 255, 0.5)", is: ClipColour(red: 0, green: 128 / 255, blue: 1, alpha: 0.5))
        expect("rgba(0,128,255,.5)", is: ClipColour(red: 0, green: 128 / 255, blue: 1, alpha: 0.5))
        expect("rgba(0, 128, 255, 50%)", is: ClipColour(red: 0, green: 128 / 255, blue: 1, alpha: 0.5))
        expect("rgb(0% 100% 100%)", is: ClipColour(red: 0, green: 1, blue: 1, alpha: 1))
    }

    /// The two spellings are the same colour; tools have moved to the second, the clipboard carries both.
    @Test("reads the modern slash-separated spelling the same as the legacy one")
    func modernSyntax() {
        expect("rgb(0 128 255 / 0.5)", is: ClipColour(red: 0, green: 128 / 255, blue: 1, alpha: 0.5))
        expect("rgb(0 128 255 / 50%)", is: ClipColour(red: 0, green: 128 / 255, blue: 1, alpha: 0.5))
        expect("hsl(120 100% 50% / 0.25)", is: ClipColour(red: 0, green: 1, blue: 0, alpha: 0.25))
    }

    /// `rgba()` with three components and `rgb()` with four are both legal CSS.
    @Test("does not hold the function to its own name")
    func interchangeableNames() {
        expect("rgba(0, 128, 255)", is: ClipColour(red: 0, green: 128 / 255, blue: 1, alpha: 1))
        expect("rgb(0, 128, 255, 0.5)", is: ClipColour(red: 0, green: 128 / 255, blue: 1, alpha: 0.5))
        expect("hsla(120, 100%, 50%)", is: ClipColour(red: 0, green: 1, blue: 0, alpha: 1))
    }

    @Test("reads hsl and hsla")
    func hsl() {
        expect("hsl(0, 100%, 50%)", is: ClipColour(red: 1, green: 0, blue: 0, alpha: 1))
        expect("hsl(120, 100%, 50%)", is: ClipColour(red: 0, green: 1, blue: 0, alpha: 1))
        expect("hsl(240, 100%, 50%)", is: ClipColour(red: 0, green: 0, blue: 1, alpha: 1))
        expect("hsl(0, 0%, 100%)", is: ClipColour(red: 1, green: 1, blue: 1, alpha: 1))
        expect("hsl(0, 0%, 0%)", is: ClipColour(red: 0, green: 0, blue: 0, alpha: 1))
        expect("hsl(0, 0%, 50%)", is: ClipColour(red: 0.5, green: 0.5, blue: 0.5, alpha: 1))
        expect("hsla(120deg, 100%, 50%, 0.25)", is: ClipColour(red: 0, green: 1, blue: 0, alpha: 0.25))
        expect("HSL(120DEG, 100%, 50%)", is: ClipColour(red: 0, green: 1, blue: 0, alpha: 1))
        // Enough tools drop the percent signs that a bare number reads as a percentage.
        expect("hsl(120, 100, 50)", is: ClipColour(red: 0, green: 1, blue: 0, alpha: 1))
    }

    /// The same hue by three names; a tool that subtracts from a hue produces the negative form.
    @Test("wraps the hue into one turn")
    func hueWrapping() {
        let magenta = ClipColour(red: 1, green: 0, blue: 170 / 255, alpha: 1)
        expect("hsl(320, 100%, 50%)", is: magenta)
        expect("hsl(-40, 100%, 50%)", is: magenta)
        expect("hsl(680, 100%, 50%)", is: magenta)
        expect("hsl(-400, 100%, 50%)", is: magenta)
        expect("hsl(360, 100%, 50%)", is: ClipColour(red: 1, green: 0, blue: 0, alpha: 1))
    }

    // MARK: - Out of range

    /// `rgb(300, 0, 0)` is a colour and it is red, as a browser reads it.
    @Test("clamps rather than rejects")
    func clamping() {
        expect("rgb(300, 0, 0)", is: ClipColour(red: 1, green: 0, blue: 0, alpha: 1))
        expect("rgb(-20, 0, 0)", is: ClipColour(red: 0, green: 0, blue: 0, alpha: 1))
        expect("rgb(0, 0, 0, 4)", is: ClipColour(red: 0, green: 0, blue: 0, alpha: 1))
        expect("rgb(0, 0, 0, -1)", is: ClipColour(red: 0, green: 0, blue: 0, alpha: 0))
        expect("hsl(0, 400%, 50%)", is: ClipColour(red: 1, green: 0, blue: 0, alpha: 1))
        #expect(ClipKindDetector.kind(of: "rgb(300, 0, 0)") == .colour)
    }

    /// Not-a-number would clamp to a confident, arbitrary colour, so it is refused.
    @Test(
        "refuses a component that is not a finite number",
        arguments: ["rgb(nan, 0, 0)", "rgb(inf, 0, 0)", "hsl(inf, 100%, 50%)", "rgba(0,0,0,nan)"])
    func nonFinite(_ text: String) {
        #expect(ClipKindDetector.colour(in: text) == nil)
    }

    // MARK: - Whitespace

    /// A trailing newline is a copying accident, never a different colour.
    @Test("ignores whitespace around the edges")
    func trimming() {
        expect("  #ff00aa \n", is: ClipColour(red: 1, green: 0, blue: 170 / 255, alpha: 1))
        expect("\n\trgba(0, 128, 255, 0.5)\n", is: ClipColour(red: 0, green: 128 / 255, blue: 1, alpha: 0.5))
        expect("\nhsl(120, 100%, 50%)  ", is: ClipColour(red: 0, green: 1, blue: 0, alpha: 1))
    }

    // MARK: - Nothing to draw

    /// Bare hex has no hash and no colour; a swatch beside `facade` would be noticed at once.
    @Test(
        "reads no colour out of a word that happens to be hex",
        arguments: ["fff", "ffffff", "dad", "bed", "ace", "add", "fee", "decade", "facade", "deeded"])
    func bareHex(_ text: String) {
        #expect(ClipKindDetector.colour(in: text) == nil)
        #expect(ClipKindDetector.kind(of: text) != .colour)
    }

    /// Everything the brief called out, plus the digit counts that are not a notation.
    @Test(
        "reads no colour out of these",
        arguments: [
            "",
            "   \n ",
            "#",
            "#f",
            "#ff",
            "#fffff",
            "#fffffff",
            "#ffff00aaa",
            "#zzz",
            "#hashtag",
            "#include <stdio.h>",
            "color: #fff;",
            "The brand colour is #fff and the accent is #000.",
            "#ff0000 #00ff00",
            "rgb(0, 128)",
            "rgb(0, 128, 255, 0.5, 1)",
            "rgb(a, b, c)",
            "hsl(a, b, c)",
            "rgb()",
            "translate(10, 20)",
            "background: rgb(0, 128, 255);",
        ])
    func unreadable(_ text: String) {
        #expect(ClipKindDetector.colour(in: text) == nil)
    }

    /// The perceptual notations are colours with no swatch, because a wrong red is worse than none.
    @Test(
        "has no value for the notations it does not convert",
        arguments: [
            "oklch(0.7 0.2 20)", "oklab(0.7 0.1 -0.1)", "lch(50% 40 30)", "lab(50% 40 30)",
            "hwb(120 0% 0%)", "color(display-p3 1 0 0.6)",
        ])
    func perceptual(_ text: String) {
        #expect(ClipKindDetector.kind(of: text) == .colour)
        #expect(ClipKindDetector.colour(in: text) == nil)
    }

    // MARK: - The two questions agree

    /// The reader may be narrower than the detector, but never wider.
    @Test(
        "reads a colour only out of clips the panel calls colours",
        arguments: [
            "#fff", "#f0a8", "#ff00aa", "#ff00aacc", "rgb(0, 128, 255)",
            "rgba(0, 128, 255, 0.5)", "rgb(0 128 255 / 50%)", "rgb(300, 0, 0)",
            "hsl(320, 100%, 50%)", "hsla(120deg, 100%, 50%, 0.25)", "  #ff00aa \n",
        ])
    func agreement(_ text: String) {
        #expect(ClipKindDetector.colour(in: text) != nil)
        #expect(ClipKindDetector.kind(of: text) == .colour)
    }

    /// Two colours are the same when their four numbers are, which decides whether a swatch redraws.
    @Test("compares by value")
    func equality() {
        #expect(ClipKindDetector.colour(in: "#ff00aa") == ClipKindDetector.colour(in: "#f0a"))
        #expect(ClipKindDetector.colour(in: "#ff00aa") != ClipKindDetector.colour(in: "#ff00aacc"))
    }
}
