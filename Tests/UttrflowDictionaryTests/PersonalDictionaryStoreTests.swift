// Tests for the dictionary store and its error.

import Foundation
import UttrflowCore
import Testing

@testable import UttrflowDictionary

@Suite("Keeping the dictionary between launches")
struct PersonalDictionaryStoreTests {
    // MARK: Where it lives

    /// Its own file beside the history, so clearing the history does not forget colleagues' names.
    @Test("keeps its own versioned file under Application Support")
    func defaultFile() {
        let root = URL(fileURLWithPath: "/tmp/support")
        #expect(
            PersonalDictionaryStore.defaultFile(in: root).path(percentEncoded: false)
                == "/tmp/support/Uttrflow/dictionary.v1.json")
        #expect(PersonalDictionaryStore.defaultFile().lastPathComponent == "dictionary.v1.json")
    }

    // MARK: Adding and reading

    @Test("keeps a word across a restart, folder and all")
    func addAndReload() async throws {
        let sandbox = Sandbox()
        try await PersonalDictionaryStore(file: sandbox.file).add(word("Uttrflow", from: .added))

        let reopened = PersonalDictionaryStore(file: sandbox.file)
        #expect(await reopened.allEntries().map(\.word) == ["Uttrflow"])
        #expect(sandbox.onDisk()?.map(\.word) == ["Uttrflow"])
    }

    @Test("answers with the dictionary as it now stands, so nothing has to be re-read")
    func writesAnswerWithTheList() async throws {
        let store = PersonalDictionaryStore(file: Sandbox().file)
        #expect(try await store.add(word("Uttrflow", from: .added)).map(\.word) == ["Uttrflow"])
        #expect(try await store.add(word("kubectl", from: .added)).count == 2)
    }

    /// Two rows spelling the same word is a visible bug; the newcomer's spelling wins.
    @Test("replaces a word rather than listing it twice")
    func addingReplaces() async throws {
        let sandbox = Sandbox()
        let store = PersonalDictionaryStore(file: sandbox.file)
        let original = word("kubectl", from: .learned)
        try await store.add(original)
        try await store.add(word("Kubectl", from: .added))
        #expect(await store.allEntries().map(\.word) == ["Kubectl"])

        try await store.add(word("Kubectl", saying: "cube cuttle", from: .added, id: original.id))
        #expect(await store.allEntries().count == 1)
        #expect(await store.allEntries().first?.pronunciation == "cube cuttle")
    }

    // MARK: Removing

    @Test("forgets one word and keeps the rest")
    func removeOne() async throws {
        let sandbox = Sandbox()
        let store = PersonalDictionaryStore(file: sandbox.file)
        let doomed = word("Typo", from: .learned)
        try await store.add(doomed)
        try await store.add(word("Uttrflow", from: .added))

        #expect(try await store.remove(doomed.id).map(\.word) == ["Uttrflow"])
        #expect(sandbox.onDisk()?.map(\.word) == ["Uttrflow"])
    }

    /// The caller asked for it to be gone, and it is.
    @Test("treats forgetting a word it never knew as success")
    func removeUnknown() async throws {
        let store = PersonalDictionaryStore(file: Sandbox().file)
        try await store.add(word("Uttrflow", from: .added))
        #expect(try await store.remove(UUID()).count == 1)
    }

    /// Reaches the disk inside the call, so a user who clears and quits does not find it still there.
    @Test("leaves nothing on disk when everything is forgotten")
    func removeEverything() async throws {
        let sandbox = Sandbox()
        let store = PersonalDictionaryStore(file: sandbox.file)
        try await store.add(word("Uttrflow", from: .added))
        try await store.removeEverything()

        #expect(await store.allEntries().isEmpty)
        #expect(sandbox.onDisk() == nil)
        #expect(FileManager.default.fileExists(atPath: sandbox.file.path(percentEncoded: false)) == false)
    }

    /// The operation the design is insured by: inferences go, typed-in words stay.
    @Test("throws away everything it worked out and keeps everything it was taught")
    func removeLearned() async throws {
        let sandbox = Sandbox()
        let store = PersonalDictionaryStore(file: sandbox.file)
        try await store.add(word("Nikhil", from: .added))
        try await store.add(word("Mis-heard", from: .learned))
        try await store.add(word("Overheard", from: .observed))
        try await store.add(word("kubectl", from: .added))

        #expect(try await store.removeLearned().map(\.word) == ["Nikhil", "kubectl"])
        #expect(sandbox.onDisk()?.map(\.word) == ["Nikhil", "kubectl"])
    }

    /// The user hand-taught nothing, so the reset leaves nothing, and no file either.
    @Test("leaves nothing behind when everything was learned")
    func removeLearnedCanEmptyTheFile() async throws {
        let sandbox = Sandbox()
        let store = PersonalDictionaryStore(file: sandbox.file)
        try await store.add(word("Mis-heard", from: .learned))
        #expect(try await store.removeLearned().isEmpty)
        #expect(sandbox.onDisk() == nil)
    }

    // MARK: What the editor sends

    @Test("keeps a typed word as one the user added themselves")
    func addingByHand() async throws {
        let store = PersonalDictionaryStore(file: Sandbox().file)
        try await store.add(word: "Uttrflow", pronunciation: "utter-flow", at: epoch)

        let kept = try #require(await store.allEntries().first)
        #expect(kept.word == "Uttrflow")
        #expect(kept.pronunciation == "utter-flow")
        #expect(kept.origin == .added)
        #expect(kept.firstSeen == epoch)
    }

    @Test("trims what was typed, because surrounding space is not part of the word")
    func addingTrims() async throws {
        let store = PersonalDictionaryStore(file: Sandbox().file)
        try await store.add(word: "  Uttrflow\n", pronunciation: " utter-flow ", at: epoch)
        #expect(await store.allEntries().first?.word == "Uttrflow")
        #expect(await store.allEntries().first?.pronunciation == "utter-flow")
    }

    /// A blank pronunciation is stored as absent, or the word would be indexed under no sound at all.
    @Test("a blank pronunciation is stored as absent, not as an empty string")
    func addingWithoutAPronunciation() async throws {
        let store = PersonalDictionaryStore(file: Sandbox().file)
        try await store.add(word: "Uttrflow", pronunciation: "   ", at: epoch)

        let kept = try #require(await store.allEntries().first)
        #expect(kept.pronunciation == nil)
        #expect(kept.soundsLike == "Uttrflow")
        #expect(await store.index().candidates(soundingLike: "utterflow").map(\.word) == ["Uttrflow"])
    }

    /// The page's list can go stale while the editor is open, and replacing would reset what is known.
    @Test("refuses a word the dictionary already holds rather than replacing it")
    func addingADuplicate() async throws {
        let store = PersonalDictionaryStore(file: Sandbox().file)
        let learnt = word("pgvector", from: .observed, used: 6)
        try await store.add(learnt)

        await #expect(throws: DictionaryStoreError.wordAlreadyKnown) {
            try await store.add(word: "PGVector", pronunciation: "pee gee vector", at: epoch)
        }
        let kept = try #require(await store.allEntries().first)
        #expect(kept.origin == .observed)
        #expect(kept.timesUsed == 6)
    }

    @Test("refuses a word with no spelling, and writes nothing")
    func addingNothing() async throws {
        let store = PersonalDictionaryStore(file: Sandbox().file)
        await #expect(throws: DictionaryStoreError.wordIsEmpty) {
            try await store.add(word: " \n ", pronunciation: "utter-flow", at: epoch)
        }
        #expect(await store.allEntries().isEmpty)
    }

    // MARK: Counting

    @Test("counts the dictations an entry was applied to, and the ones the user undid")
    func counters() async throws {
        let store = PersonalDictionaryStore(file: Sandbox().file)
        let entry = word("Claude", from: .added)
        try await store.add(entry)

        #expect(try await store.recordUse(of: entry.id)?.timesUsed == 1)
        #expect(try await store.recordUse(of: entry.id)?.timesUsed == 2)
        #expect(try await store.recordRevert(of: entry.id)?.timesReverted == 1)
        #expect(await store.allEntries().first?.timesUsed == 2)
    }

    /// The caller holds a list that has drifted from the disk, and is told so.
    @Test("says nothing was counted when the word is not there")
    func countingAnUnknownWord() async throws {
        let store = PersonalDictionaryStore(file: Sandbox().file)
        #expect(try await store.recordUse(of: UUID()) == nil)
        #expect(try await store.recordRevert(of: UUID()) == nil)
    }

    /// Retirement is visible to whoever caused it, not inferred from a lookup that went quiet.
    @Test("shows an entry retiring itself at the moment it happens")
    func retirementIsVisible() async throws {
        let store = PersonalDictionaryStore(file: Sandbox().file)
        let entry = word("Wrong", from: .learned, used: 3, reverted: 1)
        try await store.add(entry)
        #expect(try await store.recordRevert(of: entry.id)?.isTrustworthy == false)
        // Still listed, so the user can see it and see why.
        #expect(await store.allEntries().count == 1)
        #expect(await store.index().candidates(soundingLike: "wrong").isEmpty)
    }

    /// Restore gives a clean slate, so one further mistake does not retire the word again.
    @Test("gives a retired word a clean slate rather than one undo below the line")
    func restoring() async throws {
        let store = PersonalDictionaryStore(file: Sandbox().file)
        let entry = word("Wrong", from: .learned, used: 4, reverted: 3)
        try await store.add(entry)
        #expect(await store.allEntries().first?.isTrustworthy == false)

        let restored = try await store.restore(entry.id)
        #expect(restored?.timesReverted == 0)
        #expect(restored?.isTrustworthy == true)
        // Applied again, and one more mistake does not retire it a second time.
        #expect(try await store.recordRevert(of: entry.id)?.isTrustworthy == true)
        // Back in the index, which is the whole point: a restored word is applied again.
        #expect(await store.index().candidates(soundingLike: "wrong").map(\.word) == ["Wrong"])
    }

    /// The use count is a fact the user has not disputed, and carries the three-use grace period.
    @Test("restoring keeps the use count")
    func restoringKeepsUses() async throws {
        let store = PersonalDictionaryStore(file: Sandbox().file)
        let entry = word("Wrong", from: .learned, used: 4, reverted: 3)
        try await store.add(entry)
        #expect(try await store.restore(entry.id)?.timesUsed == 4)
    }

    @Test("says nothing was restored when the word is not there")
    func restoringAnUnknownWord() async throws {
        let store = PersonalDictionaryStore(file: Sandbox().file)
        #expect(try await store.restore(UUID()) == nil)
    }

    // MARK: The index

    @Test("hands out an index of everything it holds")
    func index() async throws {
        let store = PersonalDictionaryStore(file: Sandbox().file)
        try await store.add(word("Claude", from: .added))
        #expect(await store.index().candidates(soundingLike: "clawed").map(\.word) == ["Claude"])
    }

    /// The index is built once and kept, but a write must throw it away.
    @Test("rebuilds the index after a write and not before one")
    func indexIsCachedUntilSomethingChanges() async throws {
        let store = PersonalDictionaryStore(file: Sandbox().file)
        try await store.add(word("Claude", from: .added))
        let first = await store.index()
        #expect(await store.index() == first)

        try await store.add(word("Uttrflow", from: .added))
        #expect(await store.index() != first)
        #expect(await store.index().candidates(soundingLike: "utterflow").count == 1)
    }

    // MARK: The working set

    @Test("hands the speech layer the words worth conditioning it with")
    func workingSet() async throws {
        let store = PersonalDictionaryStore(file: Sandbox().file)
        try await store.add(word("Uttrflow", from: .added, used: 4, daysAgo: 30))
        try await store.add(word("PaymentSheet", from: .added, daysAgo: 30))

        #expect(await store.workingSet(now: epoch) == ["Uttrflow", "PaymentSheet"])
        #expect(await store.workingSet(limit: 1, now: epoch) == ["Uttrflow"])
        #expect(
            await store.workingSet(
                now: epoch, favouring: AppContext(documentName: "PaymentSheet.swift"))
                == ["PaymentSheet", "Uttrflow"])
    }

    // MARK: A file nobody should lose the app to

    @Test("opens with an empty dictionary when there is no file at all")
    func missingFile() async {
        #expect(await PersonalDictionaryStore(file: Sandbox().file).allEntries().isEmpty)
    }

    /// Absent, truncated or hand-edited all mean the same thing to a user: the app should open.
    @Test("degrades a mangled file to an empty dictionary and writes over it")
    func corruptFile() async throws {
        let sandbox = Sandbox()
        try sandbox.seed(Data("nonsense, entirely".utf8))
        let store = PersonalDictionaryStore(file: sandbox.file)

        #expect(await store.allEntries().isEmpty)
        #expect(try await store.add(word("Uttrflow", from: .added)).map(\.word) == ["Uttrflow"])
        #expect(sandbox.onDisk()?.map(\.word) == ["Uttrflow"])
    }

    // MARK: A disk that says no

    /// An ordinary file where the store expects its folder is the cheapest real refusal there is.
    private func blockedSandbox() throws -> Sandbox {
        let sandbox = Sandbox()
        try FileManager.default.createDirectory(at: sandbox.root, withIntermediateDirectories: true)
        try Data("in the way".utf8).write(to: sandbox.folder)
        return sandbox
    }

    @Test("reports a write the disk refuses rather than swallowing it")
    func writeFailureThrows() async throws {
        let sandbox = try blockedSandbox()
        let store = PersonalDictionaryStore(file: sandbox.file)
        await #expect(throws: DictionaryStoreError.couldNotWrite) {
            try await store.add(word("Uttrflow", from: .added))
        }
    }

    @Test("reports a reset the disk refuses too")
    func resetFailureThrows() async throws {
        // Something must exist for its removal to be attempted, so the file is made undeletable.
        let sandbox = try blockedSandbox()
        let path = sandbox.folder.path(percentEncoded: false)
        let store = PersonalDictionaryStore(file: sandbox.folder)
        try FileManager.default.setAttributes([.immutable: true], ofItemAtPath: path)
        defer { try? FileManager.default.setAttributes([.immutable: false], ofItemAtPath: path) }

        await #expect(throws: DictionaryStoreError.couldNotWrite) {
            try await store.removeEverything()
        }
    }

    /// A reset with nothing to reset is success; there is no file to refuse to delete.
    @Test("treats clearing an empty dictionary as done")
    func clearingNothing() async throws {
        try await PersonalDictionaryStore(file: Sandbox().file).removeEverything()
    }
}

@Suite("What the user is told when the dictionary cannot be saved")
struct DictionaryStoreErrorTests {
    /// Plain language with no engine names, the contract every Uttrflow failure meets.
    @Test("explains itself without naming anything inside the app")
    func message() {
        #expect(
            DictionaryStoreError.couldNotWrite.userMessage
                == "Your dictionary could not be updated on this Mac.")
    }

    /// A refusal is not a disk failure and must not be dressed as one.
    @Test("a word with no spelling is not reported as the disk refusing")
    func refusalReadsAsARefusal() {
        #expect(DictionaryStoreError.wordIsEmpty.userMessage == "Type the word before saving it.")
        #expect(DictionaryStoreError.wordIsEmpty.recovery == nil)
        #expect(
            DictionaryStoreError.wordAlreadyKnown.userMessage
                == "That word is already in your dictionary.")
    }

    /// Nothing offered, because no recovery the user can perform changes whether the disk accepts a write.
    @Test("offers no recovery it cannot actually perform")
    func recovery() {
        #expect(DictionaryStoreError.couldNotWrite.recovery == nil)
    }

    /// Dictation still works. What was lost is a word it would have got right next time.
    @Test("costs the user something, but not the dictation")
    func severity() {
        #expect(DictionaryStoreError.couldNotWrite.severity == .degraded)
        // Nothing was lost, because nothing was offered.
        #expect(DictionaryStoreError.wordIsEmpty.severity == .informational)
        #expect(DictionaryStoreError.wordAlreadyKnown.severity == .informational)
    }

    /// Chained the way `FailureCatalogue` requires, so registering it there is one line.
    @Test("is ready for the failure catalogue")
    func catalogued() {
        #expect(
            DictionaryStoreError.everyCase == [.couldNotWrite, .wordIsEmpty, .wordAlreadyKnown])
        #expect(DictionaryStoreError.firstCase.caseAfter == .wordIsEmpty)
        #expect(DictionaryStoreError.wordAlreadyKnown.caseAfter == nil)
    }
}
