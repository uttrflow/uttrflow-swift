import Foundation
import UttrflowCore
import Testing

@testable import UttrflowAI

// MARK: - Fixtures

/// A directory of its own per test, removed with the test. Real files, because the
/// store's whole job is what happens on disk and a substitute would test the substitute.
private struct Sandbox: ~Copyable {
    let root: URL

    init() {
        root = URL(fileURLWithPath: NSTemporaryDirectory())
            .appending(path: "uttrflow-snippets-\(UUID().uuidString)")
    }

    /// The folder the store is expected to make for itself. Deliberately absent to
    /// begin with.
    var folder: URL { root.appending(path: "Uttrflow") }

    /// The path the store is pointed at.
    var file: URL { folder.appending(path: "snippets.v1.json") }

    /// What is actually on disk — the only honest way to check a deletion reached it.
    func onDisk() -> [Snippet]? {
        guard let data = try? Data(contentsOf: file) else { return nil }
        return try? JSONDecoder().decode([Snippet].self, from: data)
    }

    /// Puts bytes where the store will look, so a test can hand it a file it did not
    /// write: a list from an older build, or a mangled one.
    func seed(_ data: Data) throws {
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        try data.write(to: file)
    }

    func seed(_ snippets: [Snippet]) throws {
        try seed(try JSONEncoder().encode(snippets))
    }

    deinit { try? FileManager.default.removeItem(at: root) }
}

/// A sandbox whose folder is occupied by a file, so nothing can be written inside it.
private func blockedSandbox() throws -> Sandbox {
    let sandbox = Sandbox()
    try FileManager.default.createDirectory(at: sandbox.root, withIntermediateDirectories: true)
    try Data("in the way".utf8).write(to: sandbox.folder)
    return sandbox
}

// MARK: - Tests

@Suite("Snippets, as they are kept")
struct SnippetStoreTests {

    // MARK: Where they live

    @Test("live in their own versioned file inside Uttrflow's Application Support folder")
    func defaultLocation() {
        let file = SnippetStore.defaultFile(in: URL(fileURLWithPath: "/somewhere"))
        #expect(file.path(percentEncoded: false) == "/somewhere/Uttrflow/snippets.v1.json")
    }

    /// Beside the history and the dictionary, never inside either: a user who clears
    /// what they dictated must not thereby lose what they wrote.
    @Test("do not share a file with anything else")
    func separateFromTheOtherStores() {
        let container = URL(fileURLWithPath: "/somewhere")
        #expect(SnippetStore.defaultFile(in: container).lastPathComponent == "snippets.v1.json")
    }

    // MARK: What the editor sends

    @Test("a snippet typed into the editor is kept as typed")
    func savingFromTheEditor() async throws {
        let store = SnippetStore(file: Sandbox().file)
        let kept = try await store.save(
            trigger: "  my address ", expansion: "Flat 402\nLondon", replacing: nil,
            created: snippetEpoch)

        #expect(kept.map(\.trigger) == ["my address"])
        // Verbatim: a snippet that ends in a newline is a snippet that ends in a newline,
        // and trimming the expansion would be Uttrflow editing the user's own writing.
        #expect(kept.map(\.expansion) == ["Flat 402\nLondon"])
        #expect(kept.map(\.created) == [snippetEpoch])
    }

    /// Everything the user did not type survives the edit. Losing any of it would make a
    /// two-year-old snippet look new and reset what had been counted about it.
    @Test("editing keeps the identity, the date it was created and what has been counted")
    func editingKeepsWhatWasNotTyped() async throws {
        let store = SnippetStore(file: Sandbox().file)
        let original = Snippet(
            trigger: "my adress", expansion: "Flat 402", created: snippetEpoch, timesUsed: 7,
            lastUsed: snippetEpoch.addingTimeInterval(3600))
        try await store.save(original)

        let later = snippetEpoch.addingTimeInterval(86_400 * 700)
        let kept = try await store.save(
            trigger: "my address", expansion: "Flat 402", replacing: original.id, created: later)

        #expect(kept.count == 1)
        #expect(kept[0].id == original.id)
        #expect(kept[0].trigger == "my address")
        #expect(kept[0].created == snippetEpoch)
        #expect(kept[0].timesUsed == 7)
        #expect(kept[0].lastUsed == original.lastUsed)
    }

    /// The row was deleted underneath the open editor. Refusing would lose what the user
    /// had just typed, which is a worse answer than keeping it as a new snippet.
    @Test("editing a snippet that is no longer there keeps what was typed, as a new one")
    func editingSomethingDeletedUnderneath() async throws {
        let store = SnippetStore(file: Sandbox().file)
        let later = snippetEpoch.addingTimeInterval(60)
        let kept = try await store.save(
            trigger: "my address", expansion: "Flat 402", replacing: UUID(), created: later)

        #expect(kept.count == 1)
        #expect(kept[0].created == later)
        #expect(kept[0].timesUsed == 0)
    }

    @Test("a trigger with no words in it is refused, and writes nothing")
    func savingNothingFromTheEditor() async throws {
        let store = SnippetStore(file: Sandbox().file)
        await #expect(throws: SnippetStoreError.triggerHasNoWords) {
            try await store.save(
                trigger: "  ", expansion: "Flat 402", replacing: nil, created: snippetEpoch)
        }
        #expect(await store.snippets().isEmpty)
    }

    // MARK: Keeping them

    @Test("a store with no file behind it is empty rather than broken")
    func emptyWhenAbsent() async {
        let sandbox = Sandbox()
        #expect(await SnippetStore(file: sandbox.file).snippets().isEmpty)
    }

    @Test("a saved snippet comes back, and reaches the disk")
    func savingRoundTrips() async throws {
        let sandbox = Sandbox()
        let store = SnippetStore(file: sandbox.file)
        let snippet = makeSnippet(trigger: "my address", expansion: "Flat 402")

        let kept = try await store.save(snippet)

        #expect(kept == [snippet])
        #expect(await store.snippets() == [snippet])
        #expect(sandbox.onDisk() == [snippet])
    }

    /// The list on screen is edited in place, so a row that jumps somewhere else the
    /// moment you save it is a row you then have to hunt for.
    @Test("editing a snippet replaces it where it was, rather than moving it to the end")
    func editingKeepsThePosition() async throws {
        let sandbox = Sandbox()
        let store = SnippetStore(file: sandbox.file)
        let first = makeSnippet(trigger: "one", expansion: "first")
        let second = makeSnippet(trigger: "two", expansion: "second")
        try await store.save(first)
        try await store.save(second)

        let edited = Snippet(
            id: first.id, trigger: "one", expansion: "edited", created: first.created)
        let kept = try await store.save(edited)

        #expect(kept.map(\.expansion) == ["edited", "second"])
    }

    @Test("new snippets arrive at the end, in the order they were created")
    func creationOrderIsKept() async throws {
        let sandbox = Sandbox()
        let store = SnippetStore(file: sandbox.file)
        try await store.save(makeSnippet(trigger: "one"))
        try await store.save(makeSnippet(trigger: "two"))
        try await store.save(makeSnippet(trigger: "three"))

        #expect(await store.snippets().map(\.trigger) == ["one", "two", "three"])
    }

    // MARK: Saying no

    /// A trigger with no words would match at every position; the editor must be told,
    /// not quietly given a row that does nothing.
    @Test("refuses a trigger there is no way to say", arguments: ["", "   ", "???"])
    func refusesAnUnsayableTrigger(trigger: String) async {
        let sandbox = Sandbox()
        let store = SnippetStore(file: sandbox.file)
        await #expect(throws: SnippetStoreError.triggerHasNoWords) {
            try await store.save(makeSnippet(trigger: trigger, expansion: "something"))
        }
    }

    @Test("refuses a snippet with nothing to expand to", arguments: ["", "  \n "])
    func refusesAnEmptyExpansion(expansion: String) async {
        let sandbox = Sandbox()
        let store = SnippetStore(file: sandbox.file)
        await #expect(throws: SnippetStoreError.expansionIsEmpty) {
            try await store.save(makeSnippet(trigger: "quiet", expansion: expansion))
        }
    }

    /// Two snippets answering to one trigger is a question with no right answer, and
    /// the wrong place to discover it is halfway through a dictation.
    @Test("refuses a trigger another snippet already answers to")
    func refusesADuplicateTrigger() async throws {
        let sandbox = Sandbox()
        let store = SnippetStore(file: sandbox.file)
        try await store.save(makeSnippet(trigger: "my address", expansion: "Flat 402"))

        await #expect(throws: SnippetStoreError.triggerAlreadyUsed) {
            // Different punctuation and case, same spoken words, so the same trigger.
            try await store.save(makeSnippet(trigger: "My Address!", expansion: "Level 4"))
        }
        #expect(await store.snippets().count == 1)
    }

    @Test("lets a snippet keep the trigger it already had")
    func editingKeepsItsOwnTrigger() async throws {
        let sandbox = Sandbox()
        let store = SnippetStore(file: sandbox.file)
        let snippet = makeSnippet(trigger: "my address", expansion: "Flat 402")
        try await store.save(snippet)

        let edited = Snippet(
            id: snippet.id, trigger: "my address", expansion: "Level 4",
            created: snippet.created)
        #expect(try await store.save(edited) == [edited])
    }

    // MARK: Forgetting them

    @Test("a deleted snippet is gone from the list and from the disk")
    func deleting() async throws {
        let sandbox = Sandbox()
        let store = SnippetStore(file: sandbox.file)
        let doomed = makeSnippet(trigger: "one")
        let kept = makeSnippet(trigger: "two")
        try await store.save(doomed)
        try await store.save(kept)

        #expect(try await store.delete(doomed.id) == [kept])
        #expect(sandbox.onDisk() == [kept])
    }

    @Test("deleting something that is not there is success, because it is not there")
    func deletingWhatIsAbsent() async throws {
        let sandbox = Sandbox()
        let store = SnippetStore(file: sandbox.file)
        let snippet = makeSnippet(trigger: "one")
        try await store.save(snippet)

        #expect(try await store.delete(UUID()) == [snippet])
    }

    /// Clearing leaves nothing of the user's on disk at all, which is what the button
    /// says on the tin.
    @Test("clearing removes the file rather than writing an empty one")
    func clearing() async throws {
        let sandbox = Sandbox()
        let store = SnippetStore(file: sandbox.file)
        try await store.save(makeSnippet(trigger: "one"))

        try await store.deleteEverything()

        #expect(sandbox.onDisk() == nil)
        #expect(!FileManager.default.fileExists(atPath: sandbox.file.path(percentEncoded: false)))
        #expect(await store.snippets().isEmpty)
    }

    @Test("clearing an already empty store is not an error")
    func clearingNothing() async throws {
        let sandbox = Sandbox()
        try await SnippetStore(file: sandbox.file).deleteEverything()
        #expect(sandbox.onDisk() == nil)
    }

    @Test("deleting the last snippet takes the file with it")
    func deletingTheLastOne() async throws {
        let sandbox = Sandbox()
        let store = SnippetStore(file: sandbox.file)
        let only = makeSnippet(trigger: "one")
        try await store.save(only)

        #expect(try await store.delete(only.id).isEmpty)
        #expect(sandbox.onDisk() == nil)
    }

    // MARK: Counting what fired

    @Test("counts each firing, and remembers when")
    func countingUses() async throws {
        let sandbox = Sandbox()
        let store = SnippetStore(file: sandbox.file)
        let snippet = makeSnippet(trigger: "pr", expansion: "pull request")
        try await store.save(snippet)
        let later = snippetEpoch.addingTimeInterval(60)

        // Said twice in one dictation, so used twice.
        let kept = try await store.recordUse(of: [snippet.id, snippet.id], at: later)

        #expect(kept.first?.timesUsed == 2)
        #expect(kept.first?.lastUsed == later)
        #expect(sandbox.onDisk()?.first?.timesUsed == 2)
    }

    @Test("counting a snippet that has since been deleted changes nothing")
    func countingSomethingAbsent() async throws {
        let sandbox = Sandbox()
        let store = SnippetStore(file: sandbox.file)
        let snippet = makeSnippet(trigger: "pr", expansion: "pull request")
        try await store.save(snippet)

        #expect(try await store.recordUse(of: [UUID()], at: snippetEpoch) == [snippet])
    }

    /// A dictation in which nothing fired must not rewrite the file, or every dictation
    /// would cost a write for no reason.
    @Test("a dictation with no expansions in it does not touch the disk")
    func countingNothingDoesNotWrite() async throws {
        let sandbox = try blockedSandbox()
        let store = SnippetStore(file: sandbox.file)

        // The folder is a file, so any write at all would throw.
        #expect(try await store.recordUse(of: [], at: snippetEpoch).isEmpty)
    }

    // MARK: The matcher it builds

    @Test("hands out a matcher built from what is on disk right now")
    func buildsTheMatcher() async throws {
        let sandbox = Sandbox()
        let store = SnippetStore(file: sandbox.file)
        try await store.save(makeSnippet(trigger: "my address", expansion: "Flat 402"))

        #expect(await store.expander().expand("My address.").text == "Flat 402.")

        try await store.deleteEverything()
        #expect(await store.expander().expand("My address.").text == "My address.")
    }

    // MARK: When the file is not what we left

    @Test(
        "a file nobody could read costs the snippets, not the app",
        arguments: ["not json at all", "{}", "[{\"trigger\":\"one\"}]", ""]
    )
    func corruptFileDegradesToEmpty(contents: String) async throws {
        let sandbox = Sandbox()
        try sandbox.seed(Data(contents.utf8))

        #expect(await SnippetStore(file: sandbox.file).snippets().isEmpty)
    }

    @Test("and the next save simply starts again")
    func savingOverACorruptFile() async throws {
        let sandbox = Sandbox()
        try sandbox.seed(Data("not json at all".utf8))
        let store = SnippetStore(file: sandbox.file)
        let snippet = makeSnippet(trigger: "one")

        #expect(try await store.save(snippet) == [snippet])
        #expect(sandbox.onDisk() == [snippet])
    }

    @Test("a file written by an older build is read whole or not at all")
    func partiallyReadableFile() async throws {
        let sandbox = Sandbox()
        let good = makeSnippet(trigger: "one")
        var encoded = try JSONEncoder().encode([good])
        encoded.removeLast()
        try sandbox.seed(encoded)

        #expect(await SnippetStore(file: sandbox.file).snippets().isEmpty)
    }

    // MARK: When the disk refuses

    @Test("a write the disk refuses is reported, not swallowed")
    func writeFailureThrows() async throws {
        let sandbox = try blockedSandbox()
        let store = SnippetStore(file: sandbox.file)
        await #expect(throws: SnippetStoreError.couldNotWrite) {
            try await store.save(makeSnippet(trigger: "one"))
        }
    }

    @Test("so is a deletion the disk refuses")
    func deleteFailureThrows() async throws {
        let sandbox = Sandbox()
        try sandbox.seed([makeSnippet(trigger: "one")])
        let store = SnippetStore(file: sandbox.file)
        let path = sandbox.folder.path(percentEncoded: false)
        try FileManager.default.setAttributes([.immutable: true], ofItemAtPath: path)
        defer { try? FileManager.default.setAttributes([.immutable: false], ofItemAtPath: path) }

        await #expect(throws: SnippetStoreError.couldNotWrite) {
            try await store.deleteEverything()
        }
    }

    @Test("and a count the disk refuses")
    func countFailureThrows() async throws {
        let sandbox = Sandbox()
        let snippet = makeSnippet(trigger: "one")
        try sandbox.seed([snippet])
        let path = sandbox.folder.path(percentEncoded: false)
        try FileManager.default.setAttributes([.immutable: true], ofItemAtPath: path)
        defer { try? FileManager.default.setAttributes([.immutable: false], ofItemAtPath: path) }

        await #expect(throws: SnippetStoreError.couldNotWrite) {
            try await SnippetStore(file: sandbox.file).recordUse(of: [snippet.id], at: snippetEpoch)
        }
    }
}

// MARK: - What the user is told

@Suite("What a snippet store failure says")
struct SnippetStoreErrorTests {
    @Test("every case explains itself in a complete sentence, with no jargon in it")
    func everyCaseExplainsItself() {
        for failure in SnippetStoreError.everyCase {
            #expect(failure.userMessage.hasSuffix("."), "\(failure) does not finish its sentence")
            #expect(failure.userMessage.first?.isUppercase == true)
            #expect(failure.recovery == nil)
        }
    }

    @Test("the chain reaches every case exactly once")
    func theChainIsComplete() {
        #expect(SnippetStoreError.everyCase.count == 4)
        #expect(Set(SnippetStoreError.everyCase.map(\.userMessage)).count == 4)
        #expect(SnippetStoreError.firstCase == .couldNotWrite)
    }

    /// A disk that refused costs a shortcut; a trigger the editor got wrong costs
    /// nothing at all, and must not be announced as though something broke.
    @Test("only the disk refusing counts as something going wrong")
    func severities() {
        #expect(SnippetStoreError.couldNotWrite.severity == .degraded)
        #expect(SnippetStoreError.triggerHasNoWords.severity == .informational)
        #expect(SnippetStoreError.triggerAlreadyUsed.severity == .informational)
        #expect(SnippetStoreError.expansionIsEmpty.severity == .informational)
    }
}
