import CryptoKit
import Foundation
import Security
import Synchronization
import Testing
import UttrflowCore
import UttrflowPredict

@testable import UttrflowPredictStore

/// A database of its own per test, removed when the test ends; every suite in this target shares it.
struct Corpus: ~Copyable {
    let path: String

    init() {
        path = NSTemporaryDirectory() + "uttrflow-corpus-\(UUID().uuidString).sqlite"
        remove()
    }

    /// Removes the file and the two SQLite writes beside it.
    func remove() {
        for suffix in ["", "-wal", "-shm"] {
            try? FileManager.default.removeItem(atPath: path + suffix)
        }
    }

    deinit { remove() }
}

/// Opens a store on a fresh file, so each test starts from nothing.
func store(_ corpus: borrowing Corpus) throws -> PredictStore {
    try PredictStore(path: corpus.path)
}

private func isExcludedFromBackup(_ url: URL) throws -> Bool {
    let values = try url.resourceValues(forKeys: [.isExcludedFromBackupKey])
    return values.isExcludedFromBackup == true
}

private let terminal = Surface(bundleIdentifier: "com.example.terminal", role: "AXTextArea")
private let moment = Date(timeIntervalSince1970: 1_800_000_000)

private struct CorpusKeys: StoreKeyProviding {
    let value: SymmetricKey
    func key(createIfMissing _: Bool) throws -> SymmetricKey { value }
}

private struct UnavailableCorpusKeys: StoreKeyProviding {
    let status: Int32
    func key(createIfMissing _: Bool) throws -> SymmetricKey {
        throw StoreKeyError.unavailable(status)
    }
}

private final class RevocableCorpusKeys: StoreKeyProviding, StoreKeyRevoking, Sendable {
    private let stored = Mutex<SymmetricKey?>(nil)

    func key(createIfMissing: Bool) throws -> SymmetricKey {
        try stored.withLock { current in
            if let current { return current }
            guard createIfMissing else {
                throw StoreKeyError.unavailable(Int32(errSecItemNotFound))
            }
            let generated = SymmetricKey(size: .bits256)
            current = generated
            return generated
        }
    }

    func revokeKey() throws { stored.withLock { $0 = nil } }
}

@Suite("Encrypted suggestion corpus")
struct EncryptedPredictStoreTests {
    @Test("sealed snapshots hide typed lines and reopen without plaintext sidecars")
    func encryptedRoundTrip() async throws {
        let corpus = Corpus()
        let key = CorpusKeys(value: SymmetricKey(size: .bits256))
        let store = try PredictStore(path: corpus.path, encryptedStore: EncryptedStore(keys: key))
        try await store.record("distinctive corpus phrase", in: terminal, at: moment)

        let bytes = try Data(contentsOf: URL(filePath: corpus.path))
        #expect(EncryptedStore.isSealed(bytes))
        #expect(!String(decoding: bytes, as: UTF8.self).contains("distinctive corpus phrase"))
        #expect(!FileManager.default.fileExists(atPath: corpus.path + "-wal"))
        #expect(!FileManager.default.fileExists(atPath: corpus.path + "-shm"))

        let reopened = try PredictStore(path: corpus.path, encryptedStore: EncryptedStore(keys: key))
        #expect(try await reopened.recent(in: terminal, limit: 5) == ["distinctive corpus phrase"])
    }

    @Test("legacy plaintext databases migrate with their rows into an encrypted snapshot")
    func migratesLegacyDatabase() async throws {
        let corpus = Corpus()
        let legacy = try PredictStore(path: corpus.path)
        try await legacy.record("legacy private phrase", in: terminal, at: moment)
        #expect(FileManager.default.fileExists(atPath: corpus.path + "-wal"))
        let key = CorpusKeys(value: SymmetricKey(size: .bits256))

        let migrated = try PredictStore(path: corpus.path, encryptedStore: EncryptedStore(keys: key))

        #expect(try await migrated.recent(in: terminal, limit: 5) == ["legacy private phrase"])
        #expect(EncryptedStore.isSealed(try Data(contentsOf: URL(filePath: corpus.path))))
        #expect(!FileManager.default.fileExists(atPath: corpus.path + "-wal"))
        #expect(!FileManager.default.fileExists(atPath: corpus.path + "-shm"))
        _ = legacy
    }

    @Test("a wrong key refuses to open and leaves the encrypted snapshot untouched")
    func wrongKeyDoesNotReplaceSnapshot() throws {
        let corpus = Corpus()
        let original = CorpusKeys(value: SymmetricKey(size: .bits256))
        let store = try PredictStore(path: corpus.path, encryptedStore: EncryptedStore(keys: original))
        let bytes = try Data(contentsOf: URL(filePath: corpus.path))
        let wrong = CorpusKeys(value: SymmetricKey(size: .bits256))

        do {
            _ = try PredictStore(path: corpus.path, encryptedStore: EncryptedStore(keys: wrong))
            Issue.record("Opening with another key unexpectedly succeeded")
        } catch let error {
            #expect(error == .cannotOpen("encrypted corpus could not be authenticated"))
        }

        #expect(try Data(contentsOf: URL(filePath: corpus.path)) == bytes)
        _ = store
    }

    @Test("a revoked corpus key sets its old snapshot aside and starts an empty corpus")
    func missingKeyStartsEmptyCorpus() async throws {
        let corpus = Corpus()
        let keys = RevocableCorpusKeys()
        let encryptedStore = EncryptedStore(keys: keys)
        let store = try PredictStore(path: corpus.path, encryptedStore: encryptedStore)
        try await store.record("private saved line", in: terminal, at: moment)
        let original = try Data(contentsOf: URL(filePath: corpus.path))

        try encryptedStore.revokeKey()
        let reopened = try PredictStore(path: corpus.path, encryptedStore: encryptedStore)

        #expect(try await reopened.recent(in: terminal, limit: 5).isEmpty)
        #expect(LocalStore.hasSetAside(URL(fileURLWithPath: corpus.path)))
        #expect(try Data(contentsOf: URL(filePath: corpus.path)) != original)
        _ = store
    }

    @Test("a temporarily unavailable corpus key leaves its snapshot in place")
    func unavailableKeyDoesNotReplaceSnapshot() throws {
        let corpus = Corpus()
        let original = CorpusKeys(value: SymmetricKey(size: .bits256))
        let store = try PredictStore(path: corpus.path, encryptedStore: EncryptedStore(keys: original))
        let bytes = try Data(contentsOf: URL(filePath: corpus.path))
        let unavailable = UnavailableCorpusKeys(status: Int32(errSecInteractionNotAllowed))

        do {
            _ = try PredictStore(path: corpus.path, encryptedStore: EncryptedStore(keys: unavailable))
            Issue.record("Opening with an unavailable key unexpectedly succeeded")
        } catch let error {
            #expect(error == .cannotOpen("encrypted corpus could not be authenticated"))
        }

        #expect(try Data(contentsOf: URL(filePath: corpus.path)) == bytes)
        _ = store
    }
}

@Suite("Remembering what was entered")
struct RecordingTests {
    @Test("What was entered comes back when its opening is typed.")
    func roundTrip() async throws {
        let corpus = Corpus()
        let store = try store(corpus)
        try await store.record("git commit -m", in: terminal, at: moment)
        let found = try await store.candidates(for: terminal, matching: "git c")
        #expect(found.map(\.text) == ["git commit -m"])
        #expect(found.first?.evidence?.count == 1)
    }

    @Test(
        "An application's typed lines come back newest first, across its fields, without our own suggestions."
    )
    func recentLinesInApplication() async throws {
        let corpus = Corpus()
        let store = try store(corpus)
        let notes = Surface(bundleIdentifier: "com.example.terminal", role: "AXTextField", locator: "notes")
        try await store.record("older line", in: terminal, at: moment)
        try await store.record("newer line", in: notes, at: moment.addingTimeInterval(60))
        try await store.record(
            "offered line", in: terminal, selfSourced: true, at: moment.addingTimeInterval(120))
        try await store.record(
            "elsewhere", in: Surface(bundleIdentifier: "com.example.other", role: "AXTextArea"), at: moment)
        #expect(
            try await store.recentLines(inApplication: "com.example.terminal", limit: 5) == [
                "newer line", "older line",
            ])
        #expect(
            try await store.recentLines(inApplication: "com.example.terminal", limit: 1) == ["newer line"])
        #expect(try await store.recentLines(inApplication: "com.example.terminal", limit: 0).isEmpty)
    }

    @Test("A line whose command substitution cannot be read is marked irreversible.")
    func unreadableSubstitutionIsIrreversible() async throws {
        let corpus = Corpus()
        let store = try store(corpus)
        try await store.record("rm -rf $(find . -name node_modules)", in: terminal, at: moment)
        let found = try await store.candidates(for: terminal, matching: "rm -rf")
        #expect(found.map(\.isIrreversible) == [true])
    }

    @Test("the corpus database is kept out of backups")
    func databaseIsExcludedFromBackup() async throws {
        let corpus = Corpus()
        let store = try store(corpus)
        try await store.record("git commit -m", in: terminal, at: moment)

        #expect(try isExcludedFromBackup(URL(fileURLWithPath: corpus.path)))
    }

    @Test("Entering the same thing twice counts twice rather than storing it twice.")
    func countsRepeats() async throws {
        let corpus = Corpus()
        let store = try store(corpus)
        for _ in 0..<3 { try await store.record("make verify", in: terminal, at: moment) }
        let found = try await store.candidates(for: terminal, matching: "make")
        #expect(found.count == 1)
        #expect(found.first?.evidence?.count == 3)
    }

    @Test("A future clock reading is clamped when a line is learned.")
    func futureLearningTimestampIsClamped() async throws {
        let corpus = Corpus()
        let store = try store(corpus)
        let future = Date(timeIntervalSince1970: 4_102_444_800)
        try await store.record("deploy future", in: terminal, at: future)

        let candidate = try await store.candidates(for: terminal, matching: "deploy ").first
        #expect((candidate?.evidence?.lastUsed ?? .distantFuture) <= Date())
    }

    @Test("A future timestamp already on disk is clamped when the corpus is read.")
    func futureStoredTimestampIsClampedOnRead() async throws {
        let corpus = Corpus()
        let store = try store(corpus)
        try await store.record("deploy legacy", in: terminal, at: moment)
        let database = try Database(path: corpus.path)
        try database.run("UPDATE entry SET last_used = ? WHERE text = ?") {
            $0.bind(1, 4_102_444_800.0)
            $0.bind(2, "deploy legacy")
        }

        let candidate = try await store.candidates(for: terminal, matching: "deploy ").first
        #expect((candidate?.evidence?.lastUsed ?? .distantFuture) <= Date())
    }

    @Test("A line differing only by case is offered once.")
    func caseVariantsAreDeduplicated() async throws {
        let corpus = Corpus()
        let store = try store(corpus)
        try await store.record("Hello", in: terminal, at: moment)
        try await store.record("hello", in: terminal, at: moment.addingTimeInterval(1))

        let found = try await store.candidates(for: terminal, matching: "h")
        #expect(found.map(\.text).count == 1)
        #expect(found.first?.text == "hello")
        #expect(found.first?.evidence?.count == 2)
    }

    @Test("An empty value is not worth remembering.")
    func ignoresEmpty() async throws {
        let corpus = Corpus()
        let store = try store(corpus)
        try await store.record("", in: terminal, at: moment)
        #expect(try await store.entryCount() == 0)
    }

    @Test("A fragment left behind by an idle is not stored once the whole line it belongs to is known.")
    func fragmentOfALongerLineIsNotStored() async throws {
        let corpus = Corpus()
        let store = try store(corpus)
        try await store.record("git status", in: terminal, at: moment)
        try await store.record("git statu", in: terminal, at: moment)
        try await store.record("gi", in: terminal, at: moment)
        #expect(try await store.candidates(for: terminal, matching: "gi").map(\.text) == ["git status"])
    }

    @Test("A longer line retires the fragments it grew out of, so only the whole value is offered.")
    func longerLineSupersedesItsFragments() async throws {
        let corpus = Corpus()
        let store = try store(corpus)
        try await store.record("git statu", in: terminal, at: moment)
        try await store.record("git status", in: terminal, at: moment)
        #expect(try await store.candidates(for: terminal, matching: "git s").map(\.text) == ["git status"])
    }

    @Test("A shorter grapheme before a multi-scalar completion is recognized as a fragment.")
    func multiScalarCompletionSuppressesFragment() async throws {
        let corpus = Corpus()
        let store = try store(corpus)
        try await store.record("👨‍👩‍👧‍👦", in: terminal, at: moment)
        try await store.record("👨‍👩‍👧‍👦 end", in: terminal, at: moment)

        #expect(try await store.candidates(for: terminal, matching: "👨‍👩‍👧‍👦").map(\.text) == ["👨‍👩‍👧‍👦 end"])
    }

    @Test("A shorter grapheme after a multi-scalar completion stays a fragment.")
    func multiScalarCompletionSuppressesLateFragment() async throws {
        let corpus = Corpus()
        let store = try store(corpus)
        try await store.record("👨‍👩‍👧‍👦 end", in: terminal, at: moment)
        try await store.record("👨‍👩‍👧‍👦", in: terminal, at: moment)

        #expect(try await store.candidates(for: terminal, matching: "👨‍👩‍👧‍👦").map(\.text) == ["👨‍👩‍👧‍👦 end"])
    }

    @Test("Prefix hygiene ignores case, so a capitalised fragment is still recognised as one.")
    func fragmentSuppressionIgnoresCase() async throws {
        let corpus = Corpus()
        let store = try store(corpus)
        try await store.record("Git Status", in: terminal, at: moment)
        try await store.record("git st", in: terminal, at: moment)
        #expect(try await store.candidates(for: terminal, matching: "git").map(\.text) == ["Git Status"])
    }

    @Test("A line that only shares an opening is not a fragment, so both are kept.")
    func siblingsAreBothKept() async throws {
        let corpus = Corpus()
        let store = try store(corpus)
        try await store.record("git push", in: terminal, at: moment)
        try await store.record("git pull", in: terminal, at: moment)
        #expect(try await store.candidates(for: terminal, matching: "git p").count == 2)
    }

    @Test("Nothing typed means nothing offered, because everything would match.")
    func emptyQueryOffersNothing() async throws {
        let corpus = Corpus()
        let store = try store(corpus)
        try await store.record("make verify", in: terminal, at: moment)
        #expect(try await store.candidates(for: terminal, matching: "").isEmpty)
    }

    @Test("A field never typed in has nothing to say, and is not created by asking.")
    func unknownSurfaceIsNotCreated() async throws {
        let corpus = Corpus()
        let store = try store(corpus)
        let elsewhere = Surface(bundleIdentifier: "com.example.other", role: "AXTextField")
        #expect(try await store.candidates(for: elsewhere, matching: "git").isEmpty)
        #expect(try await store.successors(for: elsewhere, after: "x").isEmpty)
    }

    @Test("Two fields in one application keep their own memories.")
    func surfacesAreSeparate() async throws {
        let corpus = Corpus()
        let store = try store(corpus)
        let omnibox = Surface(
            bundleIdentifier: "com.example.browser", role: "AXTextField", locator: "omnibox")
        let search = Surface(bundleIdentifier: "com.example.browser", role: "AXTextField", locator: "search")
        try await store.record("example.com/dashboard", in: omnibox, at: moment)
        #expect(try await store.candidates(for: search, matching: "example").isEmpty)
        #expect(try await store.candidates(for: omnibox, matching: "example").count == 1)
    }

    @Test("The same field in two directories shares what was learned, not walled off by its folder.")
    func scopeDoesNotSeparate() async throws {
        let corpus = Corpus()
        let store = try store(corpus)
        let here = Surface(bundleIdentifier: "com.example.terminal", role: "AXTextArea", scope: "~/one")
        let there = Surface(bundleIdentifier: "com.example.terminal", role: "AXTextArea", scope: "~/two")
        try await store.record("swift build", in: here, at: moment)
        #expect(try await store.candidates(for: there, matching: "swift").count == 1)
    }

    @Test("A phrase entered in two directories is one candidate, its counts summed across both.")
    func scopesMergeIntoOne() async throws {
        let corpus = Corpus()
        let store = try store(corpus)
        let here = Surface(bundleIdentifier: "com.example.terminal", role: "AXTextArea", scope: "~/one")
        let there = Surface(bundleIdentifier: "com.example.terminal", role: "AXTextArea", scope: "~/two")
        try await store.record("swift build", in: here, at: moment)
        try await store.record("swift build", in: there, at: moment)
        try await store.record("swift build", in: there, at: moment)
        let found = try await store.candidates(for: here, matching: "swift")
        #expect(found.count == 1)
        #expect(found.first?.evidence?.count == 3)
    }

    @Test(
        "Sixteen matches from another folder cannot crowd out a far more frequent one, whichever came first.",
        arguments: [false, true])
    func otherFoldersCannotCrowdOut(frequentFirst: Bool) async throws {
        let corpus = Corpus()
        let store = try store(corpus)
        let older = Surface(bundleIdentifier: "com.example.terminal", role: "AXTextArea", scope: "/a")
        let here = Surface(bundleIdentifier: "com.example.terminal", role: "AXTextArea", scope: "/z")
        if frequentFirst {
            for _ in 0..<100 { try await store.record("git status", in: here, at: moment) }
        }
        for index in 0..<16 {
            try await store.record(String(format: "git old-%03d", index), in: older, at: moment)
        }
        if !frequentFirst {
            for _ in 0..<100 { try await store.record("git status", in: here, at: moment) }
        }
        let found = try await store.candidates(for: here, matching: "git ")
        #expect(found.count == 16)
        #expect(found.first?.text == "git status")
    }

    @Test("A suggestion taken rather than typed is recorded as ours, so it counts for less.")
    func selfSourcedIsMarked() async throws {
        let corpus = Corpus()
        let store = try store(corpus)
        try await store.record("git status", in: terminal, selfSourced: true, at: moment)
        let found = try await store.candidates(for: terminal, matching: "git s")
        #expect(found.first?.evidence?.selfSourced == 1)
    }

    @Test("Being offered and taken, or offered and refused, is counted either way.")
    func offersAreCounted() async throws {
        let corpus = Corpus()
        let store = try store(corpus)
        try await store.record("npm run dev", in: terminal, at: moment)
        try await store.recordAccepted("npm run dev", in: terminal)
        try await store.recordRejected("npm run dev", in: terminal)
        try await store.recordRejected("npm run dev", in: terminal)
        let found = try await store.candidates(for: terminal, matching: "npm")
        #expect(found.first?.evidence?.accepted == 1)
        #expect(found.first?.evidence?.rejected == 2)
    }

    @Test("Counting an offer against something never entered changes nothing and does not fail.")
    func offerAgainstUnknown() async throws {
        let corpus = Corpus()
        let store = try store(corpus)
        try await store.recordAccepted("never typed", in: terminal)
        #expect(try await store.entryCount() == 0)
    }
}

@Suite("What usually follows what")
struct SuccessionTests {
    @Test("A command that followed another is offered when that one has just run.")
    func remembersOrder() async throws {
        let corpus = Corpus()
        let store = try store(corpus)
        try await store.record("git add .", in: terminal, at: moment)
        try await store.record("git commit -m", in: terminal, after: "git add .", at: moment)
        let next = try await store.successors(for: terminal, after: "git add .")
        #expect(next.map(\.text) == ["git commit -m"])
        #expect(next.first?.source == .succession)
    }

    @Test("The more often one follows another, the higher it comes.")
    func ordersByHowOften() async throws {
        let corpus = Corpus()
        let store = try store(corpus)
        try await store.record("git push", in: terminal, after: "git commit -m", at: moment)
        for _ in 0..<4 {
            try await store.record("make verify", in: terminal, after: "git commit -m", at: moment)
        }
        let next = try await store.successors(for: terminal, after: "git commit -m")
        #expect(next.first?.text == "make verify")
    }

    @Test("Nothing followed nothing, so an empty predecessor is not recorded.")
    func emptyPredecessorIsIgnored() async throws {
        let corpus = Corpus()
        let store = try store(corpus)
        try await store.record("git status", in: terminal, after: "", at: moment)
        #expect(try await store.successors(for: terminal, after: "").isEmpty)
    }

    @Test("A successor that has since been forgotten is not offered.")
    func forgottenSuccessorIsDropped() async throws {
        let corpus = Corpus()
        let store = try store(corpus)
        try await store.record("git add .", in: terminal, at: moment)
        try await store.record("git commit -m", in: terminal, after: "git add .", at: moment)
        try await store.forget("git commit -m", in: terminal)
        #expect(try await store.successors(for: terminal, after: "git add .").isEmpty)
    }
}

@Suite("Matching what was nearly typed")
struct StoreMatchingTests {
    @Test("A transposed command is found when nothing matches exactly.")
    func fuzzyRescuesATypo() async throws {
        let corpus = Corpus()
        let store = try store(corpus)
        try await store.record("git commit -m", in: terminal, at: moment)
        let found = try await store.candidates(for: terminal, matching: "gti c")
        #expect(found.map(\.text) == ["git commit -m"])
        #expect(found.first?.editDistance == 1)
    }

    @Test(
        "A typed amount is never matched to a different learned amount.",
        arguments: [
            ("12.60", "12.50"), ("1,250", "1,350.00"), ("$130", "$120"),
        ])
    func amountsAreNotCorrected(typed: String, learned: String) async throws {
        let corpus = Corpus()
        let store = try store(corpus)
        try await store.record(learned, in: terminal, at: moment)
        #expect(try await store.candidates(for: terminal, matching: typed).isEmpty)
        #expect(try await store.candidates(for: terminal, matching: String(learned.prefix(3))).count == 1)
    }

    @Test("A query that matches exactly never reaches the fuzzy tier, so its neighbours stay out.")
    func exactSuppressesFuzzy() async throws {
        let corpus = Corpus()
        let store = try store(corpus)
        try await store.record("git push", in: terminal, at: moment)
        try await store.record("git commit -m", in: terminal, at: moment)
        let found = try await store.candidates(for: terminal, matching: "git p")
        #expect(found.map(\.text) == ["git push"])
    }

    @Test("Among more near misses than are returned, the most frequent one is kept.")
    func fuzzyKeepsTheStrongest() async throws {
        let corpus = Corpus()
        let store = try store(corpus)
        for index in 0..<16 {
            try await store.record(String(format: "git old-%03d", index), in: terminal, at: moment)
        }
        for _ in 0..<100 { try await store.record("git status", in: terminal, at: moment) }
        let found = try await store.candidates(for: terminal, matching: "gti ")
        #expect(found.count == 16)
        #expect(found.first?.text == "git status")
    }

    @Test("A line used lately reaches ranking however many older, more frequent lines share its opening.")
    func aRecentLineOutranksStaleFrequentOnes() async throws {
        let corpus = Corpus()
        let store = try store(corpus)
        let monthsAgo = moment - 200 * 86_400
        for index in 0..<(PredictStore.candidateLimit + 4) {
            for _ in 0..<5 {
                try await store.record(
                    String(format: "git stash-%03d end", index), in: terminal, at: monthsAgo)
            }
        }
        for _ in 0..<2 { try await store.record("git switch feature-x", in: terminal, at: moment) }
        let found = try await store.candidates(for: terminal, matching: "git s")
        #expect(found.count == PredictStore.candidateLimit)
        #expect(found.first?.text == "git switch feature-x")
        let scores = found.map { Frecency.score($0, now: moment) }
        #expect(scores.first == scores.max())
    }

    @Test("Two characters are too few to correct, or everything would match.")
    func shortQueriesAreNotCorrected() async throws {
        let corpus = Corpus()
        let store = try store(corpus)
        try await store.record("git commit -m", in: terminal, at: moment)
        #expect(try await store.candidates(for: terminal, matching: "gt").isEmpty)
    }

    @Test("Two Devanagari letters are too few to correct, as two Latin ones are.")
    func shortDevanagariIsNotCorrected() async throws {
        let corpus = Corpus()
        let store = try store(corpus)
        try await store.record("कल मिलते हैं", in: terminal, at: moment)
        try await store.record("आज नहीं", in: terminal, at: moment)
        #expect(try await store.candidates(for: terminal, matching: "नम").isEmpty)
        #expect(try await store.candidates(for: terminal, matching: "आप").isEmpty)
    }

    @Test("One slipped letter in six typed Devanagari letters is still found.")
    func devanagariSlipIsCorrected() async throws {
        let corpus = Corpus()
        let store = try store(corpus)
        try await store.record("कल मिलते हैं", in: terminal, at: moment)
        let found = try await store.candidates(for: terminal, matching: "कल मोल")
        #expect(found.map(\.text) == ["कल मिलते हैं"])
        #expect(found.first?.editDistance == 1)
    }

    @Test("An accented letter counts once, so two typed letters are too few to correct.")
    func accentedLettersCountOnce() async throws {
        let corpus = Corpus()
        let store = try store(corpus)
        try await store.record("cèpes farcies", in: terminal, at: moment)
        #expect(try await store.candidates(for: terminal, matching: "cé").isEmpty)
    }

    @Test("An entry found to be wrong is never offered again, exactly or otherwise.")
    func supersededIsNeverOffered() async throws {
        let corpus = Corpus()
        let store = try store(corpus)
        try await store.record("git comit", in: terminal, at: moment)
        try await store.supersede("git comit", with: "git commit", in: terminal)
        #expect(try await store.candidates(for: terminal, matching: "git c").isEmpty)
        #expect(try await store.candidates(for: terminal, matching: "gti c").isEmpty)
    }

    @Test("Superseding something in a field never typed in changes nothing.")
    func supersedeUnknownSurface() async throws {
        let corpus = Corpus()
        let store = try store(corpus)
        try await store.supersede("a", with: "b", in: terminal)
        #expect(try await store.entryCount() == 0)
    }

    @Test("The prefix range ends where the next letter begins.")
    func upperBound() {
        #expect(PredictStore.upperBound(of: "git c") == "git d")
        #expect(PredictStore.upperBound(of: "a") == "b")
        #expect(PredictStore.upperBound(of: "") == nil)
    }
}

@Suite("Forgetting")
struct ForgettingTests {
    @Test("One entry can be forgotten without touching the rest.")
    func oneEntry() async throws {
        let corpus = Corpus()
        let store = try store(corpus)
        try await store.record("git push", in: terminal, at: moment)
        try await store.record("git pull", in: terminal, at: moment)
        try await store.forget("git push", in: terminal)
        #expect(try await store.candidates(for: terminal, matching: "git p").map(\.text) == ["git pull"])
    }

    @Test("Forgetting a borrowed entry retires it in this scope and leaves the other scope intact.")
    func borrowedEntryStaysForgottenInScope() async throws {
        let corpus = Corpus()
        let store = try store(corpus)
        let folderOne = Surface(bundleIdentifier: "com.example.editor", role: "AXTextArea", scope: "/one")
        let folderTwo = Surface(bundleIdentifier: "com.example.editor", role: "AXTextArea", scope: "/two")
        try await store.record("git push origin main", in: folderOne, at: moment)
        try await store.record("git push origin main", in: folderTwo, at: moment + 1)

        try await store.forget("git push origin main", in: folderOne)

        #expect(try await store.candidates(for: folderOne, matching: "git p").isEmpty)
        #expect(try await store.recent(in: folderOne, limit: 5).isEmpty)
        let remaining = try await store.candidates(for: folderTwo, matching: "git p")
        #expect(remaining.map(\.text) == ["git push origin main"])
    }

    @Test("Everything learned in one application goes together, and other applications stay.")
    func oneApplication() async throws {
        let corpus = Corpus()
        let store = try store(corpus)
        let elsewhere = Surface(bundleIdentifier: "com.example.editor", role: "AXTextArea")
        try await store.record("git push", in: terminal, at: moment)
        try await store.record("some prose", in: elsewhere, at: moment)
        try await store.forget(bundleIdentifier: "com.example.terminal")
        #expect(try await store.entryCount() == 1)
        #expect(try await store.candidates(for: elsewhere, matching: "some").count == 1)
    }

    @Test("Forgetting one application uses the same key as learning under it.")
    func oneApplicationWithMixedCaseIdentifier() async throws {
        let corpus = Corpus()
        let store = try store(corpus)
        let mixed = Surface(bundleIdentifier: "com.example.Terminal", role: "AXTextArea")
        try await store.record("git push", in: mixed, at: moment)
        try await store.forget(bundleIdentifier: "com.example.terminal")
        #expect(try await store.entryCount() == 0)
    }

    @Test("The reset in Settings leaves nothing behind.")
    func everything() async throws {
        let corpus = Corpus()
        let store = try store(corpus)
        try await store.record("git push", in: terminal, at: moment)
        try await store.forgetEverything()
        #expect(try await store.entryCount() == 0)
    }

    @Test("What each application taught is counted by application, across every field in it.")
    func countsByApplication() async throws {
        let corpus = Corpus()
        let store = try store(corpus)
        let search = Surface(bundleIdentifier: "com.example.terminal", role: "AXTextField")
        let elsewhere = Surface(bundleIdentifier: "com.example.editor", role: "AXTextArea")
        try await store.record("git push", in: terminal, at: moment)
        try await store.record("git pull", in: terminal, at: moment)
        try await store.record("find a file", in: search, at: moment)
        try await store.record("some prose", in: elsewhere, at: moment)
        #expect(
            try await store.entryCountsByApplication()
                == ["com.example.terminal": 3, "com.example.editor": 1])
    }

    @Test("A second connection can forget while the first is still open, and the first sees it.")
    func forgetsFromASecondConnection() async throws {
        let corpus = Corpus()
        let first = try store(corpus)
        try await first.record("git push", in: terminal, at: moment)
        try await PredictStore(path: corpus.path).forgetEverything()
        #expect(try await first.entryCount() == 0)
        #expect(try await first.entryCountsByApplication().isEmpty)
    }

    @Test("Forgetting succeeds while another connection holds a read open.")
    func forgetsBesideAnOpenReader() async throws {
        let corpus = Corpus()
        let store = try store(corpus)
        try await store.record("git push", in: terminal, at: moment)
        let reader = try Database(path: corpus.path)
        try reader.execute("BEGIN")
        _ = try reader.rows("SELECT COUNT(*) FROM entry", { _ in }) { $0.integer(0) }
        try await store.forgetEverything()
        #expect(try await store.entryCount() == 0)
        try reader.execute("COMMIT")
    }

    @Test("Forgetting from a field never typed in is not an error.")
    func unknownSurface() async throws {
        let corpus = Corpus()
        let store = try store(corpus)
        try await store.forget("anything", in: terminal)
        #expect(try await store.entryCount() == 0)
    }
}

@Suite("Staying within bounds")
struct RetentionTests {
    @Test("A field stops growing at its cap, and drops what has least behind it.")
    func evictsWeakest() async throws {
        let corpus = Corpus()
        let store = try store(corpus)
        let kept = "kept command"
        for _ in 0..<5 { try await store.record(kept, in: terminal, at: moment) }
        for index in 0..<(PredictStore.entriesPerSurface + 20) {
            try await store.record("filler \(index)", in: terminal, at: moment)
        }
        #expect(try await store.entryCount() <= PredictStore.entriesPerSurface)
        #expect(try await store.candidates(for: terminal, matching: "kept").count == 1)
    }

    @Test(
        "A fragment a longer line grew out of goes before any live one, however much it once had behind it.")
    func evictsFragmentsFirst() async throws {
        let corpus = Corpus()
        let store = try store(corpus)
        for _ in 0..<50 { try await store.record("git comm", in: terminal, at: moment) }
        try await store.record("git commit --amend", in: terminal, at: moment)
        // Each filler ends in a word so none is a fragment of another, which would supersede it too.
        for index in 0..<(PredictStore.entriesPerSurface) {
            try await store.record("filler \(index) end", in: terminal, at: moment)
        }
        let superseded = try Database(path: corpus.path).rows(
            "SELECT COUNT(*) FROM entry WHERE superseded_by IS NOT NULL", { _ in }
        ) { $0.integer(0) }
        #expect(superseded == [0])
        #expect(try await store.entryCount() == PredictStore.entriesPerSurface)
    }

    @Test("A correction or a refusal outlasts every live entry, so a full field never brings the line back.")
    func retirementsOutlastLiveEntries() async throws {
        let corpus = Corpus()
        let store = try store(corpus)
        try await store.record("deploy prod", in: folderTwo, at: moment)
        for index in 0..<(PredictStore.entriesPerSurface - 1) {
            try await store.record("filler \(index) end", in: folderOne, at: moment)
        }
        try await store.record("git comit", in: folderOne, at: moment + 10)
        try await store.supersede("deploy prod", with: "deploy staging", in: folderOne)
        try await store.recordRejection(of: "git comit", in: folderOne)
        #expect(try await store.candidates(for: folderOne, matching: "dep").isEmpty)
        for index in 0..<5 {
            try await store.record("another \(index) end", in: folderOne, at: moment + 20)
        }
        #expect(try await store.candidates(for: folderOne, matching: "dep").isEmpty)
        #expect(try await store.candidates(for: folderOne, matching: "git c").isEmpty)
        #expect(try await store.candidates(for: folderTwo, matching: "dep").count == 1)
    }

    @Test("a superseded borrowed value stays retired when scope capacity is reached")
    func supersededValueSurvivesScopeEviction() async throws {
        let corpus = Corpus()
        let store = try store(corpus)
        let source = Surface(bundleIdentifier: "com.example.editor", role: "AXTextArea", scope: "/source")
        let retired = Surface(bundleIdentifier: "com.example.editor", role: "AXTextArea", scope: "/retired")
        let old = Date(timeIntervalSince1970: 1_700_000_000)
        try await store.record("deploy prod", in: source, at: old)
        try await store.supersede("deploy prod", with: "deploy staging", in: retired)
        #expect(try await store.candidates(for: retired, matching: "dep").isEmpty)
        for index in 0..<PredictStore.surfacesPerField {
            let scope = Surface(
                bundleIdentifier: "com.example.editor", role: "AXTextArea", scope: "/other\(index)")
            try await store.record(
                "unrelated \(index)", in: scope, at: old.addingTimeInterval(Double(index + 1)))
        }
        try await store.record("deploy prod", in: source, at: Date().addingTimeInterval(1))
        #expect(try await store.candidates(for: retired, matching: "dep").isEmpty)
    }

    @Test("a forgotten borrowed value stays retired when scope capacity is reached")
    func forgottenValueSurvivesScopeEviction() async throws {
        let corpus = Corpus()
        let store = try store(corpus)
        let source = Surface(bundleIdentifier: "com.example.editor", role: "AXTextArea", scope: "/source")
        let retired = Surface(bundleIdentifier: "com.example.editor", role: "AXTextArea", scope: "/retired")
        let old = Date(timeIntervalSince1970: 1_700_000_000)
        try await store.record("deploy prod", in: source, at: old)
        try await store.record("local entry", in: retired, at: old)
        try await store.forget("deploy prod", in: retired)
        #expect(try await store.candidates(for: retired, matching: "dep").isEmpty)
        for index in 0..<PredictStore.surfacesPerField {
            let scope = Surface(
                bundleIdentifier: "com.example.editor", role: "AXTextArea", scope: "/other\(index)")
            try await store.record(
                "unrelated \(index)", in: scope, at: old.addingTimeInterval(Double(index + 1)))
        }
        try await store.record("deploy prod", in: source, at: Date().addingTimeInterval(1))
        #expect(try await store.candidates(for: retired, matching: "dep").isEmpty)
    }

    @Test("What follows what stops growing at the same cap, and keeps the pairs followed most.")
    func successionsStayWithinTheCap() async throws {
        let corpus = Corpus()
        let store = try store(corpus)
        for _ in 0..<5 { try await store.record("git push", in: terminal, after: "git commit", at: moment) }
        for index in 0..<(PredictStore.entriesPerSurface + 100) {
            try await store.record(
                "filler \(index) end", in: terminal, after: "before \(index) end", at: moment)
        }
        let counts = try Database(path: corpus.path).rows(
            "SELECT (SELECT COUNT(*) FROM entry), (SELECT COUNT(*) FROM succession)", { _ in }
        ) { [$0.integer(0), $0.integer(1)] }
        #expect(counts == [[PredictStore.entriesPerSurface, PredictStore.entriesPerSurface]])
        #expect(try await store.successors(for: terminal, after: "git commit").map(\.text) == ["git push"])
    }
}

@Suite("Writing all of a record or none of it")
struct TransactionTests {
    @Test("A step that fails takes the steps before it back with it.")
    func failureRollsBack() throws {
        let corpus = Corpus()
        let database = try Database(path: corpus.path)
        try Schema.migrate(database)
        #expect(throws: PredictStoreError.self) {
            try database.transaction { () throws(PredictStoreError) in
                try database.run(
                    "INSERT INTO surface (bundle_id, role) VALUES ('com.example.app', 'AXTextArea')"
                ) {
                    _ in
                }
                try database.execute("SELECT FROM WHERE")
            }
        }
        #expect(try database.rows("SELECT COUNT(*) FROM surface", { _ in }) { $0.integer(0) } == [0])
        #expect(try database.rows("SELECT 1", { _ in }) { $0.integer(0) } == [1])
    }

    @Test("A record that goes through is there for another connection to read.")
    func successCommits() async throws {
        let corpus = Corpus()
        let store = try store(corpus)
        try await store.record("git push", in: terminal, after: "git commit", at: moment)
        let other = try Database(path: corpus.path)
        #expect(try other.rows("SELECT COUNT(*) FROM entry", { _ in }) { $0.integer(0) } == [1])
        #expect(try other.rows("SELECT COUNT(*) FROM succession", { _ in }) { $0.integer(0) } == [1])
    }
}

@Suite("Surviving a broken file")
struct RecoveryTests {
    @Test("A file that is not a database is replaced rather than crashing the app.")
    func replacesRubbish() async throws {
        let corpus = Corpus()
        try Data("this is not a database, it is a haiku".utf8).write(to: URL(fileURLWithPath: corpus.path))
        let store = try store(corpus)
        try await store.record("git push", in: terminal, at: moment)
        #expect(try await store.entryCount() == 1)
    }

    @Test("A database written by a newer build is refused and left exactly as it was, not replaced.")
    func refusesTheFuture() throws {
        let corpus = Corpus()
        do {
            let database = try Database(path: corpus.path)
            try Schema.migrate(database)
            try database.run("UPDATE schema_version SET version = ?") { $0.bind(1, Int64(99)) }
            try database.run("INSERT INTO surface (bundle_id, role) VALUES ('com.example.app', 'AXTextArea')")
            {
                _ in
            }
        }
        let original = try Data(contentsOf: URL(filePath: corpus.path))
        #expect(throws: PredictStoreError.newerThanThisBuild(version: 99)) {
            try PredictStore(path: corpus.path)
        }
        #expect(try Data(contentsOf: URL(filePath: corpus.path)) == original)
    }

    @Test("A file from the build before gains the recency index and the current version on opening.")
    func migratesFromVersionTwo() throws {
        let corpus = Corpus()
        let database = try Database(path: corpus.path)
        try Schema.migrate(database)
        try database.execute("DROP INDEX entry_recent")
        try database.run("UPDATE schema_version SET version = ?") { $0.bind(1, Int64(2)) }
        try Schema.migrate(database)
        let indexes = try database.rows("PRAGMA index_list(entry)", { _ in }) { $0.text(1) }
        #expect(indexes.contains("entry_recent"))
        let version = try database.rows("SELECT version FROM schema_version", { _ in }) { $0.integer(0) }
        #expect(version == [Schema.version])
    }

    @Test("A version five file adds scope recency seeded from its entries.")
    func migratesSurfaceRecency() throws {
        let corpus = Corpus()
        let database = try Database(path: corpus.path)
        try Schema.migrate(database)
        try database.run("INSERT INTO surface (bundle_id, role, scope) VALUES (?, ?, ?)") {
            $0.bind(1, "com.example.term")
            $0.bind(2, "AXTextArea")
            $0.bind(3, "/work")
        }
        try database.run("INSERT INTO entry (surface_id, text, text_lower, last_used) VALUES (1, ?, ?, ?)") {
            $0.bind(1, "make verify")
            $0.bind(2, "make verify")
            $0.bind(3, moment.timeIntervalSince1970)
        }
        // SQLite refuses to drop an indexed column, so a version-five file is rebuilt index first.
        try database.execute("DROP INDEX IF EXISTS surface_recent")
        try database.execute("ALTER TABLE surface DROP COLUMN last_used")
        try database.run("UPDATE schema_version SET version = ?") { $0.bind(1, Int64(5)) }
        let legacyColumns = try database.rows("PRAGMA table_info(surface)", { _ in }) { $0.text(1) }
        #expect(!legacyColumns.contains("last_used"))
        try Schema.migrate(database)
        let recency = try database.rows("SELECT last_used FROM surface WHERE id = 1", { _ in }) {
            $0.double(0)
        }
        #expect(recency == [moment.timeIntervalSince1970])
        let indexes = try database.rows("PRAGMA index_list(surface)", { _ in }) { $0.text(1) }
        #expect(indexes.contains("surface_recent"))
    }

    @Test("A version four file folds mixed-case application rows into one surface.")
    func migratesMixedCaseApplicationKeys() async throws {
        let corpus = Corpus()
        do {
            let database = try Database(path: corpus.path)
            try Schema.migrate(database)
            try database.run("UPDATE schema_version SET version = ?") { $0.bind(1, Int64(4)) }
            for bundle in ["com.example.terminal", "com.example.Terminal"] {
                try database.run("INSERT INTO surface (bundle_id, role) VALUES (?, ?)") {
                    $0.bind(1, bundle)
                    $0.bind(2, "AXTextArea")
                }
            }
            let entries: [(Int64, String, Int64, Int64, Int64)] = [
                (1, "git push", 2, 1, 0), (2, "git push", 3, 0, 1), (2, "git status", 1, 0, 0),
            ]
            for (surface, text, count, accepted, rejected) in entries {
                try database.run(
                    """
                    INSERT INTO entry (surface_id, text, text_lower, count, accepted, rejected, last_used)
                    VALUES (?, ?, ?, ?, ?, ?, ?)
                    """
                ) {
                    $0.bind(1, surface)
                    $0.bind(2, text)
                    $0.bind(3, text.lowercased())
                    $0.bind(4, count)
                    $0.bind(5, accepted)
                    $0.bind(6, rejected)
                    $0.bind(7, moment.timeIntervalSince1970)
                }
            }
            for (surface, previous, next, count) in [
                (Int64(1), "git commit", "git push", Int64(1)),
                (2, "git commit", "git push", 2),
                (2, "git status", "git log", 1),
            ] {
                try database.run(
                    "INSERT INTO succession (surface_id, previous, next, count) VALUES (?, ?, ?, ?)"
                ) {
                    $0.bind(1, surface)
                    $0.bind(2, previous)
                    $0.bind(3, next)
                    $0.bind(4, count)
                }
            }
        }

        let store = try store(corpus)
        let push = try await store.candidates(for: terminal, matching: "git p").first?.evidence
        #expect(push?.count == 5)
        #expect(push?.accepted == 1)
        #expect(push?.rejected == 1)
        #expect(try await store.entryCount() == 2)
        #expect(try await store.successors(for: terminal, after: "git commit").map(\.text) == ["git push"])
        let rows = try Database(path: corpus.path).rows(
            "SELECT bundle_id, COUNT(*) FROM surface GROUP BY bundle_id", { _ in }
        ) { [$0.text(0), String($0.integer(1))] }
        #expect(rows == [["com.example.terminal", "1"]])
        let version = try Database(path: corpus.path).rows("SELECT version FROM schema_version", { _ in }) {
            $0.integer(0)
        }
        #expect(version == [Schema.version])
    }

    @Test("A path that cannot be opened at all is reported rather than pretended about.")
    func reportsAnImpossiblePath() {
        #expect(throws: PredictStoreError.self) {
            try PredictStore(path: "/this/directory/does/not/exist/corpus.sqlite")
        }
    }

    @Test("A statement that is not SQL is reported as a query failure.")
    func reportsABadStatement() throws {
        let corpus = Corpus()
        let database = try Database(path: corpus.path)
        #expect(throws: PredictStoreError.self) { try database.execute("SELECT FROM WHERE") }
    }
}

@Suite("The query that runs on every keystroke")
struct QueryPlanTests {
    /// Fills a database directly, because the point is the plan and not the round trips.
    private func seed(_ path: String, surfaces: Int, each: Int) throws {
        let database = try Database(path: path)
        try Schema.migrate(database)
        try database.execute("BEGIN")
        for surface in 0..<surfaces {
            try database.run(
                "INSERT INTO surface (bundle_id, role, locator, scope) VALUES (?, ?, '', '')"
            ) {
                $0.bind(1, "com.example.app\(surface)")
                $0.bind(2, "AXTextArea")
            }
            let id = database.lastInsertedIdentifier
            for index in 0..<each {
                try database.run(
                    "INSERT INTO entry (surface_id, text, text_lower, count, last_used) VALUES (?, ?, ?, ?, ?)"
                ) {
                    $0.bind(1, id)
                    $0.bind(2, "git command \(index) --flag=\(index)")
                    $0.bind(3, "git command \(index) --flag=\(index)")
                    $0.bind(4, Int64(index % 40 + 1))
                    $0.bind(5, moment.timeIntervalSince1970)
                }
            }
        }
        try database.execute("COMMIT")
    }

    @Test("The prefix query narrows on the text as well as the field, which is the whole point of the index.")
    func usesBothIndexColumns() throws {
        let corpus = Corpus()
        try seed(corpus.path, surfaces: 4, each: 500)
        let database = try Database(path: corpus.path)
        let plan = try database.plan(of: PredictStore.prefixQuery).joined(separator: " | ")
        #expect(plan.contains("USING INDEX entry_prefix"), "the plan was: \(plan)")
        #expect(plan.contains("text_lower>?"), "the plan was: \(plan)")
        #expect(!plan.contains("SCAN entry"), "the plan was: \(plan)")
    }

    @Test("The newest-first prefix query narrows on the text as well as the field.")
    func recentPrefixUsesBothIndexColumns() throws {
        let corpus = Corpus()
        try seed(corpus.path, surfaces: 4, each: 500)
        let database = try Database(path: corpus.path)
        let plan = try database.plan(of: PredictStore.recentPrefixQuery).joined(separator: " | ")
        #expect(plan.contains("USING INDEX entry_prefix"), "the plan was: \(plan)")
        #expect(plan.contains("text_lower>?"), "the plan was: \(plan)")
        #expect(!plan.contains("SCAN entry"), "the plan was: \(plan)")
    }

    @Test("The recency read has an index of its own, so it does not walk the field's rows by hand.")
    func recentReadUsesItsIndex() throws {
        let corpus = Corpus()
        try seed(corpus.path, surfaces: 4, each: 500)
        let database = try Database(path: corpus.path)
        let plan = try database.plan(of: PredictStore.recentQuery).joined(separator: " | ")
        #expect(plan.contains("USING INDEX entry_recent"), "the plan was: \(plan)")
        #expect(!plan.contains("SCAN entry"), "the plan was: \(plan)")
        #expect(!plan.contains("TEMP B-TREE"), "nothing is grouped or sorted in a temporary: \(plan)")
    }

    @Test(
        "Written as a LIKE the same query reads every row of the field, which is why it is not written that way."
    )
    func likeReadsTheWholeSurface() throws {
        let corpus = Corpus()
        try seed(corpus.path, surfaces: 4, each: 500)
        let database = try Database(path: corpus.path)
        let asLike = """
            SELECT text FROM entry
            WHERE surface_id = ? AND text LIKE ? AND superseded_by IS NULL
            ORDER BY count DESC LIMIT ?
            """
        let plan = try database.plan(of: asLike).joined(separator: " | ")
        #expect(!plan.contains("text_lower>?"), "LIKE unexpectedly narrowed the text: \(plan)")
    }

    @Test("A query against twenty thousand entries still returns only what was asked for.")
    func staysBoundedAtScale() async throws {
        let corpus = Corpus()
        try seed(corpus.path, surfaces: 10, each: 2_000)
        let store = try PredictStore(path: corpus.path)
        let surface = Surface(bundleIdentifier: "com.example.app3", role: "AXTextArea")
        let found = try await store.candidates(for: surface, matching: "git command 1")
        #expect(found.count <= PredictStore.candidateLimit)
        #expect(found.allSatisfy { $0.text.hasPrefix("git command 1") })
    }
}

@Suite("Superseding through the verification tier")
struct StoreSupersessionTests {
    @Test("What the gates corrected is superseded here without them having anywhere to report a failure.")
    func recordsThroughTheProtocol() async throws {
        let corpus = Corpus()
        let store = try store(corpus)
        try await store.record("git comit", in: terminal, at: moment)
        let recording: any SupersessionRecording = store
        try await recording.recordSupersession(of: "git comit", by: "git commit", in: terminal)
        #expect(try await store.candidates(for: terminal, matching: "git c").isEmpty)
    }

    @Test("What the gates refused is put out of reach here, with nothing named as replacing it.")
    func recordsARejection() async throws {
        let corpus = Corpus()
        let store = try store(corpus)
        try await store.record("git zqxjw", in: terminal, at: moment)
        let recording: any SupersessionRecording = store
        try await recording.recordRejection(of: "git zqxjw", in: terminal)
        #expect(try await store.candidates(for: terminal, matching: "git z").isEmpty)
    }
}

@Suite("Where the corpus lives")
struct PredictStoreLocationTests {
    @Test("It sits in Uttrflow's own folder, versioned in its name.")
    func inTheAppsOwnFolder() {
        let file = PredictStore.defaultFile(in: URL(filePath: "/tmp/support"))
        #expect(file.path(percentEncoded: false) == "/tmp/support/Uttrflow/predict.v1.sqlite")
    }

    @Test("A folder that does not exist yet is made rather than refused.")
    func makesItsOwnFolder() throws {
        let root = URL(filePath: NSTemporaryDirectory()).appending(path: UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let file = PredictStore.defaultFile(in: root)
        _ = try PredictStore(path: file.path(percentEncoded: false))
        #expect(FileManager.default.fileExists(atPath: file.path(percentEncoded: false)))
    }
}

/// The same field in two folders, which reads draw from together.
private let folderOne = Surface(bundleIdentifier: "com.example.terminal", role: "AXTextArea", scope: "~/one")
private let folderTwo = Surface(bundleIdentifier: "com.example.terminal", role: "AXTextArea", scope: "~/two")

@Suite("Feedback on a line learned in another folder")
struct BorrowedFeedbackTests {
    @Test("Refusing a line borrowed from another folder is counted against it where it is offered.")
    func refusingABorrowedLineCounts() async throws {
        let corpus = Corpus()
        let store = try store(corpus)
        try await store.record("git status", in: folderOne, at: moment)
        #expect(try await store.candidates(for: folderTwo, matching: "git s").count == 1)
        try await store.recordRejected("git status", in: folderTwo)
        try await store.recordAccepted("git status", in: folderTwo)
        let found = try await store.candidates(for: folderTwo, matching: "git s")
        #expect(found.first?.evidence?.rejected == 1)
        #expect(found.first?.evidence?.accepted == 1)
    }

    @Test("A line refused in another folder keeps its refusals until the person types it again by hand.")
    func typingALineByHandForgivesItsRefusals() async throws {
        let corpus = Corpus()
        let store = try store(corpus)
        for _ in 0..<3 { try await store.record("git status --short", in: folderOne, at: moment) }
        for _ in 0..<3 { try await store.recordRejected("git status --short", in: folderTwo) }
        #expect(try await store.candidates(for: folderTwo, matching: "git s").first?.evidence?.rejected == 3)
        try await store.record("git status --short", in: folderOne, selfSourced: true, at: moment)
        #expect(try await store.candidates(for: folderTwo, matching: "git s").first?.evidence?.rejected == 3)
        try await store.record("git status --short", in: folderTwo, at: moment)
        #expect(try await store.candidates(for: folderTwo, matching: "git s").first?.evidence?.rejected == 0)
        #expect(try await store.candidates(for: folderOne, matching: "git s").first?.evidence?.rejected == 0)
    }

    @Test("A line known in both folders is counted once, against this folder's own entry.")
    func aLineInBothFoldersCountsOnce() async throws {
        let corpus = Corpus()
        let store = try store(corpus)
        try await store.record("git status", in: folderOne, at: moment)
        try await store.record("git status", in: folderTwo, at: moment)
        try await store.recordRejected("git status", in: folderTwo)
        #expect(try await store.candidates(for: folderTwo, matching: "git s").first?.evidence?.rejected == 1)
        let rows = try Database(path: corpus.path).rows(
            """
            SELECT surface.scope FROM entry JOIN surface ON surface.id = entry.surface_id
            WHERE entry.rejected > 0
            """, { _ in }
        ) { $0.text(0) }
        #expect(rows == ["~/two"])
    }

    @Test("A line the gates refuse in this folder is retired here, and still offered where it was learned.")
    func refusingABorrowedLineRetiresItHere() async throws {
        let corpus = Corpus()
        let store = try store(corpus)
        try await store.record("git status", in: folderOne, at: moment)
        try await store.recordRejection(of: "git status", in: folderTwo)
        #expect(try await store.candidates(for: folderTwo, matching: "git s").isEmpty)
        #expect(try await store.candidates(for: folderTwo, matching: "gti s").isEmpty)
        #expect(try await store.recent(in: folderTwo, limit: 5).isEmpty)
        #expect(try await store.candidates(for: folderOne, matching: "git s").count == 1)
    }

    @Test("Typing a retired line by hand makes it available in that folder again.")
    func typingARetiredLineByHandBringsItBack() async throws {
        let corpus = Corpus()
        let store = try store(corpus)
        try await store.record("meeting at 3", in: folderOne, at: moment)
        try await store.supersede("meeting at 3", with: "meeting at 4", in: folderOne)

        for index in 1...3 {
            try await store.record(
                "meeting at 3", in: folderOne, at: moment.addingTimeInterval(Double(index)))
        }

        let found = try await store.candidates(for: folderOne, matching: "meeting at")
        #expect(found.map(\.text) == ["meeting at 3"])
        #expect(found.first?.evidence?.count == 4)
        #expect(try await store.recent(in: folderOne, limit: 5) == ["meeting at 3"])
    }

    @Test("Accepting a retired line does not make it available again.")
    func acceptingARetiredLineDoesNotBringItBack() async throws {
        let corpus = Corpus()
        let store = try store(corpus)
        try await store.record("meeting at 3", in: folderOne, at: moment)
        try await store.supersede("meeting at 3", with: "meeting at 4", in: folderOne)
        try await store.record("meeting at 3", in: folderOne, selfSourced: true, at: moment)

        #expect(try await store.candidates(for: folderOne, matching: "meeting at").isEmpty)
        #expect(try await store.recent(in: folderOne, limit: 5).isEmpty)
    }

    @Test("A line known in both folders and retired in one is not brought back by the other.")
    func retiringALineInBothFolders() async throws {
        let corpus = Corpus()
        let store = try store(corpus)
        try await store.record("git status", in: folderOne, at: moment)
        try await store.record("git status", in: folderTwo, at: moment)
        try await store.recordRejection(of: "git status", in: folderTwo)
        #expect(try await store.candidates(for: folderTwo, matching: "git s").isEmpty)
        #expect(try await store.candidates(for: folderOne, matching: "git s").count == 1)
    }

    @Test("Retiring a line never learned in any folder writes nothing.")
    func retiringAnUnknownLineWritesNothing() async throws {
        let corpus = Corpus()
        let store = try store(corpus)
        try await store.record("git status", in: folderOne, at: moment)
        try await store.supersede("git stash", with: "git status", in: folderTwo)
        #expect(try await store.entryCount() == 1)
    }
}

@Suite("Recovering from a corrupt corpus")
struct CorruptCorpusTests {
    @Test("a file that is not a database is set aside, not deleted, and a fresh corpus opens")
    func corruptFileIsSetAside() async throws {
        let folder = URL(filePath: NSTemporaryDirectory())
            .appending(path: "uttrflow-corrupt-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let file = folder.appending(path: "predict.v1.sqlite")
        let bytes = Data(repeating: 0xA5, count: 4_096)
        try bytes.write(to: file)

        let opened = try PredictStore(path: file.path(percentEncoded: false))
        _ = try await opened.candidates(for: terminal, matching: "")

        let names = try FileManager.default.contentsOfDirectory(atPath: folder.path(percentEncoded: false))
        let aside = try #require(names.first { $0.hasPrefix("predict.v1.sqlite.unreadable-") })
        #expect(try Data(contentsOf: folder.appending(path: aside)) == bytes)
        #expect(FileManager.default.fileExists(atPath: file.path(percentEncoded: false)))
    }
}
