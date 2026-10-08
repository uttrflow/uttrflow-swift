// Times the passes that run over the whole joined text after key release, against dictation length.
import Foundation
import Testing

@testable import UttrflowAI
@testable import UttrflowCore
@testable import UttrflowPipeline

/// The post-release whole-text chain at 30, 120 and 300 seconds of speech; prints one WHOLETEXT line per length.
@Suite("Whole-text cost against dictation length")
struct WholeTextCostProbeTests {
    /// Invented sentences, about twelve words each, the size of one five-second piece at 150 words a minute.
    private static let sentences = [
        "so the plan for next week is to finish the import screen first",
        "then we check the numbers with the team on tuesday after lunch",
        "the a p i returns the list in pages of fifty items each time",
        "we should also write down what happens when the network drops out",
        "after that the settings page needs one more pass for the labels",
        "remind me to send the draft to the reviewers before friday evening",
    ]

    /// Pieces for `seconds` of speech, one per five seconds.
    private static func pieces(seconds: Int) -> [Piece] {
        (0..<(seconds / 5)).map { index in
            let text = sentences[index % sentences.count]
            return Piece(
                heard: Transcription(text: text), corrected: .unchanged(text),
                cleaned: TransformationResult(text: text, producedBy: .rules))
        }
    }

    /// The median of `runs` timings of `work`, in milliseconds.
    private static func medianMilliseconds(runs: Int = 7, _ work: () -> Void) -> Double {
        let clock = ContinuousClock()
        let timings = (0..<runs).map { _ in
            let elapsed = clock.measure(work)
            return Double(elapsed.components.attoseconds) / 1e15 + Double(elapsed.components.seconds) * 1e3
        }.sorted()
        return timings[timings.count / 2]
    }

    @Test("prints the cost of joining, finishing the message and the Latin check", arguments: [30, 120, 300])
    func wholeTextCost(seconds: Int) {
        let formatter = DestinationFormatter.standard(for: .document)
        let pieces = Self.pieces(seconds: seconds)
        let joined = PieceJoiner.join(pieces, under: formatter)
        let message = CleaningPipeline.message(for: formatter, situation: .unknown)
        let finished = message.run(Draft(keepingLineBreaks: joined.cleaned.text)).text

        let join = Self.medianMilliseconds { _ = PieceJoiner.join(pieces, under: formatter) }
        let finish = Self.medianMilliseconds {
            _ = message.run(Draft(keepingLineBreaks: joined.cleaned.text))
        }
        let latin = Self.medianMilliseconds { _ = LatinScript.enforced(finished) }
        let words = finished.split(separator: " ").count
        print(
            "WHOLETEXT seconds=\(seconds) words=\(words) join=\(String(format: "%.2f", join))ms "
                + "message=\(String(format: "%.2f", finish))ms latin=\(String(format: "%.2f", latin))ms")
        #expect(words >= seconds * 2)
    }
}
