public import UttrflowCore

/// Ends a sentence where the speaker paused as long as a piece boundary, inside one piece. See `Docs/cleanup.md`.
public struct PauseStopPass: PieceCleaningPass {
    public static let id: PassID = .pauseStop
    public static let laws: Set<PassLaw> = Set(PassLaw.allCases)

    /// The silence that ends a sentence: the pause that also ends a piece, so both boundaries agree.
    public static func sentencePause(for pauses: PauseLength) -> Duration {
        .seconds(SpeechWindowing.standard.adjusted(for: pauses).sentencePause)
    }

    /// Where the text goes; only prose takes a stop from a pause.
    public let destination: Destination

    /// The silence that ends a sentence for the person speaking.
    public let sentencePause: Duration

    public init(destination: Destination = .plain, pauses: PauseLength = .usual) {
        self.destination = destination
        self.sentencePause = Self.sentencePause(for: pauses)
    }

    public func apply(_ draft: Draft) -> Draft {
        guard Self.prose.contains(destination) else { return draft }
        var draft = draft
        let live = draft.presentIndices
        for (index, next) in zip(live, live.dropFirst()) {
            guard let pause = draft.pause(before: next), pause >= sentencePause,
                !draft.words[index].isLayoutMark, !draft.words[next].isLayoutMark,
                draft.shape(at: index).suffix.isEmpty, !draft.shape(at: index).core.isEmpty
            else { continue }
            let before = live.prefix { $0 <= index }.map { draft.words[$0].text }.joined(separator: " ")
            let after = live.drop { $0 < next }.map { draft.words[$0].text }.joined(separator: " ")
            // The same evidence that keeps a seam's sentence going keeps this one going.
            guard !SentenceBoundaryEvidence.sentenceRunsOn(before, into: after) else { continue }
            draft.replace(at: index, with: WordShape.finished(draft.words[index].text), by: Self.id)
        }
        return draft
    }

    private static let prose: Set<Destination> = [.document, .messaging, .email, .plain]
}
