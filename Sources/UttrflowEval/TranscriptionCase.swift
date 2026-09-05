public import UttrflowCore

/// One passage the operator reads aloud, and what a recogniser must come back with.
public struct TranscriptionCase: Sendable, Equatable, Codable, Identifiable {
    /// Which of the product's three ways of speaking this passage is; Hinglish is its own case.
    public enum Language: String, Sendable, Equatable, CaseIterable, Codable {
        case english
        case hindi
        case hinglish

        /// What a recogniser is told to expect when hinted; Hinglish is Hindi-led, so it hints Hindi.
        public var code: LanguageCode { self == .english ? .english : .hindi }
    }

    /// What makes a recogniser mishear this passage, as distinct from what a rewriter must decide.
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
        /// A stress the catalogue names and this enum does not; kept apart from ``everyday``.
        case other

        /// The labels to report under, which are this stressor's own name when none are listed.
        func labels(from stresses: [String]) -> [String] {
            stresses.isEmpty ? [rawValue] : stresses
        }
    }

    public let id: String
    public let language: Language
    public let stressor: Stressor
    /// The passage in Latin script, the form the product must produce.
    public let romanised: String
    /// The passage as a Devanagari-answering recogniser writes it; `nil` for a passage with no Hindi.
    public let devanagari: String?
    /// Words that must survive, limited to terms spelled the same in either script.
    public let mustKeep: [String]
    /// Everything this passage stresses, in the catalogue's vocabulary; rows built from this overlap.
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
        // The hand-written corpus states its stress once, in the typed field, so the list derives from it.
        self.stresses = stressor.labels(from: stresses)
    }

    /// Decodes by hand so a passage recorded without the newer fields still decodes.
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

    /// What the operator is shown to read: Devanagari when there is one, since that reads fluently.
    public var prompt: String { devanagari ?? romanised }

    /// The reference for the script a transcript came back in, or `nil` when that form is absent.
    public func reference(in script: Script) -> String? {
        switch script {
        case .devanagari: devanagari
        case .latin: romanised.isEmpty ? nil : romanised
        }
    }

    /// Every form of this passage that exists, for the checks that both must satisfy.
    public var forms: [String] { [romanised, devanagari].compactMap(\.self).filter { !$0.isEmpty } }
}
