import UttrflowCore
import UttrflowDictionary

/// Condition three, decided by counting evidence for each reading. See Docs/ai-correction-thresholds.md.
struct CorrectionEvidence: Sendable {
    /// Signals the candidate needs beyond the heard reading; two, so one coincidence never swaps a homophone.
    static let improvementMargin = 2

    /// The most words read off the screen: a visible page, and small enough that the scan is not measurable.
    static let maximumWordsOnScreen = 512

    /// The words the frontmost app is showing.
    private let onScreen: Haystack
    /// The words of the utterance the recogniser was sure of.
    private let saidClearly: Haystack

    /// Reads both haystacks once per utterance; only words at or above `certainAt` may corroborate.
    init(utterance: Utterance, seeing context: AppContext, certainAt threshold: Double) {
        // Split by letters and digits, not by sound: `PaymentSheet.swift` must match the entry.
        onScreen = Haystack(
            TextTidy.words(
                [context.applicationName, context.documentName, context.selectedText]
                    .compactMap { $0 }
                    .joined(separator: " ")
            ).prefix(Self.maximumWordsOnScreen))
        saidClearly = Haystack(
            utterance.words
                .filter { $0.confidence >= threshold }
                .flatMap { TextTidy.words($0.text) })
    }

    /// The best signal the candidate has and the heard reading lacks, or nil when the margin is not cleared.
    func decisiveReason(preferring candidate: String, over heard: String) -> CorrectionReason? {
        let candidateWords = TextTidy.words(candidate)
        let heardWords = TextTidy.words(heard)
        let forCandidate = reasons(supporting: candidateWords, ratherThan: heardWords)
        let forHeard = reasons(supporting: heardWords, ratherThan: candidateWords)
        let gained = forCandidate.filter { !forHeard.contains($0) }
        let lost = forHeard.filter { !forCandidate.contains($0) }
        guard gained.count >= lost.count + Self.improvementMargin else { return nil }
        return gained.first
    }

    /// Every signal that holds for this reading rather than the other, in priority order.
    private func reasons(supporting words: [String], ratherThan other: [String]) -> [CorrectionReason] {
        CorrectionReason.allCases.filter { holds($0, for: words, ratherThan: other) }
    }

    /// Whether one signal holds for `words` rather than for `other`.
    private func holds(_ reason: CorrectionReason, for words: [String], ratherThan other: [String]) -> Bool {
        switch reason {
        case .seenOnScreen: onScreen.contains(words)
        case .saidClearlyElsewhere: saidClearly.contains(words)
        case .heardAsStrayLetters: Self.readsAsWholeWords(words)
        // The one comparative signal, a run collapsing into one written word; symmetric, so it cancels.
        case .heardAsSeveralWords: words.count < other.count
        }
    }

    // MARK: Reading the text

    /// Whether the text is words rather than letters a recogniser spelt out; "a", "I" and digits are words.
    static func readsAsWholeWords(_ text: String) -> Bool {
        readsAsWholeWords(TextTidy.words(text))
    }

    /// The same rule against text already split into words, which is how the hot path holds it.
    static func readsAsWholeWords(_ words: [String]) -> Bool {
        words.allSatisfy { $0.count > 1 || $0 == "a" || $0 == "i" || $0.allSatisfy(\.isNumber) }
    }
}

extension CorrectionEvidence {
    /// A body of text a run of words might appear in; keeps a set beside the sequence for one-word needles.
    private struct Haystack: Sendable {
        /// The words in order.
        private let words: [String]
        /// The same words as a set, answering a one-word needle without a scan.
        private let unique: Set<String>

        /// Keeps the words and indexes them.
        init(_ words: some Sequence<String>) {
            self.words = Array(words)
            unique = Set(self.words)
        }

        /// Whether the needle appears consecutively and in order; an empty needle is never contained.
        func contains(_ needle: [String]) -> Bool {
            // A first word that appears nowhere settles it without a scan, single-word needles included.
            guard let first = needle.first, unique.contains(first) else { return false }
            guard needle.count > 1 else { return true }
            guard needle.count <= words.count else { return false }
            return words.indices.dropLast(needle.count - 1).contains { start in
                needle.indices.allSatisfy { words[start + $0] == needle[$0] }
            }
        }
    }
}
