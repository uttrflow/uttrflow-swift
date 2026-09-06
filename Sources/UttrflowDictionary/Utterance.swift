/// One word a recogniser thinks it heard, with its confidence, which says where help is worth spending.
public struct SpokenWord: Sendable, Equatable {
    public let text: String
    /// Between zero and one, clamped, because a negative confidence would sort itself to the front.
    public let confidence: Double

    public init(text: String, confidence: Double) {
        self.text = text
        self.confidence = min(1, max(0, confidence))
    }
}

/// Everything the recogniser produced for one press; the candidates offered are a function of this alone.
public struct Utterance: Sendable, Equatable {
    public let words: [SpokenWord]

    public init(words: [SpokenWord]) {
        self.words = words
    }

    /// A whole transcript at one confidence, for an engine that scores the utterance rather than each word.
    public init(heard text: String, confidence: Double) {
        self.init(
            words: text.split(whereSeparator: \.isWhitespace)
                .map { SpokenWord(text: String($0), confidence: confidence) })
    }
}

/// A run of consecutive spoken words that might be one entry, since "payment sheet" is `PaymentSheet`.
struct SpokenSpan: Sendable, Equatable {
    /// The words with spaces left in; `DoubleMetaphone` ignores spaces, so this keys as the closed form.
    let text: String
    /// The confidence of the least certain word in the run.
    let confidence: Double
    /// Where the run starts, used only to keep equally uncertain runs in a stable order.
    let start: Int
}

extension Utterance {
    /// Every run of up to `maximumLength` words, least confident first, so the budget goes where needed.
    func spans(upTo maximumLength: Int) -> [SpokenSpan] {
        var spans: [SpokenSpan] = []
        for start in words.indices {
            for length in 1...max(1, maximumLength) where start + length <= words.count {
                let run = words[start..<(start + length)]
                spans.append(
                    SpokenSpan(
                        text: run.map(\.text).joined(separator: " "),
                        confidence: run.reduce(1) { min($0, $1.confidence) },
                        start: start))
            }
        }
        return spans.sorted(by: SpokenSpan.isMoreDeserving)
    }
}

extension Utterance {
    /// Every sound this utterance could be hiding, as index keys; one place, so offering and learning agree.
    func sounds(upTo maximumLength: Int) -> Set<String> {
        Set(spans(upTo: maximumLength).flatMap { DoubleMetaphone.code(for: $0.text).keys })
    }
}

extension SpokenSpan {
    /// A total order, so the same utterance always produces the same shortlist in the same order.
    static func isMoreDeserving(_ first: SpokenSpan, _ second: SpokenSpan) -> Bool {
        if first.confidence != second.confidence { return first.confidence < second.confidence }
        if first.start != second.start { return first.start < second.start }
        return first.text.count > second.text.count
    }
}
