private import Synchronization
/// The words of one utterance, each carrying what the recogniser heard and what has been done to it since.
public struct Draft: Sendable, Equatable {
    /// One word, its origin, and the pass that last touched it.
    public struct Word: Sendable, Equatable {
        /// What a pass did to the word; every state but `.removed` still appears in the text.
        public enum State: Sendable, Equatable {
            case kept
            case removed(by: PassID)
            case replaced(by: PassID, from: String)
            case inserted(by: PassID)
        }

        /// One pass's change to this word, so a later pass touching it does not take the credit.
        public struct Edit: Sendable, Equatable {
            /// Which of the three things the pass did.
            public enum Kind: Sendable, Equatable {
                case removed
                case replaced
                case inserted
            }

            public let by: PassID
            public let kind: Kind
            /// What the word read before this pass; empty for a word the pass put in.
            public let from: String
            /// What it read after; empty for a word the pass took out.
            public let to: String
            /// How strongly the pass's replacement beat what was heard; `nil` for a pass that weighs no evidence.
            public let evidence: OverrideEvidence?

            public init(by: PassID, kind: Kind, from: String, to: String, evidence: OverrideEvidence? = nil) {
                self.by = by
                self.kind = kind
                self.from = from
                self.to = to
                self.evidence = evidence
            }
        }

        /// What the recogniser said about how surely it heard a word; unknown is not a score of 1.
        public enum Evidence: Sendable, Equatable {
            /// No score: the recogniser gave none that spells this word, or a pass put the word in.
            case unknown
            /// The recogniser's confidence in the heard word, 0 to 1.
            case score(Double)
        }

        /// The word as it reads now, or a layout mark beginning with a newline.
        public var text: String
        /// What the recogniser said, never changed; empty for a word a pass inserted.
        public let heard: String
        /// How surely the recogniser heard the word, stated by whoever builds it.
        public let evidence: Evidence
        /// Whether an override wrote the word, so no pass or model may rewrite it whatever its score.
        public let settled: Bool
        /// The script the recogniser wrote the word in, kept after romanising so English-only lists can skip Hindi.
        public let origin: Origin
        /// Where the recogniser heard the word begin; nil when untimed or inserted.
        public let start: Duration?
        /// Where the recogniser heard the word end; nil when untimed or inserted.
        public let end: Duration?
        public var state: State
        /// Every change a pass has made to this word, oldest first.
        public private(set) var edits: [Edit]

        public init(
            text: String, heard: String, evidence: Evidence, settled: Bool = false,
            origin: Origin = .latin,
            start: Duration? = nil, end: Duration? = nil, state: State = .kept, edits: [Edit] = []
        ) {
            self.text = text
            self.heard = heard
            self.evidence = evidence
            self.settled = settled
            self.origin = origin
            self.start = start
            self.end = end
            self.state = state
            self.edits = edits
        }

        /// Notes what a pass has just done to this word, keeping the chain a later pass adds to.
        mutating func note(_ edit: Edit) {
            edits.append(edit)
        }

        /// A heard word that nothing has touched yet.
        public init(
            _ heard: String, evidence: Evidence, settled: Bool = false,
            start: Duration? = nil, end: Duration? = nil
        ) {
            self.init(
                text: heard, heard: heard, evidence: evidence, settled: settled,
                start: start, end: end, state: .kept)
        }

        /// The score a threshold reads: the recogniser's, or 1 when unknown, so an unscored word is never doubted.
        public var confidence: Double {
            if case .score(let score) = evidence { return score }
            return 1
        }

        /// Whether the word still appears in the text.
        public var isPresent: Bool {
            if case .removed = state { return false }
            return true
        }

        /// Whether the word is a line break, a paragraph break, a bullet or an item number rather than something said.
        public var isLayoutMark: Bool {
            text.hasPrefix("\n") || text == Draft.bullet || isListMark || isLabelledItemMark
        }

        /// Whether the word is a repeated label and its item number, as "Reason 2: ", wherever its line starts.
        public var isLabelledItemMark: Bool {
            let mark = text.drop(while: \.isNewline)
            guard mark.hasSuffix(Draft.labelStop) else { return false }
            let parts = mark.dropLast(Draft.labelStop.count).split(separator: " ")
            guard parts.count == 2, let label = parts.first, let digits = parts.last else { return false }
            return label.allSatisfy(\.isLetter) && digits.allSatisfy(\.isNumber)
        }

        /// Whether the word opens a list item, with a bullet or with a number; neither takes a full stop.
        public var isListMark: Bool {
            let mark = text.drop(while: \.isNewline)
            if mark.hasSuffix(Draft.bullet) { return true }
            guard mark.hasSuffix(Draft.numberStop) else { return false }
            let digits = mark.dropLast(Draft.numberStop.count)
            return !digits.isEmpty && digits.allSatisfy(\.isNumber)
        }
    }

    /// The script a word was recognised in, before romanising wrote every word in Latin letters.
    public enum Origin: Sendable, Equatable {
        case latin
        case devanagari
    }

    /// Whether the word at `index` was spoken as Hindi, so a list keyed on English spelling does not apply to it.
    public func isHindi(at index: Int) -> Bool { words[index].origin == .devanagari }

    /// Whether the words after the last paragraph or list mark are a list item, which takes no full stop.
    public var endsInListItem: Bool {
        let marks = presentIndices.map { words[$0] }.filter(\.isLayoutMark)
        return marks.last(where: { $0.text.hasPrefix("\n\n") || $0.isListMark })?.isListMark ?? false
    }

    /// The dash and space a list item begins with, after the line break that starts it.
    public static let bullet = "- "
    /// What a numbered item begins with once its digits are past: "1. ", "2. ".
    public static let numberStop = ". "
    /// What follows a repeated label's item number.
    public static let labelStop = ": "
    /// The tokens a line may open with to be read as a list item; `InsertionPoint` reads the same set.
    public static let bulletTokens: Set<String> = ["-", "\u{2022}", "*"]

    public var words: [Word] {
        didSet { presence = PresenceCache() }
    }
    /// The present positions, read once per edit rather than once per question a pass asks.
    private var presence = PresenceCache()
    /// Whether any word carries a recogniser's score rather than unknown evidence.
    public var confidencesAreReal: Bool {
        words.contains { $0.evidence != .unknown }
    }

    public init(words: [Word]) {
        self.words = words
    }

    /// Splits plain text on whitespace; no word has a score.
    public init(text: String) {
        self.init(words: Self.split(text, evidence: .unknown))
    }

    /// Splits text on spaces and tabs, keeping line breaks and list markers as layout marks.
    public init(keepingLineBreaks text: String) {
        var words: [Word] = []
        var previousLine: Int?
        let lines = text.split(omittingEmptySubsequences: false, whereSeparator: \.isNewline)
        for (number, line) in lines.enumerated() {
            var lineWords = WordTokens.words(line, .display)
            guard !lineWords.isEmpty else { continue }
            let opening = lineWords.count > 1 ? lineWords[0] : ""
            let isBullet = Self.bulletTokens.contains(opening)
            let itemNumber = Self.numberedItemNumber(opening)
            let isItem = isBullet || itemNumber != nil
            if isItem { lineWords.removeFirst() }
            let breaks = previousLine.map { String(repeating: "\n", count: number - $0) } ?? ""
            let itemMark = isBullet ? Self.bullet : itemNumber.map { "\($0)\(Self.numberStop)" } ?? ""
            let mark = breaks + itemMark
            if !mark.isEmpty { words.append(Word(mark, evidence: .unknown)) }
            words += lineWords.map { Word($0, evidence: .unknown) }
            previousLine = number
        }
        self.init(words: words)
    }

    /// Returns a line-opening number marker such as `3.` without treating ordinary numbers as list items.
    private static func numberedItemNumber(_ token: String) -> String? {
        guard token.hasSuffix("."), token.count > 1 else { return nil }
        let digits = token.dropLast()
        return digits.allSatisfy(\.isNumber) ? String(digits) : nil
    }

    /// Takes the recogniser's confidences when its timed words spell the text, spacing aside, else splits it.
    public init(transcription: Transcription) {
        let spoken = Self.split(transcription.text, evidence: .unknown)
        let timed = transcription.segments.flatMap(\.words).flatMap { word in
            Self.split(word.text, evidence: .score(word.confidence), settled: word.settled)
                .map { TimedPiece(word: $0, from: word) }
        }
        guard !timed.isEmpty, timed.map(\.word.text).joined() == spoken.map(\.text).joined() else {
            self.init(words: spoken)
            return
        }
        self.init(words: Self.confidences(of: timed, onto: spoken))
    }

    /// Romanises each Devanagari word of the transcription, remembering that it was Devanagari.
    public init(romanising transcription: Transcription) {
        let heard = Draft(transcription: transcription)
        // A stop joined to the next word is spaced off when romanised, so the token becomes two words.
        let words = heard.words.flatMap { word in
            guard Romaniser.containsDevanagari(word.text) else { return [word] }
            return WordTokens.words(Romaniser.romanised(word.text), .display).map {
                Word(
                    text: $0, heard: $0, evidence: word.evidence, settled: word.settled,
                    origin: .devanagari, start: word.start, end: word.end)
            }
        }
        self.init(words: words)
    }

    private static func split(_ text: String, evidence: Word.Evidence, settled: Bool = false) -> [Word] {
        WordTokens.words(text, .display).map { Word($0, evidence: evidence, settled: settled) }
    }

    /// A piece of one recognised word, with that word's place in the audio.
    private struct TimedPiece {
        let word: Word
        let start: Duration?
        let end: Duration?

        init(word: Word, from transcribed: TranscribedWord) {
            self.word = word
            self.start = transcribed.start
            self.end = transcribed.end
        }
    }

    /// Gives each spoken word the lowest confidence, settled state, and audio span among the timed words that spell it.
    private static func confidences(of timed: [TimedPiece], onto spoken: [Word]) -> [Word] {
        var remaining = timed[...]
        var spent = 0
        return spoken.map { word in
            var needed = word.text.count
            var confidence = 1.0
            var settled = false
            let start = spent == 0 ? remaining.first?.start : nil
            var end: Duration?
            while needed > 0, let next = remaining.first {
                confidence = min(confidence, next.word.confidence)
                settled = settled || next.word.settled
                end = next.end
                let available = next.word.text.count - spent
                guard available <= needed else {
                    spent += needed
                    needed = 0
                    continue
                }
                needed -= available
                spent = 0
                remaining.removeFirst()
            }
            return Word(word.text, evidence: .score(confidence), settled: settled, start: start, end: end)
        }
    }

    // MARK: Reading

    /// The words still in the text, joined by single spaces, with layout marks unspaced.
    public var text: String {
        var result = ""
        var afterMark = true
        for word in words where word.isPresent {
            if !afterMark, !word.isLayoutMark { result.append(" ") }
            result.append(word.text)
            afterMark = word.isLayoutMark
        }
        return result
    }

    /// What the recogniser said, before any pass ran.
    public var originalText: String {
        words.filter { !$0.heard.isEmpty }.map(\.heard).joined(separator: " ")
    }

    /// Every word a pass took out of the text.
    public var removed: [Word] { words.filter { !$0.isPresent } }

    /// Positions in `words` of the words still in the text, in order.
    public var presentIndices: [Int] {
        presence.indices {
            Self.wordsRead?.record(words.count)
            return words.indices.filter { words[$0].isPresent }
        }
    }

    /// Counts the words the draft's helpers read, so a scaling test bounds a pass by work rather than time.
    @TaskLocal package static var wordsRead: WorkTally?

    public static func == (lhs: Draft, rhs: Draft) -> Bool {
        lhs.words == rhs.words
    }

    // MARK: Editing

    /// Takes the word at `index` out of the text, remembering which pass did it.
    public mutating func remove(at index: Int, by pass: PassID) {
        guard words[index].isPresent else { return }
        words[index].note(Word.Edit(by: pass, kind: .removed, from: words[index].text, to: ""))
        words[index].state = .removed(by: pass)
    }

    /// Takes the word out, moving the marks it carries onto the words that stay. See `Docs/cleanup.md`.
    public mutating func remove(at index: Int, by pass: PassID, carryingMarks: Bool) {
        guard words[index].isPresent else { return }
        if carryingMarks { carryMarks(from: index, by: pass) }
        remove(at: index, by: pass)
    }

    /// Moves a word's closing marks back onto the previous word and its opening marks onto the next.
    private mutating func carryMarks(from index: Int, by pass: PassID) {
        let shape = WordShape(words[index].text)
        // A comma or an ellipsis is the pause the removed word stood in, so it goes with the word; every other mark is the sentence's.
        let amount = shape.core.contains(where: \.isNumber)
        let trailsOff = WordShape.trailsOff(shape.suffix)
        let closing = shape.suffix.filter {
            $0 != "," && !$0.isWhitespace && !(amount && Self.isOwnSymbol($0))
                && !(trailsOff && ($0 == "." || $0 == "\u{2026}"))
        }
        let opening = shape.prefix.filter {
            $0 != "," && !$0.isWhitespace && !(amount && Self.isOwnSymbol($0))
        }
        if !closing.isEmpty, let before = previousPresent(before: index) {
            replace(at: before, with: WordShape.marked(words[before].text, withAll: closing), by: pass)
        }
        if !opening.isEmpty, let after = nextPresent(after: index) {
            replace(at: after, with: String(opening) + words[after].text, by: pass)
        }
    }

    /// Whether a mark on a number is part of its value, like the `$` of "$40" or the `%` of "40%", and so leaves with it.
    private static func isOwnSymbol(_ mark: Character) -> Bool {
        mark.isCurrencySymbol || unitSymbols.contains(mark)
    }

    /// Signs written against a number that are part of its value rather than the sentence's punctuation.
    private static let unitSymbols: Set<Character> = ["%", "\u{2030}", "\u{2031}", "\u{00B0}", "#"]

    /// The word still in the text before `index`, or nil when a line break stands between: a mark never crosses one.
    private func previousPresent(before index: Int) -> Int? {
        guard let found = words[..<index].lastIndex(where: \.isPresent),
            !words[found].isLayoutMark
        else { return nil }
        return found
    }

    /// The word still in the text after `index`, or nil when a line break stands between.
    private func nextPresent(after index: Int) -> Int? {
        guard let found = words[(index + 1)...].firstIndex(where: \.isPresent),
            !words[found].isLayoutMark
        else { return nil }
        return found
    }

    /// Rewrites the word at `index`, remembering the pass and what it read before; a removed word stays removed.
    public mutating func replace(at index: Int, with text: String, by pass: PassID) {
        guard words[index].isPresent, words[index].text != text else { return }
        words[index].note(Word.Edit(by: pass, kind: .replaced, from: words[index].text, to: text))
        words[index].state = .replaced(by: pass, from: words[index].text)
        words[index].text = text
    }

    /// The silence the recogniser timed before the word at `index`, back to the last word it heard; nil when untimed.
    public func pause(before index: Int) -> Duration? {
        guard let start = words[index].start,
            let previous = words[..<index].last(where: { $0.end != nil })?.end
        else { return nil }
        return max(.zero, start - previous)
    }

    /// Puts a word the speaker never said into the text at `index`.
    public mutating func insert(_ text: String, at index: Int, by pass: PassID) {
        words.insert(
            Word(
                text: text, heard: "", evidence: .unknown, state: .inserted(by: pass),
                edits: [Word.Edit(by: pass, kind: .inserted, from: "", to: text)]), at: index)
    }
}

/// Holds the present positions of one version of a draft's words; an edit replaces it rather than changing it.
private final class PresenceCache: Sendable {
    private let stored = Mutex<[Int]?>(nil)

    func indices(_ compute: () -> [Int]) -> [Int] {
        if let known = stored.withLock({ $0 }) { return known }
        let computed = compute()
        stored.withLock { $0 = computed }
        return computed
    }
}
