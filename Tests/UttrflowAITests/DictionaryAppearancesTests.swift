// Tests for counting the dictionary words a landed dictation wrote.

import Foundation
import Testing
import UttrflowDictionary

@testable import UttrflowAI

@Suite("Which dictionary words a dictation used")
struct DictionaryAppearancesTests {
    private let start = Date(timeIntervalSince1970: 1_700_000_000)

    private func orvanta(used: Int = 0, reverted: Int = 0) -> DictionaryEntry {
        DictionaryEntry(
            word: "Orvanta", origin: .observed, firstSeen: start, timesUsed: used, timesReverted: reverted)
    }

    /// Replays dictations against an entry the way the store counts them, once per dictation.
    private func replay(_ texts: [String], into entry: DictionaryEntry) -> DictionaryEntry {
        var counted = entry
        for text in texts {
            let used = DictionaryAppearances.used([counted], applied: [], writtenIn: text)
            if used == [entry.id] { counted.timesUsed += 1 }
        }
        return counted
    }

    /// Issue 4275: the prompt made the recogniser spell the word, so no correction fired, yet it was used.
    @Test("Counts an entry the recogniser spelled right in each of 40 dictations, 40 times")
    func countsEveryAppearance() {
        let texts = (0..<40).map { "Dictation \($0) went to the Orvanta team today." }
        #expect(replay(texts, into: orvanta()).timesUsed == 40)
    }

    @Test("Keeps a word the recogniser keeps spelling right in the prompt after 60 days")
    func keepsAnAppearingWordInThePrompt() {
        let texts = (0..<40).map { "Orvanta sent note \($0)." }
        let day60 = start.addingTimeInterval(60 * 86_400)
        #expect(WorkingSet.words(from: [orvanta()], now: day60).isEmpty)
        #expect(WorkingSet.words(from: [replay(texts, into: orvanta())], now: day60) == ["Orvanta"])
    }

    /// The boundary test, never a prefix or substring, decides whether the word is there.
    @Test("Does not count a spelling written only inside a longer word")
    func ignoresASpellingInsideAWord() {
        let used = DictionaryAppearances.used([orvanta()], applied: [], writtenIn: "Call Orvantasoft today")
        #expect(used.isEmpty)
    }

    @Test("Counts an entry once when a correction applied it and the text spells it")
    func countsOnceAcrossPaths() {
        let entry = orvanta()
        let other = UUID()
        let used = DictionaryAppearances.used(
            [entry], applied: [entry.id, other, entry.id], writtenIn: "Orvanta and Orvanta")
        #expect(used == [entry.id, other])
    }

    /// Every undone dictation is one appearance and one undo, so the ratio still retires the word.
    @Test("Still retires a word the user undoes every time it appears")
    func undoStillRetires() {
        var entry = replay(Array(repeating: "Orvanta again", count: 5), into: orvanta())
        entry.timesReverted = 5
        #expect(!entry.isTrustworthy)
        #expect(WorkingSet.words(from: [entry], now: start).isEmpty)
    }
}
