import Testing
import UttrflowCore

@testable import UttrflowPipeline

/// A long dictation over three unrelated subjects, cut into pieces at every pause, whose only sign of a new subject is a longer pause.
@Suite("PieceJoiner subject pauses over a long dictation")
struct PieceJoinerSubjectPauseTests {
    /// Each piece as the cleaner returns it, and the quiet before it: 1.5 s between sentences, 2.5 s between subjects, 1 s inside a sentence.
    static let pieces: [(text: String, pause: Double)] = [
        ("The offsite went well on the whole.", 0),
        ("Most of the team came for both days", 1.5),
        ("and the sessions ran on time.", 1.0),
        ("The venue asked us to confirm the date for next year by the end of the month.", 1.5),
        ("I am not sure whether any of this is worth raising with the leadership group.", 1.5),
        ("The sync service retries failed uploads three times before it gives up.", 2.5),
        ("Each retry waits twice as long as the one before.", 1.5),
        ("We saw the queue grow during the outage", 1.5),
        ("because every client retried at once.", 1.0),
        ("Adding jitter to the wait should spread them out.", 1.5),
        ("My garden is finally coming back after the frost.", 2.5),
        ("The roses lost most of their leaves", 1.5),
        ("but the new shoots look healthy.", 1.0),
        ("I will plant the herbs out next weekend.", 1.5),
    ]

    static let expected = """
        The offsite went well on the whole. Most of the team came for both days and the sessions ran on time. \
        The venue asked us to confirm the date for next year by the end of the month. \
        I am not sure whether any of this is worth raising with the leadership group.

        The sync service retries failed uploads three times before it gives up. \
        Each retry waits twice as long as the one before. We saw the queue grow during the outage \
        because every client retried at once. Adding jitter to the wait should spread them out.

        My garden is finally coming back after the frost. The roses lost most of their leaves \
        but the new shoots look healthy. I will plant the herbs out next weekend.
        """

    private func laid(_ pieces: [(text: String, pause: Double)], _ destination: Destination) -> String {
        PieceJoiner.laidOut(
            pieces.map(\.text), under: .standard(for: destination), pauses: pieces.map { .seconds($0.pause) })
    }

    @Test("breaks a paragraph at each subject's longer pause, and nowhere else", arguments: [Destination.document, .email])
    func breaksAtSubjects(destination: Destination) {
        #expect(laid(Self.pieces, destination) == Self.expected)
    }

    @Test("writes no break where every pause between sentences is the same length")
    func evenPausesKeepOneParagraph() {
        let even = Self.pieces.map { (text: $0.text, pause: $0.pause == 2.5 ? 1.5 : $0.pause) }
        #expect(!laid(even, .document).contains("\n"))
    }
}
