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

        /// The word as it reads now, or a layout mark beginning with a newline.
        public var text: String
        /// What the recogniser said, never changed; empty for a word a pass inserted.
        public let heard: String
        /// The recogniser's confidence in the heard word, 0 to 1.
        public let confidence: Double
        public var state: State

        public init(text: String, heard: String, confidence: Double = 1, state: State = .kept) {
            self.text = text
            self.heard = heard
            self.confidence = confidence
            self.state = state
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

        /// Whether the word is a line or paragraph break rather than something said.
        public var isLayoutMark: Bool { text.hasPrefix("\n") }
    }

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

    /// Splits text on spaces and tabs, keeping each run of line breaks between words as one layout mark.
    public init(keepingLineBreaks text: String) {
        var words: [Word] = []
        var previousLine: Int?
        let lines = text.split(omittingEmptySubsequences: false, whereSeparator: \.isNewline)
        for (number, line) in lines.enumerated() {
            let lineWords = line.split(whereSeparator: \.isWhitespace)
            guard !lineWords.isEmpty else { continue }
            if let previousLine { words.append(Word(String(repeating: "\n", count: number - previousLine))) }
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
        words[index].state = .removed(by: pass)
    }

    /// Rewrites the word at `index`, remembering the pass and what it read before.
    public mutating func replace(at index: Int, with text: String, by pass: PassID) {
        guard words[index].text != text else { return }
        words[index].state = .replaced(by: pass, from: words[index].text)
        words[index].text = text
    }

    /// Puts a word the speaker never said into the text at `index`.
    public mutating func insert(_ text: String, at index: Int, by pass: PassID) {
        words.insert(Word(text: text, heard: "", confidence: 1, state: .inserted(by: pass)), at: index)
    }
}
