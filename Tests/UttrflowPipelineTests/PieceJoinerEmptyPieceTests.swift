import Testing
import UttrflowCore

@testable import UttrflowPipeline

@Suite("PieceJoiner empty and single pieces")
struct PieceJoinerEmptyPieceTests {
    private func joined(_ pieces: [String], _ destination: Destination) -> String {
        PieceJoiner.laidOut(pieces, under: .standard(for: destination))
    }

    private func laid(_ pieces: [String], pauses: [Double]) -> String {
        PieceJoiner.laidOut(pieces, under: .standard(for: .email), pauses: pauses.map { .seconds($0) })
    }

    @Test("skips a piece the tidier left empty or blank, and joins the rest as if it were absent")
    func skipsEmptyPieces() {
        #expect(joined(["Hello there.", "", "  ", "Goodbye."], .plain) == "Hello there. Goodbye.")
    }

    @Test("returns the one remaining piece as it is, with no list or paragraph layout")
    func singlePieceIsReturnedAsIs() {
        #expect(joined(["", "Only this one.", " "], .document) == "Only this one.")
        #expect(joined(["Only this one."], .email) == "Only this one.")
    }

    @Test("returns nothing for no pieces, or pieces that are all blank")
    func noPiecesIsEmpty() {
        #expect(joined([], .plain).isEmpty)
        #expect(joined(["", "  ", "\n"], .plain).isEmpty)
    }

    @Test("hands the pause owed by a blank piece on, so it adds to the next piece's pause")
    func blankPieceHandsItsPauseOn() {
        let pieces = ["We shipped the sync fix.", "", "The retry service now backs off."]
        // 1.5 s before the blank piece and 0.6 s before the next make 2.1 s, past the 2 s that sets a subject apart.
        #expect(
            laid(pieces, pauses: [0, 1.5, 0.6])
                == "We shipped the sync fix.\n\nThe retry service now backs off.")
        // Without the blank piece's 1.5 s the 0.6 s alone is an ordinary pause.
        #expect(
            laid(pieces, pauses: [0, 0, 0.6])
                == "We shipped the sync fix. The retry service now backs off.")
    }
}
