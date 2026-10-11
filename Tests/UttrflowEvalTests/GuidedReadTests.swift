// Tests what one reading of the guided passage measures: rate, pauses inside sentences, confidence and missed terms.
import Testing
import UttrflowCore

@testable import UttrflowEval

@Suite("The guided read")
struct GuidedReadTests {
    /// The passage as heard word by word, each 0.3 s long, `gap` apart, with `swap` replacing heard words.
    private func reading(
        gap: Double = 0.1, confidence: Double = 0.9, timed: Bool = true, swap: [String: String] = [:]
    ) -> [TranscribedWord] {
        GuidedRead.passage.split(separator: " ").enumerated().map { index, text in
            let start = Double(index) * (0.3 + gap)
            return TranscribedWord(
                text: swap[String(text)] ?? String(text), confidence: confidence,
                start: timed ? .milliseconds(Int((start * 1000).rounded())) : nil,
                end: timed ? .milliseconds(Int(((start + 0.3) * 1000).rounded())) : nil)
        }
    }

    @Test("the passage is Latin script and holds the lexicon's terms in the order read")
    func passage() {
        #expect(LatinScript.writesOnlyLatin(GuidedRead.passage))
        #expect(
            GuidedRead.measure([]).targets == [
                "grep", "sed", "awk", "api", "dns", "csv", "pdf", "ssh", "config", "cron", "mv", "mkdir",
                "git",
                "regex", "repo", "pytest", "cpu",
            ])
    }

    @Test("a reading heard as read misses nothing and reports its rate, pauses and confidence")
    func exact() throws {
        let words = reading()
        let read = GuidedRead.measure(words)
        #expect(read.missedTargets.isEmpty)
        let rate = try #require(read.wordsPerMinute)
        let expected = Double(words.count) / ((Double(words.count) * 0.4 - 0.1) / 60)
        #expect(abs(rate - expected) < 0.001)
        #expect(abs((read.medianPause ?? 0) - 0.1) < 0.000_001)
        #expect(abs((read.longPause ?? 0) - 0.1) < 0.000_001)
        #expect(read.medianConfidence == 0.9)
        #expect(read.pauses == .usual)
    }

    @Test("a technical word heard as an everyday one is missed, and only that one")
    func missed() {
        let read = GuidedRead.measure(reading(swap: ["sed": "said"]))
        #expect(read.missedTargets == ["sed"])
    }

    @Test("the gap after a word that closes a sentence is no pause inside a sentence")
    func sentenceEnds() throws {
        var words = reading()
        let closing = try #require(words.firstIndex { $0.text.hasSuffix(".") })
        let end = try #require(words[closing].end)
        let next = words[closing + 1]
        words[closing + 1] = TranscribedWord(
            text: next.text, confidence: next.confidence, start: end + .seconds(5), end: end + .seconds(6))
        #expect(GuidedRead.measure(words).longPause.map { $0 < 1 } == true)
    }

    @Test(
        "the pause setting is the first whose sentence pause the long gap stays under",
        arguments: [(0.5, PauseLength.usual), (1.0, .long), (3.0, .veryLong)])
    func setting(gap: Double, expected: PauseLength) {
        #expect(GuidedRead.measure(reading(gap: gap)).pauses == expected)
    }

    @Test("an untimed reading has no rate, no pauses and no pause setting")
    func untimed() {
        let read = GuidedRead.measure(reading(timed: false))
        #expect(read.wordsPerMinute == nil)
        #expect(read.longPause == nil)
        #expect(read.pauses == nil)
        #expect(read.missedTargets.isEmpty)
    }
}
