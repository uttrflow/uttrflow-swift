import Testing

@testable import UttrflowCore

@Suite("OutputSafety")
struct OutputSafetyTests {
    @Test("keeps tab and line feed inside the text")
    func keepsTabAndLineFeed() {
        let checked = OutputSafety.checked("one\ttwo\nthree")
        #expect(checked == OutputSafety.Checked(text: "one\ttwo\nthree", violations: 0))
    }

    @Test("turns every other control character into a space")
    func replacesControlCharacters() {
        #expect(OutputSafety.checked("a\u{0}b\rc\u{7F}d\u{85}e").text == "a b c d e")
        #expect(OutputSafety.checked("a\u{0}b\rc\u{7F}d\u{85}e").violations == 4)
    }

    @Test("never ends with a line break")
    func dropsTrailingBreaks() {
        #expect(OutputSafety.checked("ls -la\n").text == "ls -la")
        #expect(OutputSafety.checked("ls -la\n\n").violations == 2)
    }

    @Test("removes escape sequences whole")
    func removesEscapeSequences() {
        #expect(OutputSafety.checked("red \u{1B}[31mtext\u{1B}[0m").text == "red text")
        #expect(OutputSafety.checked("a\u{1B}cb").text == "ab")
        #expect(OutputSafety.checked("a\u{1B}").text == "a")
    }

    @Test("every control character in the C0 and C1 ranges is caught")
    func coversEveryControlCharacter() {
        for value in Array(0x00...0x1F) + Array(0x7F...0x9F) {
            guard let scalar = Unicode.Scalar(value) else { continue }
            let text = OutputSafety.checked("a" + String(Character(scalar)) + "b").text
            #expect(
                !text.unicodeScalars.contains { $0.value < 0x20 && $0 != "\t" && $0 != "\n" },
                "U+\(String(value, radix: 16)) survived")
            #expect(!text.unicodeScalars.contains { (0x7F...0x9F).contains($0.value) })
        }
    }

    @Test(
        "where Return acts, every break inside the text becomes one space",
        arguments: Consequence.allCases.filter(\.returnActs))
    func breaksBecomeSpaceWhereReturnActs(_ consequence: Consequence) {
        let checked = OutputSafety.checked("see you\n\nbring snacks\n", consequence: consequence)
        #expect(checked == OutputSafety.Checked(text: "see you bring snacks", violations: 3))
        #expect(OutputSafety.checked("one \n two", consequence: consequence).text == "one two")
        #expect(OutputSafety.checked("\nls", consequence: consequence).text == "ls")
        #expect(OutputSafety.checked("a  b\tc", consequence: consequence).text == "a  b\tc")
    }

    @Test("where the text is stored, a break inside it stays")
    func storedTextKeepsBreaks() {
        #expect(OutputSafety.checked("see you\n\nbring snacks", consequence: .stores).text == "see you\n\nbring snacks")
    }
}
