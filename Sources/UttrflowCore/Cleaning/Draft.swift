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

            public init(by: PassID, kind: Kind, from: String, to: String) {
                self.by = by
                self.kind = kind
                self.from = from
                self.to = to
            }
        }

        /// The word as it reads now, or a layout mark beginning with a newline.
        public var text: String
        /// What the recogniser said, never changed; empty for a word a pass inserted.
        public let heard: String
        /// The recogniser's confidence in the heard word, 0 to 1.
        public let confidence: Double
        public var state: State
        /// Every change a pass has made to this word, oldest first.
        public private(set) var edits: [Edit]

        public init(
            text: String, heard: String, confidence: Double = 1, state: State = .kept,
            edits: [Edit] = []
        ) {
            self.text = text
            self.heard = heard
            self.confidence = confidence
            self.state = state
            self.edits = edits
        }

        /// Notes what a pass has just done to this word, keeping the chain a later pass adds to.
        mutating func note(_ edit: Edit) {
            edits.append(edit)
        }

        /// A heard word that nothing has touched yet.
        public init(_ heard: String, confidence: Double = 1) {
            self.init(text: heard, heard: heard, confidence: confidence, state: .kept)
        }

        /// Whether the word still appears in the text.
        public var isPresent: Bool {
            if case .removed = state { return false }
            return true
        }

        /// Whether the word is a line break, a paragraph break or a bullet rather than something said.
        public var isLayoutMark: Bool { text.hasPrefix("\n") || text == Draft.bullet }

        /// Whether the word is the bullet that opens a list item.
        public var isListMark: Bool { text.hasSuffix(Draft.bullet) }
    }

    /// The dash and space a list item begins with, after the line break that starts it.
    public static let bullet = "- "
    /// The tokens a line may open with to be read as a list item.
    private static let bulletTokens: Set<Substring> = ["-", "•", "*"]

    public var words: [Word]
    /// Whether the words carry the recogniser's confidences rather than a stand-in of 1 for every word.
    public let confidencesAreReal: Bool

    public init(words: [Word], confidencesAreReal: Bool = false) {
        self.words = words
        self.confidencesAreReal = confidencesAreReal
    }

    /// Splits plain text on whitespace, giving every word full confidence.
    public init(text: String) {
        self.init(words: Self.split(text, confidence: 1))
    }

    /// Splits text on spaces and tabs, keeping each run of line breaks as one layout mark and a bulleted line as a list item.
    public init(keepingLineBreaks text: String) {
        var words: [Word] = []
        var previousLine: Int?
        let lines = text.split(omittingEmptySubsequences: false, whereSeparator: \.isNewline)
        for (number, line) in lines.enumerated() {
            var lineWords = line.split(whereSeparator: \.isWhitespace)
            guard !lineWords.isEmpty else { continue }
            let isItem = lineWords.count > 1 && Self.bulletTokens.contains(lineWords[0])
            if isItem { lineWords.removeFirst() }
            let breaks = previousLine.map { String(repeating: "\n", count: number - $0) } ?? ""
            let mark = breaks + (isItem ? Self.bullet : "")
            if !mark.isEmpty { words.append(Word(mark)) }
            words += lineWords.map { Word(String($0)) }
            previousLine = number
        }
        self.init(words: words)
    }

    /// Takes the recogniser's confidences when its timed words spell the text, spacing aside, else splits it.
    public init(transcription: Transcription) {
        let spoken = Self.split(transcription.text, confidence: 1)
        let timed = transcription.segments.flatMap(\.words).flatMap {
            Self.split($0.text, confidence: $0.confidence)
        }
        guard !timed.isEmpty, timed.map(\.text).joined() == spoken.map(\.text).joined() else {
            self.init(words: spoken)
            return
        }
        self.init(words: Self.confidences(of: timed, onto: spoken), confidencesAreReal: true)
    }

    private static func split(_ text: String, confidence: Double) -> [Word] {
        text.split(whereSeparator: \.isWhitespace).map { Word(String($0), confidence: confidence) }
    }

    /// Gives each of `spoken` the lowest confidence among the timed words that spell it, letter for letter.
    private static func confidences(of timed: [Word], onto spoken: [Word]) -> [Word] {
        var remaining = timed[...]
        var spent = 0
        return spoken.map { word in
            var needed = word.text.count
            var confidence = 1.0
            while needed > 0, let next = remaining.first {
                confidence = min(confidence, next.confidence)
                let available = next.text.count - spent
                guard available <= needed else {
                    spent += needed
                    needed = 0
                    continue
                }
                needed -= available
                spent = 0
                remaining.removeFirst()
            }
            return Word(word.text, confidence: confidence)
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
    public var presentIndices: [Int] { words.indices.filter { words[$0].isPresent } }

    // MARK: Editing

    /// Takes the word at `index` out of the text, remembering which pass did it.
    public mutating func remove(at index: Int, by pass: PassID) {
        guard words[index].isPresent else { return }
        words[index].note(Word.Edit(by: pass, kind: .removed, from: words[index].text, to: ""))
        words[index].state = .removed(by: pass)
    }

    /// Rewrites the word at `index`, remembering the pass and what it read before; a removed word stays removed.
    public mutating func replace(at index: Int, with text: String, by pass: PassID) {
        guard words[index].isPresent, words[index].text != text else { return }
        words[index].note(Word.Edit(by: pass, kind: .replaced, from: words[index].text, to: text))
        words[index].state = .replaced(by: pass, from: words[index].text)
        words[index].text = text
    }

    /// Puts a word the speaker never said into the text at `index`.
    public mutating func insert(_ text: String, at index: Int, by pass: PassID) {
        words.insert(
            Word(
                text: text, heard: "", confidence: 1, state: .inserted(by: pass),
                edits: [Word.Edit(by: pass, kind: .inserted, from: "", to: text)]), at: index)
    }
}
