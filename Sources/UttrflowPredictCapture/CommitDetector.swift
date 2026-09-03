public import Foundation

/// One thing that happened in a text field, carrying the moment it happened rather than reading a clock.
public enum CaptureEvent: Sendable, Equatable {
    /// The line the caret is on after a key was pressed, which is what a completion matches.
    case keystroke(String, at: Date)
    /// Return was pressed, which is the user saying the value is finished.
    case returnPressed(at: Date)
    /// The focus moved off this field.
    case focusLeft(at: Date)
    /// The application went to the background with the field still focused.
    case applicationDeactivated(at: Date)
    /// Time passed, which is the only way this machine can notice a pause.
    case tick(at: Date)

    /// When the event happened, which is the clock the detector runs on.
    public var moment: Date {
        switch self {
        case .keystroke(_, let moment), .returnPressed(let moment), .focusLeft(let moment),
            .applicationDeactivated(let moment), .tick(let moment):
            moment
        }
    }
}

/// Why a value counted as finished, which is what the measurements are broken down by.
public enum CommitReason: String, Sendable, Equatable, CaseIterable {
    case returnPressed
    case focusLeft
    case applicationDeactivated
    case wentIdle
}

/// One value the user finished entering, and the shorter one it continues.
public struct Commit: Sendable, Equatable {
    /// The text as it stood when it was finished.
    public let text: String
    /// A value committed earlier in this same run that this one extends, which it replaces.
    public let supersedes: String?
    public let reason: CommitReason

    public init(text: String, supersedes: String? = nil, reason: CommitReason) {
        self.text = text
        self.supersedes = supersedes
        self.reason = reason
    }
}

/// Decides when a line holds a finished value, so nothing is ever remembered per keystroke.
public struct CommitDetector: Sendable, Equatable {
    /// How long a line sits genuinely untouched before an idle commit will consider it finished.
    public static let idleInterval: TimeInterval = 8

    private var pending = ""
    private var lastKeystroke: Date?
    private var committed: String?

    public init() {}

    /// Whether an idle alone may learn a line, which needs more than a bare single token still being typed.
    static func looksComplete(_ text: String) -> Bool {
        text.contains(" ")
    }

    /// Takes one event and answers with the value to record, which is nothing almost every time.
    public mutating func receive(_ event: CaptureEvent) -> Commit? {
        switch event {
        case .keystroke(let text, let moment):
            pending = text.trimmingCharacters(in: .whitespacesAndNewlines)
            lastKeystroke = moment
            if let committed, !pending.hasPrefix(committed) { self.committed = nil }
            return nil
        case .returnPressed:
            return finishing(.returnPressed)
        case .focusLeft:
            return finishing(.focusLeft)
        case .applicationDeactivated:
            return finishing(.applicationDeactivated)
        case .tick(let moment):
            guard let lastKeystroke,
                moment.timeIntervalSince(lastKeystroke) >= Self.idleInterval,
                // A still-being-typed fragment is left for Return or focus change to commit, not the idle timer.
                Self.looksComplete(pending)
            else { return nil }
            return commit(.wentIdle)
        }
    }

    /// Forgets the field, which is what a new field focused in the same session amounts to.
    public mutating func reset() {
        pending = ""
        lastKeystroke = nil
        committed = nil
    }

    /// Commits and then forgets, for the three events that end the field's life.
    private mutating func finishing(_ reason: CommitReason) -> Commit? {
        defer { reset() }
        return commit(reason)
    }

    /// Emits what is pending, unless it is nothing or is exactly what was emitted last.
    private mutating func commit(_ reason: CommitReason) -> Commit? {
        guard !pending.isEmpty, pending != committed else { return nil }
        let superseded = committed.flatMap { pending.hasPrefix($0) ? $0 : nil }
        committed = pending
        return Commit(text: pending, supersedes: superseded, reason: reason)
    }
}
