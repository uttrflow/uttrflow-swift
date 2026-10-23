public import UttrflowCore

/// Ends a sentence where the speaker paused as long as a piece boundary, inside one piece. See `Docs/cleanup.md`.
public struct PauseStopPass: PieceCleaningPass {
    public static let id: PassID = .pauseStop
    public static let laws: Set<PassLaw> = Set(PassLaw.allCases)
    public static let orderIndependentWith: Set<PassID> = [.spelledInitialism]

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
            guard let pause = draft.pause(before: next), pause >= Self.commaPause,
                !draft.words[index].isLayoutMark, !draft.words[next].isLayoutMark,
                draft.shape(at: index).suffix.isEmpty, !draft.shape(at: index).core.isEmpty
            else { continue }
            // A clause head the speaker set apart is a comma, whatever the length of the pause.
            if Self.heads.contains(draft.shape(at: index).core.lowercased()) {
                let following = draft.shape(at: next).core.lowercased()
                if !Self.carryOn.contains(following) {
                    draft.replace(at: index, with: draft.words[index].text + ",", by: Self.id)
                }
                continue
            }
            guard pause >= sentencePause else { continue }
            let before = live.prefix { $0 <= index }.map { draft.words[$0].text }.joined(separator: " ")
            let after = live.drop { $0 < next }.map { draft.words[$0].text }.joined(separator: " ")
            // The same evidence that keeps a seam's sentence going keeps this one going.
            guard !SentenceBoundaryEvidence.sentenceRunsOn(before, into: after) else { continue }
            draft.replace(at: index, with: WordShape.finished(draft.words[index].text), by: Self.id)
        }
        return draft
    }

    /// The silence that makes a clause head a pause rather than a breath: the pause that also ends a spoken tag.
    static let commaPause: Duration = .milliseconds(300)

    /// Words that head a clause of their own, so a pause after one is a comma: "sorry, was busy".
    private static let heads: Set<String> = ["sorry", "thanks", "done"]

    /// Words that take a head into its phrase, so no pause between them is a comma: "thanks for", "done with".
    private static let carryOn = FunctionWords.headCarryOns

    private static let prose: Set<Destination> = [.document, .messaging, .email, .plain]
}
