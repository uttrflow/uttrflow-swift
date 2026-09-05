public import UttrflowCore

/// One passage the operator reads aloud, and what a recogniser must come back with.
///
/// The transformation half of this harness starts from a transcript typed out by hand
/// (``EvaluationCase/spoken``). This half cannot: the thing being measured is the
/// recogniser itself, so the input has to be real speech and the reference has to be
/// what was actually read. Everything else — an id, the terms that must survive — is
/// deliberately the same vocabulary as ``EvaluationCase``, so both halves of Phase 8
/// report in the same words.
public struct TranscriptionCase: Sendable, Equatable, Codable, Identifiable {
    /// Which of the product's three ways of speaking this passage is.
    ///
    /// Not a ``LanguageCode``, because Hinglish has no tag of its own and folding it
    /// into Hindi would hide the case most likely to break: a sentence whose nouns are
    /// English and whose grammar is Hindi is not the same problem as either.
    public enum Language: String, Sendable, Equatable, CaseIterable, Codable {
        case english
        case hindi
        case hinglish

        /// What a recogniser is told to expect, when it is told anything at all.
        /// Hinglish is Hindi-led, so it hints Hindi.
        public var code: LanguageCode { self == .english ? .english : .hindi }
    }

    /// What this passage is here to break.
    ///
    /// Deliberately not ``EvaluationCase/Category``: those categories describe what a
    /// *rewriter* has to decide, and these describe what makes a *recogniser* mishear,
    /// which is a different list. A false start is trivial to transcribe and hard to
    /// clean up; a version number is the other way round.
    public enum Stressor: String, Sendable, Equatable, CaseIterable, Codable {
        /// Ordinary speech at an ordinary pace, so the rest has a floor to beat.
        case everyday
        /// Names of people and places, which no language model can guess from context.
        case properNouns
        /// Digits, versions and ports, where one wrong character changes the meaning.
        case digits
        /// Product and programming terms that are not words.
        case technical
        /// Repeats, restarts and mid-sentence corrections, as people actually talk.
        case falseStarts
        /// A stress the catalogue names and this enum has no word for — an accent, a
        /// noisy room, somebody speaking quickly. Kept as its own row rather than
        /// folded into ``everyday``: those samples are not the easy ones, and filing
        /// them under the floor category would flatter the number the floor exists to
        /// set. What is actually being stressed is in ``TranscriptionCase/stresses``.
        case other

        /// The labels to report under, which are this stressor's own name when none are listed.
        func labels(from stresses: [String]) -> [String] {
            stresses.isEmpty ? [rawValue] : stresses
        }
    }

    public let id: String
    public let language: Language
    public let stressor: Stressor
    /// The passage in Latin script — the form the product must ultimately produce,
    /// because Uttrflow's Hindi output is romanised Hinglish and never Devanagari.
    public let romanised: String
    /// The same passage as a recogniser that answers in Devanagari would write it,
    /// English loanwords included in the script the recogniser leaves them in.
    /// `nil` for a passage with no Hindi in it.
    public let devanagari: String?
    /// Words that must survive whatever else does — loanwords, numbers, product names.
    ///
    /// Only ever terms spelled the same in either script. A Devanagari transcript
    /// writes a Hindi name in Devanagari, so demanding the romanised spelling would
    /// fail every Hindi passage every time and say nothing about the recogniser. Those
    /// words are measured by the word error rate along with all the others.
    public let mustKeep: [String]
    /// Everything this passage stresses, in the corpus catalogue's vocabulary.
    ///
    /// A list rather than the single ``stressor`` because a real recording stresses
    /// several things at once — a noisy room *and* proper nouns — and at a thousand
    /// samples the question worth answering is "how do we do on proper nouns", not
    /// "how do we do on samples whose primary label happens to be proper nouns". Rows
    /// built from this therefore overlap and do not sum to the corpus; every report
    /// that prints them says so.
    public let stresses: [String]

    public init(
        id: String,
        language: Language,
        stressor: Stressor,
        romanised: String,
        devanagari: String? = nil,
        mustKeep: [String] = [],
        stresses: [String] = []
    ) {
        self.id = id
        self.language = language
        self.stressor = stressor
        self.romanised = romanised
        self.devanagari = devanagari
        self.mustKeep = mustKeep
        // The hand-written corpus says what it stresses once, in the typed field. Making
        // it repeat itself in a second list is how the two come to disagree.
        self.stresses = stressor.labels(from: stresses)
    }

    /// Decoded by hand for one reason: a passage recorded before this type grew a field
    /// must still decode.
    ///
    /// The recordings are days of somebody's time and they outlive several versions of
    /// the harness. A synthesised decoder would refuse an older file outright, which
    /// turns "the harness gained a field" into "the corpus has to be read again".
    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let stressor = try container.decode(Stressor.self, forKey: .stressor)
        self.init(
            id: try container.decode(String.self, forKey: .id),
            language: try container.decode(Language.self, forKey: .language),
            stressor: stressor,
            romanised: try container.decode(String.self, forKey: .romanised),
            devanagari: try container.decodeIfPresent(String.self, forKey: .devanagari),
            mustKeep: try container.decodeIfPresent([String].self, forKey: .mustKeep) ?? [],
            stresses: try container.decodeIfPresent([String].self, forKey: .stresses) ?? []
        )
    }

    /// What the operator is shown to read.
    ///
    /// Devanagari when there is a Devanagari form, because that is what a Hindi speaker
    /// reads fluently — and reading is the one part of this a person cannot be asked to
    /// do twice.
    public var prompt: String { devanagari ?? romanised }

    /// The reference to score a transcript against, given the script it came back in.
    ///
    /// Scoring a Devanagari transcript against a romanised reference — or the reverse —
    /// measures transliteration rather than recognition and invents errors the
    /// recogniser never made, so each script is scored against its own form of the
    /// passage. When only one form exists, the caller has to transliterate and say so.
    /// An empty ``romanised`` counts as absent rather than as a reference of no words.
    /// A catalogue sample written only in Devanagari has no Latin form, and scoring a
    /// Latin transcript against nothing would report every word as an invention.
    public func reference(in script: Script) -> String? {
        switch script {
        case .devanagari: devanagari
        case .latin: romanised.isEmpty ? nil : romanised
        }
    }

    /// Every form of this passage that exists, for the checks that both must satisfy.
    public var forms: [String] { [romanised, devanagari].compactMap(\.self).filter { !$0.isEmpty } }
}
