// The warning the dictionary editor shows for a word that sounds like ordinary words.
import Foundation
import UttrflowDictionary

extension DictionaryPresenter {
    /// Says so when the typed word would be proposed for ordinary words in the shipped sample sentences; saving stays allowed.
    static func riskNote(for draft: DictionaryDraft) -> String? {
        let word = draft.word.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !word.isEmpty else { return nil }
        let entry = DictionaryEntry(
            word: word, pronunciations: DictionaryEntry.pronunciations(inField: draft.pronunciation),
            origin: .added, firstSeen: Date(timeIntervalSince1970: 0))
        let risk = EntryRiskCheck.risk(of: entry)
        guard risk.isRisky else { return nil }
        return "This may replace ordinary words: it sounds like them in \(risk.sentencesHit) of "
            + "\(risk.sentencesChecked) sample sentences. You can still add it."
    }
}
