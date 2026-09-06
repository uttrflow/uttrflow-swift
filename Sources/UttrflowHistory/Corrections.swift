// What Uttrflow records against a dictation: corrections, snippet firings and the spoken word count.
public import struct Foundation.UUID

/// Why Uttrflow changed a word; a closed set whose raw values match `UttrflowAI.CorrectionReason`.
public enum CorrectionReason: String, Sendable, Equatable, CaseIterable, Codable {
    /// The replacement is written on the screen being dictated into.
    case seenOnScreen
    /// The same word appears elsewhere in this dictation, where it is heard clearly.
    case saidClearlyElsewhere
    /// What was heard was loose letters and the replacement is a word.
    case heardAsStrayLetters
    /// What was heard was a run of words and the replacement is one written word.
    case heardAsSeveralWords

    /// The label the Corrections page shows beside the change.
    public var title: String {
        switch self {
        case .seenOnScreen: "Seen on screen"
        case .saidClearlyElsewhere: "You said it clearly elsewhere"
        case .heardAsStrayLetters: "Heard as stray letters"
        case .heardAsSeveralWords: "Heard as several words"
        }
    }
}

/// One word Uttrflow replaced, with everything an undo needs so it never searches the finished text.
public struct RecordedCorrection: Sendable, Equatable, Identifiable, Codable {
    /// Identifies the change to the undo path and the Corrections page.
    public let id: UUID
    /// Exactly what the recogniser produced, verbatim.
    public let heard: String
    /// What was written in its place.
    public let wrote: String
    /// Which spoken words this covered, as indices into the transcript's words.
    public let wordRange: Range<Int>
    /// The entry that won; `PersonalDictionaryStore.recordRevert(of:)` counts an undo against it.
    public let entryID: UUID
    /// Why the word was changed.
    public let reason: CorrectionReason
    /// What the recogniser scored the words being replaced; shows that the engine only moves on a guess.
    public let heardConfidence: Double
    /// Whether the user has put it back; a flag, not a deletion, so the page can show it and count it.
    public var isUndone: Bool

    /// Builds a change whose reason is already named.
    public init(
        id: UUID = UUID(), heard: String, wrote: String, wordRange: Range<Int>, entryID: UUID,
        reason: CorrectionReason, heardConfidence: Double, isUndone: Bool = false
    ) {
        self.id = id
        self.heard = heard
        self.wrote = wrote
        self.wordRange = wordRange
        self.entryID = entryID
        self.reason = reason
        self.heardConfidence = heardConfidence
        self.isUndone = isUndone
    }

    /// Builds a change from the raw reason the pipeline carries, or `nil` when this build cannot name it.
    public init?(
        id: UUID = UUID(), heard: String, wrote: String, wordRange: Range<Int>, entryID: UUID,
        reason: String, heardConfidence: Double, isUndone: Bool = false
    ) {
        guard let named = CorrectionReason(rawValue: reason) else { return nil }
        self.init(
            id: id, heard: heard, wrote: wrote, wordRange: wordRange, entryID: entryID,
            reason: named, heardConfidence: heardConfidence, isUndone: isUndone)
    }

    /// Reads `isUndone` as `false` when absent; the rest is required. See Docs/core-history-decoding.md.
    public init(from decoder: any Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        id = try values.decode(UUID.self, forKey: .id)
        heard = try values.decode(String.self, forKey: .heard)
        wrote = try values.decode(String.self, forKey: .wrote)
        wordRange = try values.decode(Range<Int>.self, forKey: .wordRange)
        entryID = try values.decode(UUID.self, forKey: .entryID)
        reason = try values.decode(CorrectionReason.self, forKey: .reason)
        heardConfidence = try values.decode(Double.self, forKey: .heardConfidence)
        // A file without the flag and a change nobody undid are the same fact.
        isUndone = try values.decodeIfPresent(Bool.self, forKey: .isUndone) ?? false
    }
}

/// One snippet firing once.
public struct RecordedSnippet: Sendable, Equatable, Codable {
    /// Which snippet fired; a lookup rather than a copy, because the store may change by the time it is read.
    public let snippetID: UUID
    /// The words in the transcript that were replaced, exactly as they appeared there.
    public let matched: String
    /// What replaced them.
    public let expansion: String

    /// Builds one firing.
    public init(snippetID: UUID, matched: String, expansion: String) {
        self.snippetID = snippetID
        self.matched = matched
        self.expansion = expansion
    }
}

/// Everything Uttrflow changed about one dictation; present and empty means "nothing was changed".
public struct RecordedChanges: Sendable, Equatable, Codable {
    /// In the order the words were spoken.
    public var corrections: [RecordedCorrection]
    /// In the order they appear; a snippet that fires twice appears twice.
    public let snippets: [RecordedSnippet]
    /// How many words the user said; `nil` retires the accuracy figure. See Docs/core-history-accuracy.md.
    public let spokenWords: Int?

    /// Builds the set; both lists default to empty and the word count to unknown.
    public init(
        corrections: [RecordedCorrection] = [], snippets: [RecordedSnippet] = [],
        spokenWords: Int? = nil
    ) {
        self.corrections = corrections
        self.snippets = snippets
        self.spokenWords = spokenWords
    }

    /// Distinct in-range spoken positions still replaced; undone changes and snippets do not count.
    public var correctedWords: Int {
        guard let spokenWords else { return 0 }
        let said = 0..<spokenWords
        return Set(
            corrections.lazy
                .filter { !$0.isUndone }
                .flatMap(\.wordRange)
                .filter { said.contains($0) }
        ).count
    }

    /// Reads both lists entry by entry, dropping what it cannot read. See Docs/core-history-decoding.md.
    public init(from decoder: any Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        corrections =
            try values.decodeIfPresent([Salvaged<RecordedCorrection>].self, forKey: .corrections)?
            .compactMap(\.value) ?? []
        snippets =
            try values.decodeIfPresent([Salvaged<RecordedSnippet>].self, forKey: .snippets)?
            .compactMap(\.value) ?? []
        spokenWords = try values.decodeIfPresent(Int.self, forKey: .spokenWords)
    }
}

/// One `Value`, or `nil` when this build cannot read it, so an array of them never throws.
private struct Salvaged<Value: Decodable>: Decodable {
    /// The decoded value, or `nil` when decoding it threw.
    let value: Value?

    /// Swallows the decoding error on purpose; the alternative on this path is losing the whole history.
    init(from decoder: any Decoder) throws {
        value = try? Value(from: decoder)
    }
}
