// Which languages a person dictates in, kept as counts in the evidence ledger and never as text.

/// The language counts, projected from evidence rows. See `Docs/learned-state.md`.
public enum LanguageSignals {
    /// A dictation of fewer words is not counted: detection on a short piece is too unreliable to teach from.
    public static let minimumWords = 8
    /// A verdict below this confidence, or without one, is not counted.
    public static let minimumConfidence = 0.8

    /// The row one dictation adds, or none when it is too short or the engine was not sure of the language.
    public static func rows(for text: String, heardAs language: DetectedLanguage?, day: Int) -> [EvidenceRow]
    {
        guard let language, let confidence = language.confidence, confidence >= minimumConfidence,
            WordShape.words(text).count >= minimumWords
        else { return [] }
        return [
            EvidenceRow(kind: .language, subject: language.code.value, day: day, provenance: .dictation)
        ]
    }

    /// Dictations counted per language code; rows of other kinds are ignored.
    public static func project(_ rows: [EvidenceRow]) -> [String: Int] {
        var totals: [String: Int] = [:]
        for row in rows where row.kind == .language { totals[row.subject, default: 0] += row.weight }
        return totals
    }
}
