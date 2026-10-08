// The stage-by-stage account of a dictation tidied in pieces and joined, as `uttrflow-dev explain --pieces` prints it.
import UttrflowAI
import UttrflowCore

/// What each piece and the join did to one dictation's words. See `Docs/dictation-trace.md`.
public struct PieceTrace: Sendable {
    /// Each recognised piece through the dictionary and the tidier, before any piece was joined.
    let pieces: [Piece]
    /// What the join made of them; nil when nothing writable was left.
    let joined: JoinedDictation?
    /// The text the dictation would insert, or nil when it would refuse it as silence.
    public let text: String?

    /// The account, one labelled line per fact, each piece in order and then the join.
    public var lines: [String] {
        pieces.enumerated().flatMap { index, piece in Self.rows(of: piece, numbered: index + 1) }
            + joinRows
            + [DictationExplanation.row("result", text.map(DictationExplanation.shown) ?? "nothing writable")]
    }

    private static func rows(of piece: Piece, numbered number: Int) -> [String] {
        let corrected =
            piece.corrected.text == piece.heard.text
            ? [] : [DictationExplanation.row("dictionary", piece.corrected.text)]
        return [DictationExplanation.row("piece \(number)", piece.heard.text)] + corrected
            + DictationExplanation.cleaningRows(of: piece.cleaned)
            + [
                DictationExplanation.row("tidied by", piece.cleaned.producedBy.rawValue),
                DictationExplanation.row("tidied", DictationExplanation.shown(piece.cleaned.text)),
            ]
    }

    /// The stages that read the pieces together, each shown only where it changed the words.
    private var joinRows: [String] {
        guard let joined else { return [] }
        let rejoined =
            joined.rejoined.count == pieces.count
            ? []
            : joined.rejoined.map {
                DictationExplanation.row("rejoined", DictationExplanation.shown($0.cleaned.text))
            }
        let laid = joined.laid.cleaned.text
        let acrossSeams = joined.acrossSeams.cleaned.text
        let atSeams =
            acrossSeams == laid ? [] : [DictationExplanation.row("at seams", DictationExplanation.shown(acrossSeams))]
        return rejoined + [DictationExplanation.row("joined", DictationExplanation.shown(laid))] + atSeams
            + [DictationExplanation.row("message", DictationExplanation.shown(joined.whole.cleaned.text))]
    }
}
