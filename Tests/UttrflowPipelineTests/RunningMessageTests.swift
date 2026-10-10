// Tests that a dictation's seams are decided as its pieces arrive, so key-up does not decide them again.
import Testing

@testable import UttrflowAI
@testable import UttrflowCore
@testable import UttrflowPipeline

@Suite("A running message decides each seam as its piece arrives")
struct RunningMessageTests {
    private static let document = Situation(app: .unknown, insertion: .unknown, destination: .document)
    private static let chat = Situation(app: .unknown, insertion: .unknown, destination: .messaging)

    private static func piece(_ text: String) -> Piece {
        Piece(
            heard: Transcription(text: text), corrected: .unchanged(text),
            cleaned: TransformationResult(text: text, producedBy: .rules))
    }

    /// The words the draft's helpers read while `work` runs, which a seam decided earlier does not add to.
    private static func wordsRead(_ work: () -> Void) -> Int {
        let tally = WorkTally()
        Draft.$wordsRead.withValue(tally) { work() }
        return tally.count
    }

    @Test(
        "a folded seam answers with the joiner's verdict and reads no words",
        arguments: [
            ("the meeting starts at three", "thirty in the afternoon", true),
            ("send the report today", "and call me after lunch", false),
        ])
    func foldedSeam(head: String, tail: String, runs: Bool) {
        var message = RunningMessage()
        let folding = Self.wordsRead {
            message.fold(Self.piece(head), going: Self.document)
            message.fold(Self.piece(tail), going: Self.document)
        }
        var verdict = !runs
        let asking = Self.wordsRead {
            verdict = message.unitRunsAcross(head, into: tail, going: Self.document)
        }
        let joiner = PieceJoiner.unitRunsAcross(
            head, into: tail, under: .standard(for: Self.document), going: Self.document)
        #expect(folding > 0)
        #expect(asking == 0)
        #expect(verdict == runs)
        #expect(joiner == runs)
        #expect(message.pieces.map(\.corrected.text) == [head, tail])
    }

    @Test("a seam never folded, or folded for another place, is decided when it is asked about")
    func unfoldedSeam() {
        var message = RunningMessage()
        message.fold(Self.piece("the meeting starts at three"), going: Self.document)
        message.fold(Self.piece("thirty in the afternoon"), going: Self.document)
        let later = Self.wordsRead {
            _ = message.unitRunsAcross("thirty in the afternoon", into: "see you then", going: Self.document)
        }
        let elsewhere = Self.wordsRead {
            _ = message.unitRunsAcross(
                "the meeting starts at three", into: "thirty in the afternoon", going: Self.chat)
        }
        #expect(later > 0)
        #expect(elsewhere > 0)
    }

    @Test("the pieces taken over at key-up keep the seams decided while the key was held")
    func keepsEarlierVerdicts() {
        let pieces = ["the meeting starts at three", "thirty in the afternoon", "see you then"]
            .map(Self.piece)
        var early = RunningMessage()
        for piece in pieces.dropLast() { early.fold(piece, going: Self.document) }
        let released = RunningMessage(pieces, keeping: early)
        let heldSeam = Self.wordsRead {
            _ = released.unitRunsAcross(
                pieces[0].corrected.text, into: pieces[1].corrected.text, going: Self.document)
        }
        #expect(heldSeam == 0)
        #expect(released.pieces.map(\.corrected.text) == pieces.map(\.corrected.text))
    }
}
