// Tests for what a week of dictations teaches the dictionary.

import Foundation
import UttrflowCore
import Testing

@testable import UttrflowDictionary

/// One dictation told to the store as the pipeline tells it; returns the words it taught, usually none.
@discardableResult
private func dictate(
    into store: PersonalDictionaryStore,
    saying heard: String,
    writing wrote: String? = nil,
    titled title: String? = nil,
    over selection: String? = nil,
    at moment: Date = epoch
) async throws -> [String] {
    try await store.learn(
        heard: heard,
        wrote: wrote ?? heard,
        seeing: AppContext(
            applicationName: "Xcode", documentName: title, selectedText: selection),
        at: moment
    ).map(\.word)
}

@Suite("A week of dictations, and what the dictionary keeps")
struct DictionaryLearningTests {
    /// The whole feature driven as it will run: `pgvector` is learnt, and nothing else is.
    @Test("Learns the term that keeps coming back, and nothing else")
    func learnsWhatKeepsComingBack() async throws {
        let sandbox = Sandbox()
        let store = PersonalDictionaryStore(file: sandbox.file)

        #expect(
            try await dictate(
                into: store, saying: "we should try pgvector for this",
                titled: "pgvector — notes"
            ).isEmpty)
        #expect(
            try await dictate(
                into: store, saying: "meeting notes for tomorrow",
                titled: "Meeting notes — tomorrow"
            ).isEmpty)
        #expect(
            try await dictate(
                into: store, saying: "pgvector is fast enough", titled: "pgvector — notes"
            ).isEmpty)
        #expect(
            try await dictate(
                into: store, saying: "let us ship pgvector today", titled: "pgvector — notes")
                == ["pgvector"])

        let entries = try #require(await store.allEntries().first)
        #expect(await store.allEntries().count == 1)
        #expect(entries.word == "pgvector")
        #expect(entries.origin == .observed)
        // Nothing but the word: not the title, not the sentence.
        #expect(entries.pronunciation == nil)
    }

    @Test("numbered titles share one inferred spelling and keep used names in the working set")
    func numberedTitlesDoNotGrowTheDictionary() async throws {
        let sandbox = Sandbox()
        let store = PersonalDictionaryStore(file: sandbox.file)
        try await store.add(word("Marisol", from: .added, used: 5))

        for file in 0..<200 {
            for _ in 0..<3 {
                _ = try await dictate(
                    into: store, saying: "the spreadsheet is open",
                    titled: "Spreadsheet\(file).xlsx")
            }
        }

        let entries = await store.allEntries()
        #expect(
            entries.filter { $0.origin == .observed || $0.origin == .learned }.map(\.word) == ["Spreadsheet"])
        let workingSet = WorkingSet.words(from: entries, limit: 8, now: epoch)
        #expect(workingSet.contains("Marisol"))
        #expect(!workingSet.contains("Spreadsheet199"))
    }

    @Test("bounds inferred entries while preserving added and shipped entries")
    func inferredEntriesStayBounded() async throws {
        let sandbox = Sandbox()
        let store = PersonalDictionaryStore(file: sandbox.file)
        try await store.add(word("UserTerm", from: .added))
        try await store.add(word("ShipTerm", from: .shipped))

        for index in 0...PersonalDictionaryStore.maximumInferredEntries {
            try await store.add(word("Learned\(index)", from: .observed, daysAgo: Double(index)))
        }

        let entries = await store.allEntries()
        #expect(
            entries.filter { $0.origin == .learned || $0.origin == .observed }.count
                == PersonalDictionaryStore.maximumInferredEntries)
        #expect(
            Set(entries.filter { $0.origin == .added || $0.origin == .shipped }.map(\.word)) == [
                "UserTerm", "ShipTerm",
            ])
        #expect(!entries.contains { $0.word == "Learned256" })
    }

    @Test("unused inferred words leave the working set after thirty days")
    func unusedInferredWordsExpireFromWorkingSet() {
        let stale = word("OldTerm", from: .observed, daysAgo: 31)
        let recent = word("NewTerm", from: .learned, daysAgo: 29)
        #expect(WorkingSet.words(from: [stale, recent], now: epoch) == ["NewTerm"])
        #expect(
            WorkingSet.words(from: [word("UsedTerm", from: .observed, used: 1, daysAgo: 90)], now: epoch) == [
                "UsedTerm"
            ])
    }

    @Test("Window chrome does not teach the dictionary while distinct spellings do")
    func ignoresChromeAndKeepsDistinctSpellings() async throws {
        let sandbox = Sandbox()
        let store = PersonalDictionaryStore(file: sandbox.file)
        let chrome = [
            ("Inbox (12) — Mail", "clear the inbox before lunch"),
            ("IMG_4821.HEIC", "the image is too dark"),
            ("Screenshot 2026-09-21 at 10.14.33", "take a screenshot"),
            ("q3-report-final-v2.docx", "the final report is ready"),
            ("a3f9c2e1d — fix login", "fix the login bug"),
            ("Slack | #general | Acme", "post it in general"),
            ("README.md", "readme it later"),
            ("localhost:3000", "local host is ready"),
            ("Downloads", "open downloads"),
            ("Notifications", "check notifications"),
            ("Terminal — zsh", "terminal is ready"),
            ("Spreadsheet1.xlsx", "the spreadsheet is ready"),
        ]
        for _ in 1...LearnableWords.sightingsBeforeLearning {
            for (title, heard) in chrome {
                #expect(try await dictate(into: store, saying: heard, titled: title).isEmpty)
            }
        }
        #expect(await store.allEntries().isEmpty)

        let personal = [
            ("Zorvane — notes", "use Zorvain for this", "Zorvane"),
            ("PaymentSheet.swift", "add a total to the payment sheet", "PaymentSheet"),
            ("Chandrashekhar — notes", "ask Chandra Shekhar about it", "Chandrashekhar"),
            ("Bandra office", "kal Bandaraa office jaana hai", "Bandra"),
            ("pgvector — notes", "we should use PG vector", "pgvector"),
        ]
        for _ in 1...LearnableWords.sightingsBeforeLearning {
            for (title, heard, _) in personal {
                _ = try await dictate(into: store, saying: heard, titled: title)
            }
        }
        #expect(Set(await store.allEntries().map(\.word)) == Set(personal.map(\.2)))
    }

    /// A filter tuned only to English would learn half of Hinglish; the place name is the user's own.
    @Test("Learns a Hinglish speaker's own words and not their ordinary ones")
    func learnsHinglishWithoutTheFillers() async throws {
        let sandbox = Sandbox()
        let store = PersonalDictionaryStore(file: sandbox.file)
        var learnt: [String] = []
        for _ in 1...LearnableWords.sightingsBeforeLearning {
            learnt += try await dictate(
                into: store, saying: "kal Bandra office jaana hai, bilkul theek",
                titled: "Bandra office — bilkul theek")
        }
        #expect(learnt == ["Bandra"])
    }

    /// Learning a deleted word again is the app arguing with the person using it.
    @Test("a word the user deletes is not learnt again")
    func deletingRefusesTheWord() async throws {
        let sandbox = Sandbox()
        let store = PersonalDictionaryStore(file: sandbox.file)
        for _ in 1...LearnableWords.sightingsBeforeLearning {
            try await dictate(into: store, saying: "the pgvector migration", titled: "pgvector — notes")
        }
        let learnt = try #require(await store.allEntries().first)
        #expect(learnt.word == "pgvector")

        try await store.remove(learnt.id)

        // The title and the user still say it, so a cleared tally would count straight back up.
        for _ in 1...(LearnableWords.sightingsBeforeLearning * 2) {
            try await dictate(into: store, saying: "the pgvector migration", titled: "pgvector — notes")
        }
        #expect(await store.allEntries().isEmpty)
    }

    /// Removing learned words clears sightings while a refusal remains stored.
    @Test("removing learned words keeps a deleted word refused after three sightings")
    func removingLearnedKeepsTheRefusal() async throws {
        let sandbox = Sandbox()
        let store = PersonalDictionaryStore(file: sandbox.file)
        for _ in 1...LearnableWords.sightingsBeforeLearning {
            try await dictate(
                into: store, saying: "use Zorvain for this", titled: "Zorvane — notes")
        }
        try await store.remove(#require(await store.allEntries().first).id)
        try await store.removeLearned()

        for _ in 1...LearnableWords.sightingsBeforeLearning {
            try await dictate(
                into: store, saying: "use Zorvain for this", titled: "Zorvane — notes")
        }
        #expect(await store.allEntries().isEmpty)
    }

    /// A word the user typed in and then deleted stays deleted until they type it in again.
    @Test("deleting a word you added yourself refuses it, and typing it in again still works")
    func deletingAnAddedWordRefusesIt() async throws {
        let sandbox = Sandbox()
        let store = PersonalDictionaryStore(file: sandbox.file)
        try await store.add(word: "pgvector", pronunciation: "", at: epoch)
        try await store.remove(#require(await store.allEntries().first).id)

        for _ in 1...(LearnableWords.sightingsBeforeLearning * 2) {
            try await dictate(into: store, saying: "the pgvector migration", titled: "pgvector — notes")
        }
        #expect(await store.allEntries().isEmpty)

        try await store.add(word: "pgvector", pronunciation: "", at: epoch)
        #expect(await store.allEntries().map(\.origin) == [.added])
    }

    /// A relaunch is a new store on the same file, and a deleted word must still be refused there.
    @Test("a word deleted before a relaunch is not learnt again after it")
    func refusalOutlivesARelaunch() async throws {
        let sandbox = Sandbox()
        let before = PersonalDictionaryStore(file: sandbox.file)
        for _ in 1...LearnableWords.sightingsBeforeLearning {
            try await dictate(
                into: before, saying: "use Zorvain for this", titled: "Zorvane — notes")
        }
        try await before.remove(#require(await before.allEntries().first).id)

        let after = PersonalDictionaryStore(file: sandbox.file)
        for _ in 1...LearnableWords.sightingsBeforeLearning {
            try await dictate(
                into: after, saying: "use Zorvain for this", titled: "Zorvane — notes")
        }
        #expect(await after.allEntries().isEmpty)
    }

    /// The refusal remains on disk when learned entries are removed.
    @Test("removing learned words keeps a deleted word refused after a relaunch")
    func learnedRemovalKeepsRefusalAcrossRelaunch() async throws {
        let sandbox = Sandbox()
        let before = PersonalDictionaryStore(file: sandbox.file)
        for _ in 1...LearnableWords.sightingsBeforeLearning {
            try await dictate(
                into: before, saying: "use Zorvain for this", titled: "Zorvane — notes")
        }
        try await before.remove(#require(await before.allEntries().first).id)
        try await before.removeLearned()

        let after = PersonalDictionaryStore(file: sandbox.file)
        for _ in 1...LearnableWords.sightingsBeforeLearning {
            try await dictate(
                into: after, saying: "use Zorvain for this", titled: "Zorvane — notes")
        }
        #expect(await after.allEntries().isEmpty)
    }

    /// Removing everything clears refusals so the user can start over completely.
    @Test("removing everything lets a deleted word be learnt again")
    func removingEverythingLiftsTheRefusal() async throws {
        let sandbox = Sandbox()
        let store = PersonalDictionaryStore(file: sandbox.file)
        for _ in 1...LearnableWords.sightingsBeforeLearning {
            try await dictate(
                into: store, saying: "use Zorvain for this", titled: "Zorvane — notes")
        }
        try await store.remove(#require(await store.allEntries().first).id)
        try await store.removeEverything()

        for _ in 1...LearnableWords.sightingsBeforeLearning {
            try await dictate(
                into: store, saying: "use Zorvain for this", titled: "Zorvane — notes")
        }
        #expect(await store.allEntries().map(\.word) == ["Zorvane"])
    }

    /// The refusal record beside a sandbox's dictionary, decoded as the store writes it.
    private func refusalRecord(of sandbox: borrowing Sandbox) -> [String]? {
        let stem = sandbox.file.deletingPathExtension().lastPathComponent
        let url = sandbox.file.deletingLastPathComponent().appending(path: "\(stem).refused.json")
        guard let data = try? Data(contentsOf: url) else { return nil }
        return try? JSONDecoder().decode([String].self, from: data)
    }

    /// The Dictionary page lists each refused word in the user's spelling, newest first.
    @Test("a deleted word is listed as refused, as spelt, and still is after a relaunch")
    func deletedWordIsListedAsRefused() async throws {
        let sandbox = Sandbox()
        let store = PersonalDictionaryStore(file: sandbox.file)
        try await store.add(word: "Docker", pronunciation: "", at: epoch)
        try await store.add(word: "pgvector", pronunciation: "", at: epoch)
        for entry in await store.allEntries() { try await store.remove(entry.id) }

        #expect(await store.refusedWords() == ["pgvector", "Docker"])
        #expect(refusalRecord(of: sandbox) == ["Docker", "pgvector"])
        #expect(await PersonalDictionaryStore(file: sandbox.file).refusedWords() == ["pgvector", "Docker"])
    }

    /// Allow again is the inverse of deleting: off the list, out of the file, and learnable once more.
    @Test("allowing a refused word again lets three sightings teach it")
    func allowingAgainLiftsTheRefusal() async throws {
        let sandbox = Sandbox()
        let store = PersonalDictionaryStore(file: sandbox.file)
        for _ in 1...LearnableWords.sightingsBeforeLearning {
            try await dictate(
                into: store, saying: "use Zorvain for this", titled: "Zorvane — notes")
        }
        try await store.remove(#require(await store.allEntries().first).id)
        try await store.allowAgain("zorvane")

        #expect(await store.refusedWords().isEmpty)
        #expect(refusalRecord(of: sandbox) == nil)
        let reopened = PersonalDictionaryStore(file: sandbox.file)
        #expect(await reopened.refusedWords().isEmpty)
        for _ in 1...LearnableWords.sightingsBeforeLearning {
            try await dictate(
                into: reopened, saying: "use Zorvain for this", titled: "Zorvane — notes")
        }
        #expect(await reopened.allEntries().map(\.word) == ["Zorvane"])
    }

    /// Lifting one refusal leaves the rest, on the list and in the file.
    @Test("allowing one word again keeps every other refusal")
    func allowingOneKeepsTheRest() async throws {
        let sandbox = Sandbox()
        let store = PersonalDictionaryStore(file: sandbox.file)
        try await store.add(word: "Docker", pronunciation: "", at: epoch)
        try await store.add(word: "pgvector", pronunciation: "", at: epoch)
        for entry in await store.allEntries() { try await store.remove(entry.id) }
        try await store.allowAgain("Docker")
        try await store.allowAgain("never refused")

        #expect(await store.refusedWords() == ["pgvector"])
        #expect(refusalRecord(of: sandbox) == ["pgvector"])
    }

    /// Reset everything empties the list the page shows.
    @Test("removing everything empties the refused list")
    func removingEverythingEmptiesTheList() async throws {
        let sandbox = Sandbox()
        let store = PersonalDictionaryStore(file: sandbox.file)
        try await store.add(word: "Docker", pronunciation: "", at: epoch)
        try await store.remove(#require(await store.allEntries().first).id)
        try await store.removeEverything()
        #expect(await store.refusedWords().isEmpty)
        #expect(refusalRecord(of: sandbox) == nil)
    }

    /// The one path where the user is telling us; one dictation is enough because it is deliberate.
    @Test("Learns a correction the first time the user makes one")
    func learnsACorrectionAtOnce() async throws {
        let sandbox = Sandbox()
        let store = PersonalDictionaryStore(file: sandbox.file)
        let learnt = try await dictate(
            into: store, saying: "Uttrflow", writing: "Uttrflow", titled: "notes",
            over: "utter flow")

        #expect(learnt == ["Uttrflow"])
        #expect(await store.allEntries().first?.origin == .learned)
    }

    /// The loop closing: what one dictation taught, the next is conditioned on.
    @Test("Puts what it learnt in front of the recogniser next time")
    func closesTheLoop() async throws {
        let sandbox = Sandbox()
        let store = PersonalDictionaryStore(file: sandbox.file)
        try await dictate(into: store, saying: "Uttrflow", titled: "notes", over: "utter flow")

        let ranked = WorkingSet.words(from: await store.allEntries(), now: epoch)
        #expect(ranked.contains("Uttrflow"))
        #expect(await store.index().candidates(soundingLike: "utter flow").map(\.word) == ["Uttrflow"])
    }

    /// `add(_:)` replaces an entry with counters at zero, so a typed-in word is never overwritten.
    @Test("Never overwrites a word the user typed in")
    func leavesTheUsersOwnWordsAlone() async throws {
        let sandbox = Sandbox()
        try sandbox.seed([word("Uttrflow", from: .added, used: 7)])
        let store = PersonalDictionaryStore(file: sandbox.file)

        #expect(
            try await dictate(into: store, saying: "Uttrflow", titled: "notes", over: "utter flow")
                .isEmpty)
        #expect(await store.allEntries().map(\.timesUsed) == [7])
        #expect(await store.allEntries().map(\.origin) == [.added])
    }

    /// Nearly every dictation teaches nothing, and must not put a disk write on every sentence.
    @Test("Writes nothing when there was nothing to learn")
    func writesNothingWhenThereIsNothingToLearn() async throws {
        let sandbox = Sandbox()
        let store = PersonalDictionaryStore(file: sandbox.file)

        #expect(try await dictate(into: store, saying: "hello there").isEmpty)
        #expect(sandbox.onDisk() == nil)
    }

    @Test("Keeps what it learnt across a restart")
    func learntWordsSurviveARestart() async throws {
        let sandbox = Sandbox()
        try await dictate(
            into: PersonalDictionaryStore(file: sandbox.file), saying: "Uttrflow",
            titled: "notes", over: "utter flow")

        #expect(sandbox.onDisk()?.map(\.word) == ["Uttrflow"])
        #expect(await PersonalDictionaryStore(file: sandbox.file).allEntries().count == 1)
    }

    // MARK: - The reset

    /// The promise the feature is sold under: everything worked out goes, everything typed in stays.
    @Test("Forgets both kinds of learnt word and keeps the typed-in one")
    func theResetIsComplete() async throws {
        let sandbox = Sandbox()
        try sandbox.seed([word("kubectl", from: .added)])
        let store = PersonalDictionaryStore(file: sandbox.file)

        try await dictate(into: store, saying: "Uttrflow", titled: "notes", over: "utter flow")
        for _ in 1...LearnableWords.sightingsBeforeLearning {
            try await dictate(into: store, saying: "try pgvector", titled: "pgvector — notes")
        }
        #expect(await store.allEntries().count == 3)

        #expect(try await store.removeLearned().map(\.word) == ["kubectl"])
    }

    /// Half-counted evidence surviving the reset would learn a word one dictation later.
    @Test("Forgets the half-counted evidence too, not just the words")
    func theResetForgetsWhatWasNearlyLearnt() async throws {
        let sandbox = Sandbox()
        let store = PersonalDictionaryStore(file: sandbox.file)
        for _ in 1..<LearnableWords.sightingsBeforeLearning {
            try await dictate(into: store, saying: "try pgvector", titled: "pgvector — notes")
        }

        try await store.removeLearned()

        #expect(
            try await dictate(into: store, saying: "try pgvector", titled: "pgvector — notes")
                .isEmpty)
    }

    @Test("Forgets the half-counted evidence when everything goes as well")
    func removingEverythingForgetsTheEvidence() async throws {
        let sandbox = Sandbox()
        let store = PersonalDictionaryStore(file: sandbox.file)
        for _ in 1..<LearnableWords.sightingsBeforeLearning {
            try await dictate(into: store, saying: "try pgvector", titled: "pgvector — notes")
        }

        try await store.removeEverything()

        #expect(
            try await dictate(into: store, saying: "try pgvector", titled: "pgvector — notes")
                .isEmpty)
    }

    /// Bulk removal follows the single removal rule: every inferred word removed is refused.
    @Test("Forget learned words refuses them, so the same sightings do not bring them back")
    func forgettingLearnedWordsRefusesThem() async throws {
        let sandbox = Sandbox()
        let store = PersonalDictionaryStore(file: sandbox.file)
        for _ in 1...LearnableWords.sightingsBeforeLearning {
            try await dictate(into: store, saying: "use Zorvain for this", titled: "Zorvane — notes")
        }
        #expect(await store.allEntries().count == 1)
        try await store.removeLearned()

        for _ in 1...LearnableWords.sightingsBeforeLearning {
            try await dictate(into: store, saying: "use Zorvain for this", titled: "Zorvane — notes")
        }
        #expect(await store.allEntries().isEmpty)
    }

    @Test("Removing twenty words in one call refuses all twenty in one refusal record")
    func removingSeveralRefusesEach() async throws {
        let sandbox = Sandbox()
        let store = PersonalDictionaryStore(file: sandbox.file)
        for index in 0..<20 {
            try await store.add(word: "Wordling\(index)x", pronunciation: "", at: epoch)
        }
        let ids = Set(await store.allEntries().map(\.id))
        #expect(try await store.remove(ids).isEmpty)
        let record = sandbox.file.deletingLastPathComponent()
            .appending(path: "\(sandbox.file.deletingPathExtension().lastPathComponent).refused.json")
        let refused = try JSONDecoder().decode([String].self, from: Data(contentsOf: record))
        #expect(refused.count == 20)
    }

    @Test("A batch larger than the refusal cap keeps the newest refusals")
    func aBatchPastTheCapLapsesTheOldest() async throws {
        let sandbox = Sandbox()
        let store = PersonalDictionaryStore(file: sandbox.file)
        let words = (0..<600).map { "Wordling\($0)x" }
        for word in words { try await store.add(word: word, pronunciation: "", at: epoch) }
        try await store.remove(Set(await store.allEntries().map(\.id)))
        let record = sandbox.file.deletingLastPathComponent()
            .appending(path: "\(sandbox.file.deletingPathExtension().lastPathComponent).refused.json")
        let refused = try JSONDecoder().decode([String].self, from: Data(contentsOf: record))
        #expect(refused.count == SightingLedger.maximumRefused)
    }
}
