/// What the clean-up steps did to one dictation, read off the draft's own record. See `Docs/cleanup.md`.
public struct CleaningRecord: Sendable, Equatable {
    /// A word as it reads now, and what it read before.
    public struct Rewrite: Sendable, Equatable {
        public let from: String
        public let to: String

        public init(from: String, to: String) {
            self.from = from
            self.to = to
        }
    }

    /// What one step changed, in the order the words were said; the lists are capped and the counts are exact.
    public struct Change: Sendable, Equatable, Identifiable {
        public let step: PassID
        public let removed: [String]
        public let replaced: [Rewrite]
        public let inserted: [String]
        /// How many words the step removed, which the capped `removed` list may undercount.
        public let removedCount: Int
        /// How many words the step rewrote, which the capped `replaced` list may undercount.
        public let replacedCount: Int
        /// How many words the step added, which the capped `inserted` list may undercount.
        public let insertedCount: Int

        public var id: PassID { step }

        /// A count left out, or smaller than its list, is taken from the list.
        public init(
            step: PassID, removed: [String] = [], replaced: [Rewrite] = [],
            inserted: [String] = [], removedCount: Int = 0, replacedCount: Int = 0,
            insertedCount: Int = 0
        ) {
            self.step = step
            self.removed = removed
            self.replaced = replaced
            self.inserted = inserted
            self.removedCount = max(removedCount, removed.count)
            self.replacedCount = max(replacedCount, replaced.count)
            self.insertedCount = max(insertedCount, inserted.count)
        }

        public var isEmpty: Bool { removedCount == 0 && replacedCount == 0 && insertedCount == 0 }
    }

    /// An engine's answer that was thrown away before this one, and the reason it was refused.
    public struct Refusal: Sendable, Equatable {
        public let engine: String
        public let reason: String

        public init(engine: String, reason: String) {
            self.engine = engine
            self.reason = reason
        }
    }

    /// One entry per step that changed something, ordered by the first word each touched.
    public let changes: [Change]
    /// The steps that were not in the pipeline that ran, in the order they would have run.
    public let switchedOff: [PassID]
    /// Answers refused before the one that was kept, which is why a dictation can come out plainer than the last.
    public let refusals: [Refusal]

    public init(changes: [Change], switchedOff: [PassID] = [], refusals: [Refusal] = []) {
        self.changes = changes
        self.switchedOff = switchedOff
        self.refusals = refusals
    }

    /// The same record, saying which answers were refused before the one it describes.
    public func refused(_ refusals: [Refusal]) -> CleaningRecord {
        CleaningRecord(changes: changes, switchedOff: switchedOff, refusals: refusals)
    }

    /// At most this many words are listed per step; the counts are exact either way.
    public static let wordLimit = 12

    /// Reads what every step did off the finished draft, `ran` being the pipeline's own order.
    public init(draft: Draft, ran: [PassID]) {
        self.init(
            changes: Self.changes(in: draft),
            switchedOff: CleaningSteps.offered.map(\.id).filter { !ran.contains($0) })
    }

    /// Whether anything at all is worth showing.
    public var isEmpty: Bool { changes.isEmpty && switchedOff.isEmpty && refusals.isEmpty }

    /// One record for a dictation done in pieces, keeping each step's words in the order they were said.
    public static func merging(_ records: [CleaningRecord]) -> CleaningRecord {
        var order: [PassID] = []
        var merged: [PassID: Change] = [:]
        for change in records.flatMap(\.changes) {
            if let existing = merged[change.step] {
                merged[change.step] = Change(
                    step: change.step,
                    removed: trimmed(existing.removed + change.removed),
                    replaced: trimmed(existing.replaced + change.replaced),
                    inserted: trimmed(existing.inserted + change.inserted),
                    removedCount: existing.removedCount + change.removedCount,
                    replacedCount: existing.replacedCount + change.replacedCount,
                    insertedCount: existing.insertedCount + change.insertedCount)
            } else {
                order.append(change.step)
                merged[change.step] = change
            }
        }
        let off = Set(records.flatMap(\.switchedOff))
        // Kept whole: a piece whose answer was refused is why the dictation reads unevenly.
        var refusals: [Refusal] = []
        for refusal in records.flatMap(\.refusals) where !refusals.contains(refusal) {
            refusals.append(refusal)
        }
        return CleaningRecord(
            changes: order.compactMap { merged[$0] },
            switchedOff: CleaningSteps.offered.map(\.id).filter(off.contains),
            refusals: refusals)
    }

    /// Every word a step touched, grouped by the step and ordered by the first word it reached.
    private static func changes(in draft: Draft) -> [Change] {
        var order: [PassID] = []
        var removed: [PassID: [String]] = [:]
        var replaced: [PassID: [Rewrite]] = [:]
        var inserted: [PassID: [String]] = [:]

        // Every edit, not the last state: a word two passes touched is owed to both of them.
        for word in draft.words {
            for edit in word.edits {
                note(edit.by, in: &order)
                switch edit.kind {
                case .removed:
                    removed[edit.by, default: []].append(word.heard.isEmpty ? edit.from : word.heard)
                case .replaced:
                    replaced[edit.by, default: []].append(Rewrite(from: edit.from, to: edit.to))
                case .inserted:
                    inserted[edit.by, default: []].append(edit.to)
                }
            }
        }

        return order.map { pass in
            Change(
                step: pass, removed: trimmed(removed[pass] ?? []),
                replaced: trimmed(replaced[pass] ?? []), inserted: trimmed(inserted[pass] ?? []),
                removedCount: removed[pass]?.count ?? 0, replacedCount: replaced[pass]?.count ?? 0,
                insertedCount: inserted[pass]?.count ?? 0)
        }
    }

    private static func note(_ pass: PassID, in order: inout [PassID]) {
        if !order.contains(pass) { order.append(pass) }
    }

    private static func trimmed<Element>(_ values: [Element]) -> [Element] {
        Array(values.prefix(wordLimit))
    }
}

/// Keeps what the clean-up steps did, for the one page that reports it; nothing here reaches the disk.
public protocol CleaningRecording: Sendable {
    func record(_ record: CleaningRecord) async
}

/// A recorder that discards everything, for callers with no page to draw.
public struct NoOpCleaningRecorder: CleaningRecording {
    public init() {}
    public func record(_ record: CleaningRecord) async {}
}
