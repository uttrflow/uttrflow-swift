import Testing
import UttrflowClipboard

@Suite("Invisible clipboard characters")
struct ClipTextSafetyTests {
    @Test(
        "hazardous scalars are visible by name and can be removed",
        arguments: [
            ("\u{200B}", "U+200B", "ZERO WIDTH SPACE"),
            ("\u{202E}", "U+202E", "RIGHT-TO-LEFT OVERRIDE"),
            ("\u{2066}", "U+2066", "LEFT-TO-RIGHT ISOLATE"),
            ("\u{E0001}", "U+E0001", "LANGUAGE TAG"),
            ("\u{001B}", "U+001B", "CONTROL CHARACTER"),
            ("\u{0000}", "U+0000", "CONTROL CHARACTER"),
        ])
    func scalarIsEscapedAndCleaned(scalar: String, codePoint: String, name: String) {
        let text = "before\(scalar)after"

        #expect(ClipTextSafety.containsDisplayHazards(text))
        #expect(ClipTextSafety.escaped(text) == "before⟦\(codePoint) \(name)⟧after")
        #expect(ClipTextSafety.removingDisplayHazards(from: text) == "beforeafter")
    }

    @Test("ordinary line breaks and tabs keep their layout")
    func keepsTextLayout() {
        let text = "first line\tcolumn\r\nsecond line"

        #expect(!ClipTextSafety.containsDisplayHazards(text))
        #expect(ClipTextSafety.escaped(text) == text)
        #expect(ClipTextSafety.removingDisplayHazards(from: text) == text)
    }
}
