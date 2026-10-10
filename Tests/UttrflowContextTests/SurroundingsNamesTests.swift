import Testing

@testable import UttrflowContext

@Suite("The names a surroundings read lets dictation keep")
struct SurroundingsNamesTests {
    @Test("keeps capitalised names and @mentions, nearest the field first")
    func keepsNames() {
        let names = SurroundingsNames.names(
            inText: "Kavitha: can you join?\nyes\n@dev_rao is out, Ananya will cover")
        #expect(names == ["Ananya", "dev_rao", "Kavitha"])
    }

    @Test("leaves out a word that also appears in lower case, a number, an acronym and an identifier")
    func leavesOutOrdinaryWords() {
        let names = SurroundingsNames.names(
            inText: "Thanks for that. I said thanks. OK, see build2 and URL for Meera")
        #expect(names == ["Meera"])
    }

    @Test("refuses a secret-shaped run")
    func refusesSecrets() {
        let names = SurroundingsNames.names(inText: "Key ASIAY34FZKBOKMUTVV7A for Farhan")
        #expect(!names.contains { $0.contains("ASIA") })
        #expect(names.contains("Farhan"))
    }

    @Test("keeps each name once and at most the cap")
    func capsAndDeduplicates() {
        let many = (0..<80).map {
            "Ta" + String(UnicodeScalar(UInt8(97 + $0 % 26))) + String(repeating: "o", count: $0 / 26 + 1)
                + "ba"
        }
        let names = SurroundingsNames.names(inText: (many + many).joined(separator: " "))
        #expect(names.count == SurroundingsNames.maximum)
        #expect(Set(names.map { $0.lowercased() }).count == names.count)
    }

    @Test("reads nothing from a surroundings read that found no text")
    func nothingWithoutText() {
        #expect(SurroundingsNames.names(in: Surroundings(windowTitle: "Kavitha", text: nil)).isEmpty)
    }

    @Test("leaves out the speaker labels of a chat")
    func leavesOutSpeakerLabels() {
        #expect(SurroundingsNames.names(inText: "Me: hi\nYou: hello\nMeera: hey") == ["Meera"])
    }
}
