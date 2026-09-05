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

    /// What one step changed, in the order the words were said.
    public struct Change: Sendable, Equatable, Identifiable {
        public let step: PassID
        public let removed: [String]
        public let replaced: [Rewrite]
        public let inserted: [String]

        public var id: PassID { step }

        public init(
            step: PassID, removed: [String] = [], replaced: [Rewrite] = [],
            inserted: [String] = []
        ) {
            self.step = step
            self.removed = removed
            self.replaced = replaced
            self.inserted = inserted
        }

        public var isEmpty: Bool { removed.isEmpty && replaced.isEmpty && inserted.isEmpty }
    }

    /// One entry per step that changed something, ordered by the first word each touched.
    public let changes: [Change]
    /// The steps that were not in the pipeline that ran, in the order they would have run.
    public let switchedOff: [PassID]

    public init(changes: [Change], switchedOff: [PassID] = []) {
        self.changes = changes
        self.switchedOff = switchedOff
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
    public var isEmpty: Bool { changes.isEmpty && switchedOff.isEmpty }

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
                    inserted: trimmed(existing.inserted + change.inserted))
            } else {
                order.append(change.step)
                merged[change.step] = change
            }
        }
        let off = Set(records.flatMap(\.switchedOff))
        return CleaningRecord(
            changes: order.compactMap { merged[$0] },
            switchedOff: CleaningSteps.offered.map(\.id).filter(off.contains))
    }

    /// Every word a step touched, grouped by the step and ordered by the first word it reached.
    private static func changes(in draft: Draft) -> [Change] {
        var order: [PassID] = []
        var removed: [PassID: [String]] = [:]
        var replaced: [PassID: [Rewrite]] = [:]
        var inserted: [PassID: [String]] = [:]

        for word in draft.words {
            switch word.state {
            case .kept:
                continue
            case .removed(let pass):
                note(pass, in: &order)
                removed[pass, default: []].append(word.heard.isEmpty ? word.text : word.heard)
            case .replaced(let pass, let from):
                note(pass, in: &order)
                replaced[pass, default: []].append(Rewrite(from: from, to: word.text))
            case .inserted(let pass):
                note(pass, in: &order)
                inserted[pass, default: []].append(word.text)
            }
        }

        return order.map { pass in
            Change(
                step: pass, removed: trimmed(removed[pass] ?? []),
                replaced: trimmed(replaced[pass] ?? []), inserted: trimmed(inserted[pass] ?? []))
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
