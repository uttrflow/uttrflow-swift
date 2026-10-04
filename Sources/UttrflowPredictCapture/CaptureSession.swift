// One field at a time, watched for finished values and written through every refusal.
public import UttrflowPredict

public import struct Foundation.Date

/// What came of one event, which is nothing at all almost every time.
public enum CaptureOutcome: Sendable, Equatable {
    /// Nothing was finished, so nothing was written.
    case nothing
    /// A finished value reached the corpus.
    case recorded(String)
    /// A finished value was refused before it could be written.
    case refused(CaptureRefusal)
}

/// Watches one field at a time and writes what the user finishes in it.
public actor CaptureSession {
    /// Where a finished value goes once every refusal has let it through.
    private let sink: any CaptureSink
    /// The answers about each application, kept so one given today is not asked for tomorrow.
    private let preferencesFile: CapturePreferencesFile
    /// Which endings of a field's life finish its value.
    private let policy: CommitPolicy
    /// The answers as they stand, read once at launch and written back as they change.
    private var preferences: CapturePreferences
    /// The field the events are believed to be about, until a different one is read.
    private var focused: FieldReading?
    /// Where a value is watched for being finished.
    private var detector = CommitDetector()
    /// The last value written in each surface, which is what the next one is recorded as following.
    private var lastRecorded: [Surface: String] = [:]
    /// Finished values whose write failed, oldest first, retried before the next event.
    private var unwrittenCommits: [UnwrittenCommit] = []
    /// The most finished values held for a retry, beyond which the oldest is dropped.
    static let unwrittenCommitLimit = 32
    /// Acceptances whose write failed, oldest first, retried before the next event or acceptance.
    private var unwrittenAcceptances: [UnwrittenAcceptance] = []
    /// The most acceptances held for a retry, beyond which the oldest is dropped.
    static let unwrittenAcceptanceLimit = 32
    /// The id the next held value or acceptance is given, so a retry can tell it is still the one at the head.
    private var nextHeldID: UInt64 = 0
    /// True while held finished values are being retried, so a re-entrant retry does not write the same one twice.
    private var isRetryingCommits = false
    /// True while held acceptances are being retried, so a re-entrant retry does not write the same one twice.
    private var isRetryingAcceptances = false
    /// The last acceptance written and the line it was taken over, watched for an undo until the line moves on or `undoWindow` passes.
    private var lastAcceptance: (text: String, over: String, surface: Surface, moment: Date)?
    /// How long after an acceptance a line cut back inside the accepted text reads as the person undoing it.
    static let undoWindow = SuggestionSession.undoWindow

    /// A session writing to this sink, remembering its answers in this file.
    public init(
        sink: any CaptureSink, preferencesFile: CapturePreferencesFile, policy: CommitPolicy = .everyEnding
    ) {
        self.sink = sink
        self.preferencesFile = preferencesFile
        self.policy = policy
        preferences = preferencesFile.load()
    }

    /// Takes one event in one field and answers with what it came to.
    public func handle(_ event: CaptureEvent, in reading: FieldReading) async throws -> CaptureOutcome {
        await retryUnwrittenCommits()
        await retryUnwrittenAcceptances()
        // The application leaving is the one still focused here, whatever field the caller last read in it.
        if case .applicationDeactivated = event, !isFocused(reading) {
            defer { focused = nil }
            return try await flush(with: event)
        }
        // A failed write here is already held for a retry, so it does not cost the new field its event.
        if !isFocused(reading) { _ = try? await flush(with: .focusLeft(at: event.moment)) }
        focused = reading
        await retractIfUndone(event, in: reading)
        guard let surface = reading.surface,
            let commit = detector.receive(event, admitting: { policy.admits($0, in: reading) })
        else { return .nothing }
        return try await write(commit, from: reading, in: surface, at: event.moment)
    }

    /// Whether this reading is the focused field, judged by the surface it names so a window's title marks do not end it.
    private func isFocused(_ reading: FieldReading) -> Bool {
        guard let focused else { return false }
        guard let surface = reading.surface, let known = focused.surface else { return focused == reading }
        return surface == known && focused.isSecure == reading.isSecure
    }

    /// Records a completion the person took over the line `typed`, through the same refusals as anything they typed.
    public func accepted(
        _ text: String, over typed: String = "", in reading: FieldReading, at moment: Date
    ) async throws -> CaptureOutcome {
        guard let surface = reading.surface else { return .nothing }
        if let refusal = CaptureGate.refusal(toRecord: text, from: reading, given: preferences) {
            return .refused(refusal)
        }
        await retryUnwrittenAcceptances()
        if isFocused(reading) { detector.accepted(text) }
        // Claimed before the await, so a write admitted while this one is suspended follows it.
        let acceptance = UnwrittenAcceptance(
            text: text, surface: surface, previous: claimLast(text, in: surface), moment: moment)
        do {
            try await write(acceptance)
        } catch let failure as AcceptanceWriteFailure {
            hold(failure.remaining)
            throw failure.underlying
        }
        lastAcceptance = (text, typed.trimmingCharacters(in: .whitespacesAndNewlines), surface, moment)
        return .recorded(text)
    }

    /// Takes back the last acceptance when the line, read soon after in its field, is cut back inside the accepted text or to the line it was taken over.
    private func retractIfUndone(_ event: CaptureEvent, in reading: FieldReading) async {
        guard let last = lastAcceptance else { return }
        guard reading.surface == last.surface, event.moment.timeIntervalSince(last.moment) <= Self.undoWindow
        else {
            lastAcceptance = nil
            return
        }
        switch event {
        case .keystroke(let line, _):
            let accepted = Array(last.text.unicodeScalars)
            let now = Array(line.trimmingCharacters(in: .whitespacesAndNewlines).unicodeScalars)
            // Typing on past the acceptance keeps it; a line that has moved on to other text has not undone it.
            if now.count > accepted.count, Array(now.prefix(accepted.count)) == accepted {
                lastAcceptance = nil
            }
            let cutBack = now.count < accepted.count && Array(accepted.prefix(now.count)) == now
            // A fuzzy acceptance rewrote the typed line, so an undo lands on the typo, which is no prefix of the line taken.
            let over = Array(last.over.unicodeScalars)
            let restored = now.count <= over.count && Array(over.prefix(now.count)) == now && now != accepted
            guard cutBack || restored else { return }
            lastAcceptance = nil
            try? await sink.retractAcceptance(last.text, in: last.surface)
        case .returnPressed, .focusLeft, .applicationDeactivated:
            lastAcceptance = nil
        case .tick, .typed, .inserted:
            return
        }
    }

    /// How many acceptances are waiting for their write to be retried.
    public func unwrittenAcceptanceCount() -> Int { unwrittenAcceptances.count }

    /// Writes an acceptance's line and then its count, skipping the line when it already landed.
    private func write(_ acceptance: UnwrittenAcceptance) async throws {
        var remaining = acceptance
        do {
            // Recorded before the acceptance is counted, so a new line's first acceptance is not lost.
            if !remaining.lineRecorded {
                try await sink.record(
                    remaining.text, in: remaining.surface, after: remaining.previous, selfSourced: true,
                    at: remaining.moment)
                remaining.lineRecorded = true
            }
            try await sink.recordAccepted(remaining.text, in: remaining.surface)
        } catch {
            throw AcceptanceWriteFailure(remaining: remaining, underlying: error)
        }
    }

    /// Keeps a failed acceptance for a retry, dropping the oldest past the limit.
    private func hold(_ acceptance: UnwrittenAcceptance) {
        var acceptance = acceptance
        acceptance.heldID = claimHeldID()
        unwrittenAcceptances.append(acceptance)
        if unwrittenAcceptances.count > Self.unwrittenAcceptanceLimit { unwrittenAcceptances.removeFirst() }
    }

    /// Retries held acceptances in order, stopping at the first that fails again.
    private func retryUnwrittenAcceptances() async {
        guard !isRetryingAcceptances else { return }
        isRetryingAcceptances = true
        defer { isRetryingAcceptances = false }
        while let next = unwrittenAcceptances.first {
            do {
                try await write(next)
                // A forget or the limit may have dropped it during the write, so only the same head is removed.
                if unwrittenAcceptances.first?.heldID == next.heldID { unwrittenAcceptances.removeFirst() }
            } catch let failure as AcceptanceWriteFailure {
                if unwrittenAcceptances.first?.heldID == next.heldID {
                    unwrittenAcceptances[0] = failure.remaining
                }
                return
            } catch {
                return
            }
        }
    }

    /// Hands out the next held id, so no two held entries share one.
    private func claimHeldID() -> UInt64 {
        defer { nextHeldID &+= 1 }
        return nextHeldID
    }

    /// What the user has decided about capture so far.
    public func decisions() -> CapturePreferences { preferences }

    /// Records the user's answer about one application and keeps it for the next launch.
    public func record(_ state: ConsentState, for bundleIdentifier: String) throws {
        preferences.record(state, for: bundleIdentifier)
        try preferencesFile.save(preferences)
    }

    /// Forgets every answer, in memory and on disk, so a reset is not undone by the next one recorded.
    public func forgetEveryAnswer() throws {
        preferences = CapturePreferences()
        try preferencesFile.remove()
    }

    /// Forgets what this session holds about one application, so its next line does not follow a forgotten one.
    public func forgetLearned(from bundleIdentifier: String) {
        let application = Surface(bundleIdentifier: bundleIdentifier, role: "").bundleIdentifier
        lastRecorded = lastRecorded.filter { $0.key.bundleIdentifier != application }
        unwrittenCommits.removeAll { $0.surface.bundleIdentifier == application }
        unwrittenAcceptances.removeAll { $0.surface.bundleIdentifier == application }
        if lastAcceptance?.surface.bundleIdentifier == application { lastAcceptance = nil }
        if focused?.surface?.bundleIdentifier == application { detector.reset() }
    }

    /// Forgets every line and answer this session holds, in memory and on disk.
    public func forgetEverythingLearned() throws {
        lastRecorded = [:]
        unwrittenCommits = []
        unwrittenAcceptances = []
        lastAcceptance = nil
        detector.reset()
        try forgetEveryAnswer()
    }

    /// Seeds a terminal from the shell's history, once, and only because the user asked for it.
    public func importShellHistory(
        forHomeDirectory home: String, into surface: Surface, at moment: Date
    ) async throws -> Int {
        guard !preferences.hasImportedShellHistory,
            preferences.decision(for: surface.bundleIdentifier) == .proceed
        else { return 0 }
        preferences.hasImportedShellHistory = true
        try preferencesFile.save(preferences)
        for path in ShellHistory.paths(inHomeDirectory: home) {
            let commands = ShellHistory.read(atPath: path)
            guard !commands.isEmpty else { continue }
            var stored = 0
            for (index, command) in commands.enumerated()
            where !DestructiveCommand.matches(command, failClosedOnUnresolved: true) {
                // One second per line, oldest first, so eviction keeps the newest.
                let age = Double(commands.count - 1 - index)
                try await sink.record(
                    command, in: surface, after: nil, selfSourced: false,
                    at: moment.addingTimeInterval(-age))
                stored += 1
            }
            return stored
        }
        return 0
    }

    /// Ends the focused field with this event, so a half-finished value is not lost.
    private func flush(with ending: CaptureEvent) async throws -> CaptureOutcome {
        defer { detector.reset() }
        guard let leaving = focused, let surface = leaving.surface,
            let commit = detector.receive(ending, admitting: { policy.admits($0, in: leaving) })
        else { return .nothing }
        return try await write(commit, from: leaving, in: surface, at: ending.moment)
    }

    /// Puts a finished value the policy admitted through every refusal and then into the corpus.
    private func write(
        _ commit: Commit, from reading: FieldReading, in surface: Surface, at moment: Date
    ) async throws -> CaptureOutcome {
        if let refusal = CaptureGate.refusal(
            toRecord: commit.text, from: reading, given: preferences)
        {
            // Forgotten, so a refused value is never later handed to the sink as the one replaced.
            detector.forgetLastIdleCommit()
            return .refused(refusal)
        }
        let superseded = commit.supersedes.flatMap {
            CaptureGate.refusal(toRecord: $0, from: reading, given: preferences) == nil ? $0 : nil
        }
        let unwritten = UnwrittenCommit(
            text: commit.text, surface: surface, superseded: superseded,
            previous: claimLast(commit.text, in: surface), moment: moment)
        do {
            try await write(unwritten)
        } catch let failure as CommitWriteFailure {
            if commit.reason == .wentIdle {
                // The detector still holds an idle value, so the next tick re-emits it.
                detector.forgetLastIdleCommit()
                releaseLast(commit.text, in: surface, restoring: unwritten.previous)
            } else {
                // A field's ending has already reset the detector, so only the held copy can bring it back.
                hold(failure.remaining)
            }
            throw failure.underlying
        }
        return .recorded(commit.text)
    }

    /// Makes this value the surface's last line and answers with the one it follows.
    private func claimLast(_ text: String, in surface: Surface) -> String? {
        defer { lastRecorded[surface] = text }
        return lastRecorded[surface]
    }

    /// Gives back a failed claim, unless a later write has already taken the surface's last line.
    private func releaseLast(_ text: String, in surface: Surface, restoring previous: String?) {
        guard lastRecorded[surface] == text else { return }
        lastRecorded[surface] = previous
    }

    /// How many finished values are waiting for their write to be retried.
    public func unwrittenCommitCount() -> Int { unwrittenCommits.count }

    /// Retires the superseded draft and then records the value, skipping a supersede that already landed.
    private func write(_ unwritten: UnwrittenCommit) async throws {
        var remaining = unwritten
        do {
            if let superseded = remaining.superseded {
                try await sink.supersede(superseded, with: remaining.text, in: remaining.surface)
                remaining.superseded = nil
            }
            try await sink.record(
                remaining.text, in: remaining.surface, after: remaining.previous, selfSourced: false,
                at: remaining.moment)
        } catch {
            throw CommitWriteFailure(remaining: remaining, underlying: error)
        }
    }

    /// Keeps a failed finished value for a retry, dropping the oldest past the limit.
    private func hold(_ unwritten: UnwrittenCommit) {
        var unwritten = unwritten
        unwritten.heldID = claimHeldID()
        unwrittenCommits.append(unwritten)
        if unwrittenCommits.count > Self.unwrittenCommitLimit { unwrittenCommits.removeFirst() }
    }

    /// Retries held finished values in order, stopping at the first that fails again.
    private func retryUnwrittenCommits() async {
        guard !isRetryingCommits else { return }
        isRetryingCommits = true
        defer { isRetryingCommits = false }
        while let next = unwrittenCommits.first {
            do {
                try await write(next)
                // A forget or the limit may have dropped it during the write, so only the same head is removed.
                if unwrittenCommits.first?.heldID == next.heldID { unwrittenCommits.removeFirst() }
            } catch let failure as CommitWriteFailure {
                if unwrittenCommits.first?.heldID == next.heldID { unwrittenCommits[0] = failure.remaining }
                return
            } catch {
                return
            }
        }
    }
}

/// A finished value the corpus has not fully taken yet, and how far its write got.
struct UnwrittenCommit: Sendable {
    /// The value the field ended with.
    let text: String
    /// Where it was finished.
    let surface: Surface
    /// The draft it retires, until that supersede has landed.
    var superseded: String?
    /// The line it followed when it was finished.
    let previous: String?
    /// When it was finished.
    let moment: Date
    /// Which held entry this is, given when it is held and kept through every retry.
    var heldID: UInt64 = 0
}

/// A failed finished-value write, carrying what is left of it to retry.
private struct CommitWriteFailure: Error {
    /// The value as far as its write got.
    let remaining: UnwrittenCommit
    /// What the sink threw.
    let underlying: any Error
}

/// An acceptance the corpus has not fully taken yet, and how far its write got.
struct UnwrittenAcceptance: Sendable {
    /// The completion the person took.
    let text: String
    /// Where it was taken.
    let surface: Surface
    /// The line it followed when it was taken.
    let previous: String?
    /// When it was taken.
    let moment: Date
    /// True once the line itself is in the corpus, so a retry only counts the acceptance.
    var lineRecorded = false
    /// Which held entry this is, given when it is held and kept through every retry.
    var heldID: UInt64 = 0
}

/// A failed acceptance write, carrying what is left of it to retry.
private struct AcceptanceWriteFailure: Error {
    /// The acceptance as far as it got.
    let remaining: UnwrittenAcceptance
    /// What the sink threw.
    let underlying: any Error
}
