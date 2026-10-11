import Testing

@testable import UttrflowPipeline

@Suite("The too-loud input threshold")
struct InputTooLoudTests {
    @Test("a recording below the measured cliff never shows the notice, and one at it does")
    func thresholdBoundary() {
        #expect(!InputTooLoud.isTooLoud(clippedFraction: 0))
        #expect(!InputTooLoud.isTooLoud(clippedFraction: 0.0646))
        #expect(!InputTooLoud.isTooLoud(clippedFraction: 0.1039))
        #expect(!InputTooLoud.isTooLoud(clippedFraction: InputTooLoud.clippedFractionThreshold - 0.001))
        #expect(InputTooLoud.isTooLoud(clippedFraction: InputTooLoud.clippedFractionThreshold))
        #expect(InputTooLoud.isTooLoud(clippedFraction: 0.2098))
    }
}
