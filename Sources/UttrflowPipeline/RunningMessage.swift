// The pieces of one dictation with the seams between them decided as each piece arrived. See `Docs/early-transcription.md`.
import UttrflowAI
import UttrflowCore

/// The pieces of one dictation and the seams already decided between them, so key-up decides only the seams it has not seen.
struct RunningMessage: Sendable {
    /// The words either side of one seam, which are all a seam's verdict is read from.
    private struct Seam: Hashable {
        let head: String
        let tail: String
    }

    /// Where the verdicts were reached, since the same words read differently somewhere else.
    private struct Verdicts: Sendable {
        let situation: Situation
        var unitRuns: [Seam: Bool] = [:]
    }

    private(set) var pieces: [Piece]
    private var verdicts: Verdicts?

    /// These pieces, keeping whatever `earlier` decided about the seams they share with it.
    init(_ pieces: [Piece] = [], keeping earlier: RunningMessage? = nil) {
        self.pieces = pieces
        verdicts = earlier?.verdicts
    }

    /// Takes the next piece, deciding the seam it makes with the piece before while there is time to.
    mutating func fold(_ piece: Piece, going situation: Situation) {
        if verdicts?.situation != situation { verdicts = Verdicts(situation: situation) }
        if let last = pieces.last {
            let seam = Seam(head: last.corrected.text, tail: piece.corrected.text)
            verdicts?.unitRuns[seam] = Self.unitRuns(across: seam, going: situation)
        }
        pieces.append(piece)
    }

    /// Whether a spoken unit runs across the seam, as decided while the key was held or, for a seam not seen, now.
    func unitRunsAcross(_ head: String, into tail: String, going situation: Situation) -> Bool {
        let seam = Seam(head: head, tail: tail)
        if verdicts?.situation == situation, let known = verdicts?.unitRuns[seam] { return known }
        return Self.unitRuns(across: seam, going: situation)
    }

    /// The joiner's own verdict on one seam, the only place a verdict is reached.
    private static func unitRuns(across seam: Seam, going situation: Situation) -> Bool {
        PieceJoiner.unitRunsAcross(
            seam.head, into: seam.tail, under: .standard(for: situation), going: situation)
    }
}
