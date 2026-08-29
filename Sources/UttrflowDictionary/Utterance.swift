/// One word a recogniser thinks it heard, and how sure it was.
///
/// The confidence travels with the word because it is the only thing that says where
/// help is worth spending. A word the model is certain of does not need the dictionary
/// arguing with it; a word it half-guessed is exactly where a personal spelling
/// belongs. When the candidate budget runs out, that is the order it runs out in.
public struct SpokenWord: Sendable, Equatable {
    public let text: String
    /// Between zero and one. Clamped rather than trusted, because it arrives from a
    /// speech engine whose scale is its own business and a negative confidence would
    /// silently sort itself to the front of the queue.
    public let confidence: Double

    public init(text: String, confidence: Double) {
        self.text = text
        self.confidence = min(1, max(0, confidence))
    }
}

/// Everything the recogniser produced for one press of the hotkey.
///
/// This type is the boundary the scalability guarantee is stated against: the
/// candidates offered for a dictation are a function of *this* and nothing else. The
/// dictionary decides which entries are relevant; it never decides how many there are.
public struct Utterance: Sendable, Equatable {
    public let words: [SpokenWord]

    public init(words: [SpokenWord]) {
        self.words = words
    }

    /// A whole transcript at one confidence, which is what an engine that scores the
    /// utterance rather than each word gives us.
    public init(heard text: String, confidence: Double) {
        self.init(
            words: text.split(whereSeparator: \.isWhitespace)
                .map { SpokenWord(text: String($0), confidence: confidence) })
    }
}

/// A run of consecutive spoken words that might turn out to be one dictionary entry.
///
/// Runs and not just words because the entries this product exists for are written
/// closed and said open: nobody dictates "PaymentSheet" as one word, they say "payment
/// sheet", and `setUserPrefs` is three. Looking up only single words would make the
/// whole camel-cased half of the dictionary unreachable.
struct SpokenSpan: Sendable, Equatable {
    /// The words with their spaces left in. ``DoubleMetaphone`` makes no sound for a
    /// space, so this keys identically to the closed-up spelling.
    let text: String
    /// The confidence of the least certain word in the run — a run is only as trusted
    /// as its weakest word.
    let confidence: Double
    /// Where the run starts, used only to keep the order of equally uncertain runs
    /// stable.
    let start: Int
}

extension Utterance {
    /// Every run of up to `maximumLength` consecutive words, least confident first.
    ///
    /// The count is bounded by the utterance — at most `maximumLength × words.count`
    /// runs, whatever the dictionary holds — which is the arithmetic the whole design
    /// rests on.
    ///
    /// Ordered by confidence so that when the candidate budget is spent it is spent on
    /// the words that needed it. Longer runs sort ahead of the single words inside them
    /// for free: a run's confidence is its minimum, so it can only be lower.
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
    /// Every sound this utterance could be hiding, as index keys.
    ///
    /// The same question ``spans(upTo:)`` answers, asked of the sounds rather than the
    /// words, and here rather than at its two call sites because they must not drift.
    /// One of them decides which of the user's words are worth putting in front of the
    /// recogniser and the other decides whether a term on screen was actually spoken;
    /// if those two ever disagreed about what a phrase sounds like, a word could be
    /// offered to a decoder and never learnt, or learnt and never offered.
    func sounds(upTo maximumLength: Int) -> Set<String> {
        Set(spans(upTo: maximumLength).flatMap { DoubleMetaphone.code(for: $0.text).keys })
    }
}

extension SpokenSpan {
    /// A total order, so that the same utterance always produces the same shortlist in
    /// the same order. Anything less would make the guarantee untestable.
    static func isMoreDeserving(_ first: SpokenSpan, _ second: SpokenSpan) -> Bool {
        if first.confidence != second.confidence { return first.confidence < second.confidence }
        if first.start != second.start { return first.start < second.start }
        return first.text.count > second.text.count
    }
}
