import UttrflowCore
import UttrflowDictionary

/// Condition three, decided by counting evidence for each reading. See Docs/ai-correction-thresholds.md.
struct CorrectionEvidence: Sendable {
    /// The most words read off the screen: a visible page, and small enough that the scan is not measurable.
    static let maximumWordsOnScreen = 512

    /// Counts every read of the screen, so a test can show one utterance reads it once however many runs are doubted.
    @TaskLocal static var screensRead: WorkTally?

    /// The words the frontmost app is showing.
    private let onScreen: Haystack
    /// The text around the caret alone, so a word seen there is told from one only in the window.
    private let nearCaret: Haystack
    /// The contiguous certain runs of the utterance; uncertain words keep runs from joining.
    private let saidClearly: Haystack

    /// Reads both haystacks once per utterance; only words `DoubtPolicy` calls heard surely may corroborate.
    init(utterance: Utterance, seeing context: AppContext) {
        Self.screensRead?.record()
        // The title, the selection and the sentences before the caret, never the app's own name; `LearnableWords` agrees.
        onScreen = Haystack(
            TextTidy.words(
                [context.documentName, context.selectedText, context.recognitionContext]
                    .compactMap { $0 }
                    .joined(separator: " ")
            ).prefix(Self.maximumWordsOnScreen))
        nearCaret = Haystack(
            TextTidy.words(context.recognitionContext ?? "").prefix(Self.maximumWordsOnScreen))
        var certainRuns: [[String]] = []
        var current: [String] = []
        for word in utterance.words {
            guard DoubtPolicy.isHeardSurely(word.confidence) else {
                if !current.isEmpty { certainRuns.append(current); current = [] }
                continue
            }
            current.append(contentsOf: TextTidy.words(word.text))
        }
        if !current.isEmpty { certainRuns.append(current) }
        saidClearly = Haystack(certainRuns)
    }

    /// The best signal the candidate has and the heard reading lacks, or nil when the margin is not cleared.
    func decisiveReason(preferring candidate: String, over heard: String) -> CorrectionReason? {
        decision(preferring: candidate, over: heard)?.reason
    }

    /// The best signal and how strongly the candidate won, or nil when the margin is not cleared.
    func decision(
        preferring candidate: String, over heard: String
    ) -> (reason: CorrectionReason, evidence: OverrideEvidence)? {
        let (gained, lost) = signals(preferring: candidate, over: heard)
        let agreeing = SignalProvenance.agreement(of: gained)
        let margin = agreeing - SignalProvenance.agreement(of: lost)
        guard
            DoubtPolicy.OverridePolicy.allows(
                margin: margin,
                cost: ConfusionCost.of(heard: heard, candidate: candidate), consequence: .stores),
            let best = gained.first?.value
        else { return nil }
        return (best, OverrideEvidence(signals: agreeing, margin: margin))
    }

    /// How an added entry beats a heard non-word: the pair's own margin, moved by the counted signals; nil when it loses.
    func decision(respelling heard: String, as candidate: String, heardSurely: Bool) -> OverrideEvidence? {
        var (gained, lost) = signals(preferring: candidate, over: heard)
        // A word heard surely is in the clear runs itself, so it counts as said clearly only when said twice.
        if heardSurely, saidClearly.occurrences(of: TextTidy.words(heard)) < 2 {
            lost.removeAll { $0.value == .saidClearlyElsewhere }
        }
        let own = DoubtPolicy.OverridePolicy.nonWordMargin
        let agreeing = SignalProvenance.agreement(of: gained)
        let margin = own + agreeing - SignalProvenance.agreement(of: lost)
        guard
            DoubtPolicy.OverridePolicy.allows(
                margin: margin, cost: ConfusionCost.of(heard: heard, candidate: candidate),
                consequence: .stores)
        else { return nil }
        return OverrideEvidence(signals: own + agreeing, margin: margin)
    }

    /// The signals that hold for the candidate and not the heard reading, and those that hold the other way.
    func signals(
        preferring candidate: String, over heard: String
    ) -> (gained: [Sourced<CorrectionReason>], lost: [Sourced<CorrectionReason>]) {
        let candidateWords = TextTidy.words(candidate)
        let heardWords = TextTidy.words(heard)
        let forCandidate = reasons(supporting: candidateWords, ratherThan: heardWords)
        let forHeard = reasons(supporting: heardWords, ratherThan: candidateWords)
        // A reason that holds both ways cancels, wherever each side read it from.
        let candidateReasons = Set(forCandidate.map(\.value))
        let heardReasons = Set(forHeard.map(\.value))
        return (
            forCandidate.filter { !heardReasons.contains($0.value) },
            forHeard.filter { !candidateReasons.contains($0.value) }
        )
    }

    /// Every signal that holds for this reading rather than the other, in priority order, with where it was read.
    private func reasons(
        supporting words: [String], ratherThan other: [String]
    ) -> [Sourced<CorrectionReason>] {
        CorrectionReason.allCases.compactMap { reason in
            provenance(of: reason, for: words, ratherThan: other).map {
                Sourced(value: reason, provenance: $0)
            }
        }
    }

    /// Where one signal for `words` rather than for `other` was read from, or nil when it does not hold.
    private func provenance(
        of reason: CorrectionReason, for words: [String], ratherThan other: [String]
    ) -> SignalProvenance? {
        switch reason {
        case .seenOnScreen:
            guard onScreen.contains(words) else { return nil }
            return nearCaret.contains(words) ? .caretText : .windowText
        case .saidClearlyElsewhere: return saidClearly.contains(words) ? .recogniserAcoustics : nil
        case .heardAsStrayLetters: return Self.readsAsWholeWords(words) ? .transcriptLetters : nil
        // The one comparative signal, a run collapsing into one written word; symmetric, so it cancels.
        case .heardAsSeveralWords: return words.count < other.count ? .transcriptWordCount : nil
        // Decided by the letters alone, never by counting signals.
        case .heardAsNonWord, .spelledAsInDictionary, .unknown: return nil
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

        /// Keeps each contiguous run separate while retaining one-word lookup across all runs.
        init(_ runs: [[String]]) {
            self.words = runs.flatMap { $0 + ["\u{0000}"] }
            unique = Set(runs.flatMap { $0 })
        }

        /// How many times a one-word needle appears; a longer or empty needle counts none.
        func occurrences(of needle: [String]) -> Int {
            guard needle.count == 1, let word = needle.first, unique.contains(word) else { return 0 }
            return words.count(where: { $0 == word })
        }

        /// Whether the needle appears consecutively and in order; an empty needle is never contained.
        func contains(_ needle: [String]) -> Bool {
            // A first word that appears nowhere settles it without a scan, single-word needles included.
            guard let first = needle.first, unique.contains(first) else { return false }
            guard needle.count > 1 else { return true }
            guard needle.count <= words.count else { return false }
            return words.indices.dropLast(needle.count - 1).contains { start in
                needle.indices.allSatisfy {
                    words[start + $0] != "\u{0000}" && words[start + $0] == needle[$0]
                }
            }
        }
    }
}
