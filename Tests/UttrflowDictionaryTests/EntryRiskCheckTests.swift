import Foundation
import Testing

@testable import UttrflowDictionary

@Suite("The dictionary entry risk check")
struct EntryRiskCheckTests {
    private func entry(_ word: String, sounding: [String] = []) -> DictionaryEntry {
        DictionaryEntry(
            word: word, pronunciations: sounding, origin: .added, firstSeen: Date(timeIntervalSince1970: 0))
    }

    @Test("an entry spelled for a common word's sound is flagged")
    func commonSoundFlagged() {
        #expect(EntryRiskCheck.risk(of: entry("Cee", sounding: ["see"])).isRisky)
        #expect(EntryRiskCheck.risk(of: entry("Ayr", sounding: ["air"])).isRisky)
    }

    @Test("a word followed by punctuation still counts")
    func punctuationIsIgnored() {
        let sentences = ["I will see.", "Did you see!", "Nothing here", "Nor here"]
        let risk = EntryRiskCheck.risk(of: entry("Cee", sounding: ["see"]), sentences: sentences)
        #expect(risk.sentencesHit == 2)
    }

    @Test("an unusual word is not flagged")
    func unusualWordNotFlagged() {
        #expect(!EntryRiskCheck.risk(of: entry("Zyxel")).isRisky)
    }

    @Test("twenty unusual invented words raise no false flag")
    func falseFlagRate() {
        let words = [
            "Quenzara", "Blorvex", "Tamsinger", "Vikrolo", "Drumlevin", "Oskarnath", "Pellucida",
            "Xandrith", "Muvelto", "Karnaby", "Zephyrine", "Hollowmere", "Brandovik", "Siltrane",
            "Nimbrel", "Gorvanti", "Ulverath", "Tessaly", "Fronkel", "Ardwyn",
        ]
        let flagged = words.filter { EntryRiskCheck.risk(of: entry($0)).isRisky }
        #expect(flagged.isEmpty, "false flags: \(flagged)")
    }

    @Test("the sentence set holds forty sentences")
    func setSize() {
        #expect(EntryRiskSentences.all.count == 40)
    }
}
