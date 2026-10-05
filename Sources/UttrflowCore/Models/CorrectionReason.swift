// Why a word was swapped: the one vocabulary the correction engine writes and History stores.

/// Why one word was swapped; known cases in priority order, and `unknown` keeps a newer build's reason.
public enum CorrectionReason: Sendable, Hashable, CaseIterable, Codable, RawRepresentable {
    /// The replacement is written on the screen being dictated into.
    case seenOnScreen
    /// The same word appears elsewhere in this dictation, heard clearly.
    case saidClearlyElsewhere
    /// The heard text is loose letters and the replacement is a word; named from the losing side.
    case heardAsStrayLetters
    /// The heard text is several words and the replacement one written word; named from the losing side.
    case heardAsSeveralWords
    /// The heard letters are the entry's letters in another case, so only the case is changed.
    case spelledAsInDictionary
    /// A reason this build cannot name, kept verbatim so the record is shown and undoable, never dropped.
    case unknown(String)

    /// The reasons this build can decide, in priority order; `unknown` is only ever read, never proposed.
    public static let allCases: [CorrectionReason] = [
        .seenOnScreen, .saidClearlyElsewhere, .heardAsStrayLetters, .heardAsSeveralWords,
        .spelledAsInDictionary,
    ]

    /// Names the stored spelling, keeping one this build does not know as `unknown`.
    public init(rawValue: String) {
        self = Self.allCases.first { $0.rawValue == rawValue } ?? .unknown(rawValue)
    }

    /// The stored spelling, which is the case name for every known reason.
    public var rawValue: String {
        switch self {
        case .seenOnScreen: "seenOnScreen"
        case .saidClearlyElsewhere: "saidClearlyElsewhere"
        case .heardAsStrayLetters: "heardAsStrayLetters"
        case .heardAsSeveralWords: "heardAsSeveralWords"
        case .spelledAsInDictionary: "spelledAsInDictionary"
        case .unknown(let raw): raw
        }
    }

    /// The label the Corrections page shows beside the change.
    public var title: String {
        switch self {
        case .seenOnScreen: "Seen on screen"
        case .saidClearlyElsewhere: "You said it clearly elsewhere"
        case .heardAsStrayLetters: "Heard as stray letters"
        case .heardAsSeveralWords: "Heard as several words"
        case .spelledAsInDictionary: "Spelled as in your dictionary"
        case .unknown: "Other"
        }
    }

    /// Reads the stored spelling; an unknown one decodes rather than failing the record.
    public init(from decoder: any Decoder) throws {
        self.init(rawValue: try decoder.singleValueContainer().decode(String.self))
    }

    /// Writes the stored spelling, so an unknown reason is written back exactly as it was read.
    public func encode(to encoder: any Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(rawValue)
    }
}
