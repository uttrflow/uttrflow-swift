// The revision of the recogniser, prompt and lexicon that produced a dictionary's counts. See `Docs/store-compatibility.md`.

public import UttrflowCore
import struct Foundation.UUID

/// Which version of the system heard the dictations a count was taken from.
public struct LearningRevision: Sendable, Equatable, Codable {
    /// The speech model's revision.
    public let recogniser: String
    /// The prompt's fingerprint, as `PromptBuilder.version` names it.
    public let prompt: String
    /// The shipped word list's version.
    public let lexicon: Int

    public init(recogniser: String, prompt: String, lexicon: Int) {
        self.recogniser = recogniser
        self.prompt = prompt
        self.lexicon = lexicon
    }

    /// One string naming all three, so two revisions are the same exactly when every part is.
    var key: String { "\(recogniser.utf8.count):\(recogniser)|\(prompt.utf8.count):\(prompt)|\(lexicon)" }
}

/// What opening the dictionary under a revision did to its counts.
public enum LearningRevisionChange: Sendable, Equatable {
    /// The counts were already produced under this revision, or none were recorded before.
    case unchanged
    /// The counts were observations of another revision and were set aside; `entries` words start counting again.
    case restarted(entries: Int)
    /// The counts this revision produced earlier came back, and nothing was lost by the visit elsewhere.
    case restored(entries: Int)
}

extension PersonalDictionaryStore {
    /// The most revisions whose counts are kept for a return to them.
    static let maximumKeptRevisions = 3

    /// One entry's counts, held for the revision that produced them.
    struct KeptCounts: Codable, Sendable, Equatable {
        let id: UUID
        let used: Int
        let reverted: Int
    }

    /// The revision the live counts came from, and the counts of earlier ones, oldest first.
    struct RevisionRecord: Codable, Sendable, Equatable {
        struct Kept: Codable, Sendable, Equatable {
            let key: String
            let counts: [KeptCounts]
        }
        let current: String
        let kept: [Kept]
    }

    /// Opens the dictionary under `revision`: choices stay, and counts follow the revision that produced them.
    @discardableResult
    public func settle(
        under revision: LearningRevision
    ) throws(DictionaryStoreError) -> LearningRevisionChange {
        let key = revision.key
        let record: RevisionRecord
        switch readRecord(RevisionRecord.self, from: revisionRecord) {
        case .missing:
            guard !LocalStore.hasSetAside(revisionRecord) else { throw .couldNotReadSeedRecord }
            try writeRevision(RevisionRecord(current: key, kept: []))
            return .unchanged
        case .unsupportedVersion, .unreadable: throw .couldNotReadSeedRecord
        case .read(let read), .recovered(let read, _, _, _, _): record = read
        }
        guard record.current != key else { return .unchanged }
        let entries = load()
        let returning = record.kept.first { $0.key == key }
        let leaving = RevisionRecord.Kept(
            key: record.current,
            counts: entries.map { .init(id: $0.id, used: $0.timesUsed, reverted: $0.timesReverted) })
        let kept = record.kept.filter { $0.key != record.current && $0.key != key } + [leaving]
        // The record goes first, so a failed list write leaves the old counts named and kept rather than lost.
        try writeRevision(RevisionRecord(current: key, kept: Array(kept.suffix(Self.maximumKeptRevisions))))
        let earlier = Dictionary(
            (returning?.counts ?? []).map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        let settled = entries.map { entry in
            var entry = entry
            entry.timesUsed = DictionaryEntry.clamped(earlier[entry.id]?.used ?? 0)
            entry.timesReverted = DictionaryEntry.clamped(earlier[entry.id]?.reverted ?? 0)
            return entry
        }
        if settled != entries { try persist(settled) }
        return returning == nil ? .restarted(entries: entries.count) : .restored(entries: entries.count)
    }

    private func writeRevision(_ record: RevisionRecord) throws(DictionaryStoreError) {
        do { try writeRecord(record, to: revisionRecord) } catch { throw .couldNotWrite }
    }
}
