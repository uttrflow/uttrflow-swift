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
        let store = PersonalDictionaryStore(file: Sandbox().file)

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

    /// A filter tuned only to English would learn half of Hinglish; the place name is the user's own.
    @Test("Learns a Hinglish speaker's own words and not their ordinary ones")
    func learnsHinglishWithoutTheFillers() async throws {
        let store = PersonalDictionaryStore(file: Sandbox().file)
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
        let store = PersonalDictionaryStore(file: Sandbox().file)
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

    /// A reset is the user asking to start again, deleted words included.
    @Test("a reset lets a deleted word be learnt again")
    func resettingLiftsTheRefusal() async throws {
        let store = PersonalDictionaryStore(file: Sandbox().file)
        for _ in 1...LearnableWords.sightingsBeforeLearning {
            try await dictate(into: store, saying: "the pgvector migration", titled: "pgvector — notes")
        }
        try await store.remove(#require(await store.allEntries().first).id)
        try await store.removeLearned()

        for _ in 1...LearnableWords.sightingsBeforeLearning {
            try await dictate(into: store, saying: "the pgvector migration", titled: "pgvector — notes")
        }
        #expect(await store.allEntries().map(\.word) == ["pgvector"])
    }

    /// A word the user typed in and then deleted is theirs to change their mind about.
    @Test("deleting a word you added yourself does not refuse it")
    func deletingAnAddedWordDoesNotRefuseIt() async throws {
        let store = PersonalDictionaryStore(file: Sandbox().file)
        try await store.add(word: "pgvector", pronunciation: "", at: epoch)
        try await store.remove(#require(await store.allEntries().first).id)

        for _ in 1...LearnableWords.sightingsBeforeLearning {
            try await dictate(into: store, saying: "the pgvector migration", titled: "pgvector — notes")
        }
        #expect(await store.allEntries().map(\.word) == ["pgvector"])
    }

    /// The one path where the user is telling us; one dictation is enough because it is deliberate.
    @Test("Learns a correction the first time the user makes one")
    func learnsACorrectionAtOnce() async throws {
        let store = PersonalDictionaryStore(file: Sandbox().file)
        let learnt = try await dictate(
            into: store, saying: "Uttrflow", writing: "Uttrflow", titled: "notes",
            over: "utter flow")

        #expect(learnt == ["Uttrflow"])
        #expect(await store.allEntries().first?.origin == .learned)
    }

    /// The loop closing: what one dictation taught, the next is conditioned on.
    @Test("Puts what it learnt in front of the recogniser next time")
    func closesTheLoop() async throws {
        let store = PersonalDictionaryStore(file: Sandbox().file)
        try await dictate(into: store, saying: "Uttrflow", titled: "notes", over: "utter flow")

        #expect(await store.workingSet(now: epoch).contains("Uttrflow"))
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
        let store = PersonalDictionaryStore(file: Sandbox().file)
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
        let store = PersonalDictionaryStore(file: Sandbox().file)
        for _ in 1..<LearnableWords.sightingsBeforeLearning {
            try await dictate(into: store, saying: "try pgvector", titled: "pgvector — notes")
        }

        try await store.removeEverything()

        #expect(
            try await dictate(into: store, saying: "try pgvector", titled: "pgvector — notes")
                .isEmpty)
    }
}
