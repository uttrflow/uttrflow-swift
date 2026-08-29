import UttrflowCore
import UttrflowDictionary

/// Condition three: whether the sentence is measurably better with the candidate in it.
///
/// The hardest of the three conditions and the one that decides whether this feature is
/// useful or a menace, so it is worth saying plainly what it is *not*.
///
/// It is not a language model. The obvious design is to ask ``CleanupModel`` which of two
/// readings fits, and it fails for a reason that has nothing to do with latency: every
/// word this engine can possibly propose is, by construction, a word a general model has
/// never seen. That is *why* it is in a personal dictionary. Asking Apple's on-device
/// model whether "Uttrflow" belongs in this sentence buys an opinion formed from no
/// evidence, and buys it at a model call per uncertain word on a path that already spends
/// two seconds. The same argument retires word embeddings, which return nothing at all for
/// a word outside their vocabulary — which is, again, every word here.
///
/// So the question is answered from evidence rather than from fluency: *is this word
/// attested in this situation, more than the words that were heard are?* Four independent
/// signals, each worth the same, each read from things already in hand — the utterance
/// itself, and what the frontmost app is showing. Both readings are scored the same way,
/// which is what makes this comparative rather than a licence: a rare word that was heard
/// correctly usually has the evidence on *its* side, and then it wins and nothing changes.
struct CorrectionEvidence: Sendable {
    /// How many signals the candidate must have that the heard words lack.
    ///
    /// Two, not one, and this is the single most important number in the engine. One
    /// signal is a coincidence — the whole risk of this feature is that a real word the
    /// user said correctly happens to be a near-homophone of a dictionary word that
    /// happens to be on the screen, and at a margin of one, "the bear clawed the bark"
    /// becomes "the bear Claude the bark" for anyone with a file called `Claude notes`
    /// open. At two it does not, because "clawed" and "Claude" are the same shape and only
    /// one signal separates them. The changes that survive a margin of two are the ones
    /// where the recogniser visibly came apart — a word split in half, a word spelt out —
    /// and *then* something in the situation names the word it came apart into.
    ///
    /// Integers rather than fractions because the signals are counts of independent facts,
    /// and there is no such thing as being three-tenths seen on screen.
    static let improvementMargin = 2

    /// The most words read off the screen.
    ///
    /// A selection can be an entire document and this runs inside a dictation, so the read
    /// has to be bounded somewhere. Five hundred covers a visible page — the word being
    /// looked for is rarely on the thousandth line of a selection — and is small enough
    /// that the scan is not measurable.
    static let maximumWordsOnScreen = 512

    private let onScreen: Haystack
    private let saidClearly: Haystack

    /// Reads the two haystacks once per utterance rather than once per candidate.
    ///
    /// `certainAt` does two jobs on purpose: it is both the line below which a word may be
    /// replaced and the line at or above which a word may vouch for a replacement. Because
    /// those two sets are exact complements, a mis-heard word can never turn up as its own
    /// corroboration — the bug that would make this signal quietly circular.
    init(utterance: Utterance, seeing context: AppContext, certainAt threshold: Double) {
        onScreen = Haystack(
            Self.tokens(
                [context.applicationName, context.documentName, context.selectedText]
                    .compactMap { $0 }
                    .joined(separator: " ")
            ).prefix(Self.maximumWordsOnScreen))
        saidClearly = Haystack(
            utterance.words
                .filter { $0.confidence >= threshold }
                .flatMap { Self.tokens($0.text) })
    }

    /// The strongest reason to prefer `candidate` over `heard`, or `nil` when the evidence
    /// does not clear the margin.
    ///
    /// Returning the reason and the verdict as one value is deliberate: they are the same
    /// fact, and a design that decided first and explained afterwards could explain a
    /// decision it never made. The reason offered is the best signal the candidate has and
    /// the heard words lack, so it is always something the change actually turned on.
    ///
    /// Each reading is split into words once here rather than once per signal. This runs
    /// dozens of times inside a dictation, and re-splitting the same two short strings
    /// eight times over was most of what it cost.
    func decisiveReason(preferring candidate: String, over heard: String) -> CorrectionReason? {
        let candidateWords = Self.tokens(candidate)
        let heardWords = Self.tokens(heard)
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

    private func holds(_ reason: CorrectionReason, for words: [String], ratherThan other: [String]) -> Bool {
        switch reason {
        case .seenOnScreen: onScreen.contains(words)
        case .saidClearlyElsewhere: saidClearly.contains(words)
        case .heardAsStrayLetters: Self.readsAsWholeWords(words)
        // The one signal that compares the two readings rather than reading each alone,
        // and the one that separates a recogniser coming apart from a recogniser being
        // merely unsure. Nobody dictates `PaymentSheet` as one word; they say "payment
        // sheet", and a spoken run collapsing into a single written word is the shape of
        // most of what this dictionary holds. Symmetric, so the arithmetic still cancels:
        // whichever reading is the shorter holds it.
        case .heardAsSeveralWords: words.count < other.count
        }
    }

    // MARK: Reading the text

    /// Lower-cased runs of letters and digits.
    ///
    /// Splitting this way is what lets the on-screen signal tell the two readings apart: a
    /// window titled `PaymentSheet.swift` offers the single token `paymentsheet`, which the
    /// entry matches and the spoken "payment sheet" does not. Matching by *sound* here — as
    /// the phonetic index rightly does elsewhere — would score both readings identically
    /// and the signal would discriminate nothing at all.
    static func tokens(_ text: String) -> [String] {
        text.lowercased().split { !$0.isLetter && !$0.isNumber }.map(String.init)
    }

    /// Whether the text is words rather than the letters a recogniser spells out when it
    /// has given up on a sound.
    ///
    /// A lone letter in the middle of dictated prose is almost never speech — "s q l" is
    /// the recogniser admitting it could not decode `SQL`. "a" and "I" are the two English
    /// words one letter long, and a lone digit is left alone because "3 tickets" is
    /// something people say.
    ///
    /// The overload below is the same rule against text already split, which is how the
    /// hot path has it; this one is here so a caller with a sentence in hand can ask.
    static func readsAsWholeWords(_ text: String) -> Bool {
        readsAsWholeWords(tokens(text))
    }

    static func readsAsWholeWords(_ words: [String]) -> Bool {
        words.allSatisfy { $0.count > 1 || $0 == "a" || $0 == "i" || $0.allSatisfy(\.isNumber) }
    }
}

extension CorrectionEvidence {
    /// A body of text a run of words might appear in.
    ///
    /// Keeps a set beside the sequence because the needle is nearly always one word, and a
    /// selection five hundred words long would otherwise turn every one of the dozens of
    /// lookups in an utterance into a scan of it.
    private struct Haystack: Sendable {
        private let words: [String]
        private let unique: Set<String>

        init(_ words: some Sequence<String>) {
            self.words = Array(words)
            unique = Set(self.words)
        }

        /// Whether these words appear consecutively and in this order.
        ///
        /// An empty needle is never contained. Anything else would make a correction whose
        /// heard text was pure punctuation look corroborated by every screen there is.
        func contains(_ needle: [String]) -> Bool {
            // A run whose first word appears nowhere cannot appear, so the set answers
            // almost every question here — including the single-word one — without a scan.
            guard let first = needle.first, unique.contains(first) else { return false }
            guard needle.count > 1 else { return true }
            guard needle.count <= words.count else { return false }
            return words.indices.dropLast(needle.count - 1).contains { start in
                needle.indices.allSatisfy { words[start + $0] == needle[$0] }
            }
        }
    }
}
