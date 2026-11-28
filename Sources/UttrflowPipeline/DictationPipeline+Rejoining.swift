// Rejoining the pieces of one dictation: the adapter's single choice and the units a pause cut.
import UttrflowAI
import UttrflowCore

extension DictationPipeline {
    /// The adapter is chosen once, from every corrected word: a dictation that reads as notation is tidied once as one text, and otherwise a spoken number, time, address or quotation cut by a pause is tidied again as one piece so the unit is read whole.
    func rejoiningUnits(
        _ pieces: [Piece], using message: RunningMessage, under formatter: DestinationFormatter,
        going situation: Situation, seeing appContext: AppContext,
        recording metrics: any MetricsRecording, for mine: Int?
    ) async -> [Piece] {
        if !pieces.isEmpty,
            NotationEvidence.writesNotation(
                in: pieces.map(\.corrected.text).joined(separator: " "), situation: situation)
        {
            let whole = PieceJoiner.join(pieces, under: formatter)
            let cleaned = await tidy(
                whole.heard, saying: whole.corrected, seeing: appContext, as: .notated,
                recording: metrics, for: mine)
            // A tidy that gave up returns the raw words, which would throw away what the pieces already finished.
            guard cleaned.producedBy != .untidied else { return pieces }
            return [Piece(heard: whole.heard, corrected: whole.corrected, cleaned: cleaned)]
        }
        var groups: [[Piece]] = []
        for piece in pieces {
            if let previous = groups.last?.last,
                message.unitRunsAcross(previous.corrected.text, into: piece.corrected.text, going: situation)
                    || PieceJoiner.quotationRunsAcross(previous.cleaned.text, into: piece.cleaned.text)
            {
                groups[groups.count - 1].append(piece)
            } else {
                groups.append([piece])
            }
        }
        guard groups.count < pieces.count else { return pieces }
        var rejoined: [Piece] = []
        for group in groups {
            guard group.count > 1 else {
                rejoined += group
                continue
            }
            let whole = PieceJoiner.join(group, under: formatter)
            let cleaned = await tidy(
                whole.heard, saying: whole.corrected, seeing: appContext, recording: metrics, for: mine)
            rejoined.append(Piece(heard: whole.heard, corrected: whole.corrected, cleaned: cleaned))
        }
        return rejoined
    }
}
