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

        /// What the step did, quoting at most `limit` words of each kind and counting the rest.
        public func summary(quoting limit: Int) -> String {
            let rewrites = replaced.map { "\($0.from) → \($0.to)" }
            return [
                Self.part("removed", removed, of: removedCount, quoting: limit),
                Self.part("rewrote", rewrites, of: replacedCount, quoting: limit),
                Self.part("added", inserted, of: insertedCount, quoting: limit),
            ].compactMap(\.self).joined(separator: "; ")
        }

        private static func part(
            _ verb: String, _ words: [String], of total: Int, quoting limit: Int
        )
            -> String?
        {
            guard total > 0 else { return nil }
            let quoted = words.prefix(limit).joined(separator: ", ")
            let shown = min(words.count, limit)
            return "\(verb) \(total): \(quoted)" + (total > shown ? " and \(total - shown) more" : "")
        }
    }

    /// An engine's answer that was thrown away before this one, and the reason it was refused.
    public struct Refusal: Sendable, Equatable {
        public let engine: String
        /// What the screen shows, which may quote what was said because it stays on this Mac.
        public let reason: String
        /// What a pasted report carries, which names the kind and never the words.
        public let kind: RefusalKind

        public init(engine: String, reason: String, kind: RefusalKind) {
            self.engine = engine
            self.reason = reason
            self.kind = kind
        }
    }

    /// An engine the router skipped before choosing the one that handled this dictation.
    public struct UnavailableEngine: Sendable, Equatable {
        public let engine: String
        public let reason: TransformerUnavailableReason

        public init(engine: String, reason: TransformerUnavailableReason) {
            self.engine = engine
            self.reason = reason
        }
    }

    /// An engine that ran but could not produce an answer, with the closed class of why.
    public struct EngineFailure: Sendable, Equatable {
        public let engine: String
        public let failureClass: ModelFailureClass

        public init(engine: String, failureClass: ModelFailureClass) {
            self.engine = engine
            self.failureClass = failureClass
        }
    }

    /// A stage that gave up on this dictation and passed its words on as they came in.
    public struct SkippedStage: Sendable, Equatable {
        /// The stages that fall back to the words they were given rather than fail the dictation.
        public enum Stage: String, Sendable, Equatable, CaseIterable {
            case correction, tidy, expansion
        }

        /// Why the stage gave up: it ran past its limit, or it threw.
        public enum Reason: String, Sendable, Equatable, CaseIterable {
            case timeout, error
        }

        public let stage: Stage
        public let reason: Reason

        public init(_ stage: Stage, _ reason: Reason) {
            self.stage = stage
            self.reason = reason
        }
    }

    /// One entry per step that changed something, ordered by the first word each touched.
    public let changes: [Change]
    /// The steps that were not in the pipeline that ran, in the order they would have run.
    public let switchedOff: [PassID]
    /// Answers refused before the one that was kept, which is why a dictation can come out plainer than the last.
    public let refusals: [Refusal]
    /// Engines skipped before the recorded engine because they were unavailable.
    public let unavailableEngines: [UnavailableEngine]
    /// Engines that failed before the recorded engine answered.
    public let engineFailures: [EngineFailure]
    /// Stages whose words passed through unchanged because they timed out or threw.
    public let skippedStages: [SkippedStage]
    /// What the kept model said, word for word, before unwrapping and finishing; one per piece, held only in memory.
    public let modelAnswers: [String]

    public init(
        changes: [Change], switchedOff: [PassID] = [], refusals: [Refusal] = [],
        unavailableEngines: [UnavailableEngine] = [], engineFailures: [EngineFailure] = [],
        skippedStages: [SkippedStage] = [], modelAnswers: [String] = []
    ) {
        self.changes = changes
        self.switchedOff = switchedOff
        self.refusals = refusals
        self.unavailableEngines = unavailableEngines
        self.engineFailures = engineFailures
        self.skippedStages = skippedStages
        self.modelAnswers = modelAnswers
    }

    /// A record holding only that `stage` gave up for `reason`.
    public static func skipped(_ stage: SkippedStage.Stage, _ reason: SkippedStage.Reason) -> CleaningRecord {
        CleaningRecord(changes: [], skippedStages: [SkippedStage(stage, reason)])
    }

    /// The same record, saying which answers were refused before the one it describes.
    public func refused(_ refusals: [Refusal]) -> CleaningRecord {
        CleaningRecord(
            changes: changes, switchedOff: switchedOff, refusals: refusals,
            unavailableEngines: unavailableEngines, engineFailures: engineFailures,
            skippedStages: skippedStages, modelAnswers: modelAnswers)
    }

    /// At most this many words are listed per step; the counts are exact either way.
    public static let wordLimit = 12

    /// Reads what every step did off the finished draft, `ran` being the pipeline's own order.
    public init(draft: Draft, ran: [PassID], modelAnswers: [String] = []) {
        self.init(
            changes: Self.changes(in: draft),
            switchedOff: CleaningSteps.optOut.map(\.id).filter { !ran.contains($0) },
            modelAnswers: modelAnswers)
    }

    /// Whether anything at all is worth showing.
    public var isEmpty: Bool {
        changes.isEmpty && switchedOff.isEmpty && refusals.isEmpty && unavailableEngines.isEmpty
            && engineFailures.isEmpty && skippedStages.isEmpty
    }

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
        var unavailableEngines: [UnavailableEngine] = []
        for engine in records.flatMap(\.unavailableEngines) where !unavailableEngines.contains(engine) {
            unavailableEngines.append(engine)
        }
        var engineFailures: [EngineFailure] = []
        for failure in records.flatMap(\.engineFailures) where !engineFailures.contains(failure) {
            engineFailures.append(failure)
        }
        var skippedStages: [SkippedStage] = []
        for skip in records.flatMap(\.skippedStages) where !skippedStages.contains(skip) {
            skippedStages.append(skip)
        }
        return CleaningRecord(
            changes: order.compactMap { merged[$0] },
            switchedOff: CleaningSteps.offered.map(\.id).filter(off.contains),
            refusals: refusals, unavailableEngines: unavailableEngines, engineFailures: engineFailures,
            skippedStages: skippedStages, modelAnswers: records.flatMap(\.modelAnswers))
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
