// Tests that repeated cookie headers cost work in proportion to the text they contain.

import Testing

@testable import UttrflowClipboard
@testable import UttrflowCore

extension HeavyClipScans {
    @Suite("Cookie headers use bounded work", .bug(id: 3738))
    struct CookieHeaderScalingTests {
        @Test("Each character in repeated cookie headers costs a bounded number of reads")
        func repeatedHeadersReadLinearly() async {
            let texts = [1_024, 16_384].map { String(repeating: "Cookie: ", count: $0 / 8) }
            let reads = await offTheTestPool { texts.map(Self.charactersRead) }

            for (text, read) in zip(texts, reads) {
                #expect(read <= 64 * text.count, "\(text.count) characters took \(read) reads")
            }
        }

        @Test("A two-megabyte repeated cookie-header clip is classified within fifteen seconds")
        func largestClipIsClassifiedWithinBudget() async {
            let text = String(repeating: "Cookie: ", count: 250_000)
            let (kind, elapsed) = await offTheTestPool {
                let clock = ContinuousClock()
                let start = clock.now
                let kind = ClipKindDetector.kind(of: text)
                return (kind, start.duration(to: clock.now))
            }

            #expect(kind == .text)
            #expect(elapsed < .seconds(15))
        }

        private static func charactersRead(_ text: String) -> Int {
            let tally = ScanTally()
            SecretShapes.$tally.withValue(tally) { _ = SecretShapes.matches(text) }
            return tally.count
        }
    }
}
