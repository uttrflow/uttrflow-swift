// Tests how the live path and a retry window the same recording.
import Foundation
import Testing
import UttrflowCore
import UttrflowEval

@Suite("RetryParity")
struct RetryParityTests {
    private let rate = 16_000

    /// Alternating tone and silence, the shape of sentences with pauses between them.
    private func passage(_ parts: [(seconds: Double, loud: Bool)]) -> [Float] {
        parts.flatMap { part in
            let count = Int(part.seconds * Double(rate))
            return part.loud
                ? (0..<count).map { Float(sin(Double($0) * 0.2)) * 0.3 } : [Float](repeating: 0, count: count)
        }
    }

    @Test func aRoundTripKeepsSixteenBitPrecision() {
        let samples: [Float] = [0, 0.5, -0.5, 1, -1, 2, 0.00001]
        let stored = RetryParity.roundTripped(samples)
        #expect(stored[0] == 0)
        #expect(abs(stored[1] - 0.5) < 1 / 32_767)
        #expect(stored[3] == 1)
        #expect(stored[5] == 1)
        #expect(stored[6] == 0)
    }

    @Test func piecesCoverTheWholeRecordingInOrder() {
        let samples = passage([
            (3, true), (1.2, false), (4, true), (1.2, false), (6, true), (0.9, false), (2, true),
        ])
        for pieces in [
            RetryParity.livePieces(samples, sampleRate: rate, pollSamples: rate),
            RetryParity.retryPieces(samples, sampleRate: rate),
        ] {
            #expect(pieces.first?.lowerBound == 0)
            #expect(pieces.last?.upperBound == samples.count)
            #expect(zip(pieces, pieces.dropFirst()).allSatisfy { $0.upperBound == $1.lowerBound })
            #expect(pieces.count > 1)
        }
    }

    @Test func aRecordingTooShortToCutIsOnePiece() {
        let samples = passage([(2, true)])
        #expect(RetryParity.livePieces(samples, sampleRate: rate, pollSamples: rate) == [0..<samples.count])
        #expect(RetryParity.retryPieces(samples, sampleRate: rate) == [0..<samples.count])
        #expect(RetryParity.livePieces(samples, sampleRate: rate, pollSamples: 0) == [0..<samples.count])
    }

    @Test func silenceIsStillOnePiece() {
        let samples = [Float](repeating: 0, count: rate)
        #expect(RetryParity.retryPieces(samples, sampleRate: rate) == [0..<samples.count])
    }
}
