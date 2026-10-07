// What happens in a field, why a value counts as finished, and the machine that decides.
public import Foundation

/// One thing that happened in a text field, carrying the moment it happened rather than reading a clock.
public enum CaptureEvent: Sendable, Equatable {
    /// The line the caret is on after a key was pressed, which is what a completion matches.
    case keystroke(String, at: Date)
    /// Characters the keyboard delivered since the last line read.
    case typed(String?, at: Date)
    /// Return was pressed, which is the user saying the value is finished.
    case returnPressed(at: Date)
    /// The focus moved off this field.
    case focusLeft(at: Date)
    /// The application went to the background with the field still focused.
    case applicationDeactivated(at: Date)
    /// Time passed, which is the only way this machine can notice a pause.
    case tick(at: Date)
    /// Text reached the line without being typed, by a paste or a dictation, so the line is no longer only this person's typing.
    case inserted(at: Date)

    /// When the event happened, which is the clock the detector runs on.
    public var moment: Date {
        switch self {
        case .keystroke(_, let moment), .typed(_, let moment), .returnPressed(let moment),
            .focusLeft(let moment),
            .applicationDeactivated(let moment), .tick(let moment), .inserted(let moment):
            moment
        }
    }

    /// Whether this event ends the field's life, and so commits whatever the line holds.
    var endsTheField: Bool {
        switch self {
        case .returnPressed, .focusLeft, .applicationDeactivated: true
        case .keystroke, .typed, .tick, .inserted: false
        }
    }

    /// The events with an insertion marked after the line they read and before anything that would commit it.
    public static func marking(_ events: [CaptureEvent], insertedAt moment: Date) -> [CaptureEvent] {
        var marked = events
        marked.insert(.inserted(at: moment), at: events.firstIndex(where: \.endsTheField) ?? events.endIndex)
        return marked
    }
}

/// Why a value counted as finished, which is what the measurements are broken down by.
public enum CommitReason: String, Sendable, Equatable, CaseIterable {
    /// The user pressed Return.
    case returnPressed
    /// The focus moved off the field.
    case focusLeft
    /// The application went to the background.
    case applicationDeactivated
    /// The line sat untouched for longer than the idle interval.
    case wentIdle
}

/// One value the user finished entering, and the idle draft of it that came before.
public struct Commit: Sendable, Equatable {
    /// The text as it stood when it was finished.
    public let text: String
    /// What an idle committed earlier in this field's life, which this value replaces whatever it has become.
    public let supersedes: String?
    /// What ended the field's life, or the idle that stood in for it.
    public let reason: CommitReason

    /// A finished value, optionally retiring the idle draft that came before it.
    public init(text: String, supersedes: String? = nil, reason: CommitReason) {
        self.text = text
        self.supersedes = supersedes
        self.reason = reason
    }
}

/// A word-level edit the person makes inside inserted text, aligned against the inserted words.
public struct EditedSpan: Sendable, Equatable {
    /// Where the edit starts, counted in words from the first inserted word.
    public let position: Int
    /// The inserted words the person replaced, empty when they only added words.
    public let old: [String]
    /// The words the person put in their place, empty when they only removed words.
    public let new: [String]

    /// An edit at this word position, replacing these inserted words with those.
    public init(position: Int, old: [String], new: [String]) {
        self.position = position
        self.old = old
        self.new = new
    }
}

/// The inserted words a line is watched for, from the line they reached until an ending or the window passes.
struct InsertedSpan: Sendable, Equatable {
    /// The whole line as the insertion left it, which the final line is aligned against.
    let line: String
    /// The inserted words, as a range of the line's words.
    let words: Range<Int>
    /// The moment of the insertion, which the edit window runs from.
    let moment: Date
    /// Whether keys the person pressed explain every change since.
    var isExplainedByKeys = true
}

/// Decides when a line holds a finished value, so nothing is ever remembered per keystroke.
public struct CommitDetector: Sendable, Equatable {
    /// How long a line sits genuinely untouched before an idle commit will consider it finished.
    public static let idleInterval: TimeInterval = 8
    /// How long after an insertion an ending may still report an edit inside it.
    public static let spanEditWindow: TimeInterval = 60
    /// The most words either side of an edit inside inserted text may hold.
    public static let spanEditWordLimit = 3

    /// The line as it last stood, trimmed, which is what any ending would commit.
    private var pending = ""
    /// When the line was last touched, which is what an idle is measured from.
    private var lastKeystroke: Date?
    /// What an idle commit remembered, kept until the field's life ends so the finished line can retire it.
    private var committed: String?
    /// What `committed` held before the most recent idle, so a failed write can put the field back where it was.
    private var committedPrior: String?
    /// The line an accepted completion already recorded, which an ending leaves alone unless it has changed since.
    private var acceptedLine: String?
    /// Whether text that was not typed reached the line in this field's life, which keeps anything it ends from being learned.
    private var holdsInsertion = false
    /// Whether a line read established a baseline for checking later keyboard input.
    private var hasObservedLine = false
    /// The untrimmed last line read, needed to retain spaces typed before a later word.
    private var observedLine = ""
    /// Characters expected to have reached the line since its last read.
    private var typedSinceRead = ""
    /// Whether a key without printable characters may have edited the line.
    private var hasUnverifiableKeySinceRead = false
    /// Whether a host-app edit made the line differ from the delivered keyboard input.
    private var holdsMutation = false
    /// The line read before the last one, which tells an insertion's words from the words around them.
    private var lineBeforeRead = ""
    /// The inserted words being watched for an edit, if any.
    private var span: InsertedSpan?
    /// The edit the last ending found inside inserted text, held until the caller takes it.
    private var editedSpan: EditedSpan?
    /// An accepted line replaced by what the person committed, held until the caller retracts its acceptance.
    private var acceptedLineToRetract: String?

    /// A detector watching a field nothing has been typed into.
    public init() {}

    /// Whether an idle alone may learn a line, which needs more than a bare single token still being typed.
    private static func looksComplete(_ text: String) -> Bool {
        text.contains(" ")
    }

    /// Takes one event and answers with the value to record, remembering only an ending `admits` lets through.
    public mutating func receive(
        _ event: CaptureEvent, admitting admits: (CommitReason) -> Bool = { _ in true }
    ) -> Commit? {
        switch event {
        case .keystroke(let text, let moment):
            let line = text.trimmingCharacters(in: .whitespacesAndNewlines)
            if hasObservedLine, (!typedSinceRead.isEmpty || hasUnverifiableKeySinceRead) {
                let replacesAcceptedText =
                    acceptedLine != nil && !typedSinceRead.isEmpty
                    && Self.isRangeReplaced(
                        in: observedLine, by: text, typing: typedSinceRead,
                        keyed: !typedSinceRead.isEmpty || hasUnverifiableKeySinceRead)
                if text != observedLine + typedSinceRead && !replacesAcceptedText {
                    holdsMutation = true
                }
            }
            let keyed = !typedSinceRead.isEmpty || hasUnverifiableKeySinceRead
            if text != observedLine,
                !Self.isRangeReplaced(in: observedLine, by: text, typing: typedSinceRead, keyed: keyed)
            {
                span?.isExplainedByKeys = false
            }
            lineBeforeRead = observedLine
            observedLine = text
            pending = line
            hasObservedLine = true
            typedSinceRead = ""
            hasUnverifiableKeySinceRead = false
            lastKeystroke = moment
            if let acceptedLine, line != acceptedLine, line.hasPrefix(acceptedLine) {
                // Typing on past the suggestion keeps its acceptance evidence.
                self.acceptedLine = nil
            }
            // A line emptied by hand holds nothing inserted, so what is typed into it next is learned again.
            if pending.isEmpty {
                holdsInsertion = false
                holdsMutation = false
                span = nil
            }
            return nil
        case .typed(let text, _):
            if let text {
                typedSinceRead += text
            } else {
                hasUnverifiableKeySinceRead = true
            }
            return nil
        case .inserted(let moment):
            holdsInsertion = true
            lastKeystroke = moment
            span = Self.insertedSpan(from: lineBeforeRead, to: observedLine, at: moment)
            return nil
        case .returnPressed(let moment):
            return finish(.returnPressed, at: moment, admits)
        case .focusLeft(let moment):
            return finish(.focusLeft, at: moment, admits)
        case .applicationDeactivated(let moment):
            return finish(.applicationDeactivated, at: moment, admits)
        case .tick(let moment):
            if let span, moment.timeIntervalSince(span.moment) > Self.spanEditWindow { self.span = nil }
            guard let lastKeystroke,
                moment.timeIntervalSince(lastKeystroke) >= Self.idleInterval,
                // A fragment still being typed is left to Return or a focus change, not to the timer.
                Self.looksComplete(pending)
            else { return nil }
            return commit(.wentIdle, admits)
        }
    }

    /// Takes the line a completion wrote as the one now standing, so an ending does not record what it replaced.
    public mutating func accepted(_ text: String) -> String? {
        let superseded = committed == text.trimmingCharacters(in: .whitespacesAndNewlines) ? nil : committed
        pending = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if let superseded {
            committedPrior = superseded
            committed = pending
        }
        acceptedLine = pending
        observedLine = text
        lineBeforeRead = text
        hasObservedLine = true
        typedSinceRead = ""
        hasUnverifiableKeySinceRead = false
        holdsInsertion = false
        holdsMutation = false
        span = nil
        return superseded
    }

    /// Forgets the accepted baseline after the capture session determines the person undid it.
    mutating func cancelAcceptedLine() {
        acceptedLine = nil
    }

    /// Forgets the field, which is what a new field focused in the same session amounts to.
    public mutating func reset() {
        pending = ""
        lastKeystroke = nil
        committed = nil
        committedPrior = nil
        acceptedLine = nil
        holdsInsertion = false
        hasObservedLine = false
        observedLine = ""
        typedSinceRead = ""
        hasUnverifiableKeySinceRead = false
        holdsMutation = false
        lineBeforeRead = ""
        span = nil
        editedSpan = nil
        acceptedLineToRetract = nil
    }

    /// Hands over the edit the last ending found inside inserted text, once.
    public mutating func takeEditedSpan() -> EditedSpan? {
        defer { editedSpan = nil }
        return editedSpan
    }

    /// Hands over an accepted line replaced by this ending, once.
    mutating func takeAcceptedLineToRetract() -> String? {
        defer { acceptedLineToRetract = nil }
        return acceptedLineToRetract
    }

    /// Undoes the most recent idle commit, so a later tick can re-emit the value after a failed write.
    public mutating func forgetLastIdleCommit() {
        committed = committedPrior
        committedPrior = nil
    }

    /// Commits and then forgets, for the three events that end the field's life.
    private mutating func finish(
        _ reason: CommitReason, at moment: Date, _ admits: (CommitReason) -> Bool
    ) -> Commit? {
        let keyedSinceRead = !typedSinceRead.isEmpty || hasUnverifiableKeySinceRead
        if keyedSinceRead { holdsMutation = true }
        let edit =
            keyedSinceRead ? nil : span.flatMap { Self.edit(of: $0, into: observedLine, at: moment) }
        let acceptedToRetract = acceptedLine != pending ? acceptedLine : nil
        let finished = commit(reason, admits)
        reset()
        editedSpan = edit
        if finished != nil { acceptedLineToRetract = acceptedToRetract }
        return finished
    }

    /// The words an insertion added between two reads of the line, or nothing when it added none.
    private static func insertedSpan(
        from before: String, to after: String, at moment: Date
    ) -> InsertedSpan? {
        let old = words(before)
        let new = words(after)
        let (prefix, suffix) = sharedEnds(old, new)
        guard new.count - suffix > prefix else { return nil }
        return InsertedSpan(line: after, words: prefix..<(new.count - suffix), moment: moment)
    }

    /// The one bounded word edit that turned the inserted line into the final one, inside the inserted words.
    private static func edit(of span: InsertedSpan, into line: String, at moment: Date) -> EditedSpan? {
        guard span.isExplainedByKeys, moment.timeIntervalSince(span.moment) <= spanEditWindow
        else { return nil }
        let old = words(span.line)
        let new = words(line)
        let (prefix, suffix) = sharedEnds(old, new)
        let replaced = Array(old[prefix..<(old.count - suffix)])
        let replacing = Array(new[prefix..<(new.count - suffix)])
        guard !(replaced.isEmpty && replacing.isEmpty), replaced.count <= spanEditWordLimit,
            replacing.count <= spanEditWordLimit, prefix >= span.words.lowerBound,
            old.count - suffix <= span.words.upperBound
        else { return nil }
        return EditedSpan(position: prefix - span.words.lowerBound, old: replaced, new: replacing)
    }

    /// A line's words, split on whitespace.
    private static func words(_ line: String) -> [String] {
        line.split(whereSeparator: \.isWhitespace).map(String.init)
    }

    /// How many leading and trailing elements two sequences share, never overlapping either.
    private static func sharedEnds<Element: Equatable>(_ old: [Element], _ new: [Element]) -> (Int, Int) {
        let limit = min(old.count, new.count)
        var prefix = 0
        while prefix < limit, old[prefix] == new[prefix] { prefix += 1 }
        var suffix = 0
        while suffix < limit - prefix, old[old.count - 1 - suffix] == new[new.count - 1 - suffix] {
            suffix += 1
        }
        return (prefix, suffix)
    }

    /// Whether the new line is the old one with one stretch replaced by the typed characters, which keys can explain.
    static func isRangeReplaced(in old: String, by new: String, typing typed: String, keyed: Bool) -> Bool {
        guard keyed else { return false }
        let old = Array(old)
        let new = Array(new)
        let typed = Array(typed)
        let (prefix, suffix) = sharedEnds(old, new)
        guard new.count >= typed.count else { return false }
        let kept = new.count - typed.count
        for head in 0...min(prefix, kept) {
            let tail = kept - head
            guard tail <= suffix, head + tail <= old.count else { continue }
            if Array(new[head..<(head + typed.count)]) == typed { return true }
        }
        return false
    }

    /// Emits what is pending, unless it is nothing, holds text that was not typed, is exactly what was emitted last, or ended in a way not admitted.
    private mutating func commit(_ reason: CommitReason, _ admits: (CommitReason) -> Bool) -> Commit? {
        guard !pending.isEmpty, !holdsInsertion, !holdsMutation, pending != committed,
            pending != acceptedLine, admits(reason)
        else {
            return nil
        }
        // An idle draft is retired by whatever the line became, even after it was backspaced away.
        let superseded = committed
        committedPrior = superseded
        committed = pending
        return Commit(text: pending, supersedes: superseded, reason: reason)
    }
}
