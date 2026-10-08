import CryptoKit
import Foundation
import UttrflowAI
import UttrflowCore
import UttrflowDictionary
import UttrflowHistory
import Testing

/// Opens every store file kept from a released build with this build's code. See `Tests/Fixtures/stores/README.md`.
@Suite("Released store fixtures")
struct ReleasedStoreFixtureTests {
    private struct Keys: StoreKeyProviding {
        let value = SymmetricKey(size: .bits256)
        func key(createIfMissing: Bool) throws -> SymmetricKey { value }
    }

    /// One store's reading of a fixture: how many records it kept and one value from them.
    private struct Opened: Equatable {
        let count: Int
        let sample: String
    }

    private static let releases = ["v26.0926.0"]

    /// Entries with no fixture yet; a new entry fails `everyEntryIsCoveredOrListed` until it is placed.
    private static let uncovered: Set<LocalStoreEntry> = [
        .clipboard, .clipboardPreferences, .clipboardImages, .savedClips, .notSecretClips, .predict,
        .predictConsent,
        .recordings, .speechModels, .encryptionKey, .legacyMigrationMarker, .instanceLock,
        .speechModelLoads, .networkActivity, .evidenceLedger,
    ]

    private static let covered: [LocalStoreEntry: Opened] = [
        .dictationHistory: Opened(count: 2, sample: "Book the meeting room for Thursday afternoon. 1.5"),
        .personalDictionary: Opened(count: 2, sample: "Zentrova zen trova 4 1"),
        .snippets: Opened(count: 2, sample: "sign off Thanks, and talk soon. 3"),
    ]

    private static var fixtures: URL {
        URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
            .appending(path: "Fixtures/stores", directoryHint: .isDirectory)
    }

    @Test("every store entry has a fixture or is listed as not yet covered")
    func everyEntryIsCoveredOrListed() {
        let placed = Set(Self.covered.keys).union(Self.uncovered)
        #expect(placed == Set(LocalStoreEntry.allCases))
        #expect(Set(Self.covered.keys).isDisjoint(with: Self.uncovered))
    }

    @Test(
        "this build opens each released store file with its records intact",
        arguments: Self.releases, [LocalStoreEntry.dictationHistory, .personalDictionary, .snippets])
    func opensReleasedFile(release: String, entry: LocalStoreEntry) async throws {
        let payload = try Data(contentsOf: Self.fixtures.appending(path: "\(release)/\(entry.name)"))
        let sandbox = Sandbox()
        let store = EncryptedStore(keys: Keys())
        let file = sandbox.root.appending(path: entry.name)
        try store.seal(payload, for: entry.name).write(to: file)

        let opened = try await Self.open(entry, file: file, store: store)

        #expect(opened == Self.covered[entry])
        let siblings = try FileManager.default.contentsOfDirectory(
            atPath: sandbox.root.path(percentEncoded: false))
        #expect(siblings == [entry.name], "an unreadable file is set aside beside the store")
    }

    private static func open(
        _ entry: LocalStoreEntry, file: URL, store: EncryptedStore
    ) async throws -> Opened {
        switch entry {
        case .dictationHistory:
            let records = await DictationHistoryStore(file: file, encryptedStore: store)
                .records(
                    keeping: Retention(days: 36_500, now: Date(timeIntervalSinceReferenceDate: 811_800_000)))
            let first = try #require(records.min { $0.when < $1.when })
            let seconds = first.spokenFor.map {
                Double($0.components.seconds) + Double($0.components.attoseconds) / 1e18
            }
            return Opened(count: records.count, sample: "\(first.text) \(seconds ?? 0)")
        case .personalDictionary:
            let entries = await PersonalDictionaryStore(file: file, encryptedStore: store).allEntries()
            let first = try #require(entries.first)
            return Opened(
                count: entries.count,
                sample: "\(first.word) \(first.pronunciation ?? "") \(first.timesUsed) \(first.timesReverted)"
            )
        case .snippets:
            let snippets = await SnippetStore(file: file, encryptedStore: store).snippets()
            let first = try #require(snippets.first)
            return Opened(
                count: snippets.count, sample: "\(first.trigger) \(first.expansion) \(first.timesUsed)")
        default:
            Issue.record("no reader for \(entry)")
            return Opened(count: 0, sample: "")
        }
    }
}
