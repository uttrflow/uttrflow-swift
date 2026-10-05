// Counted-work bounds for the audio analyses that run every second while recording.

import Foundation
import Testing

@testable import UttrflowCore

/// Phrases and pauses at the length of a short and a long dictation.
private enum Recording {
    static let rate = 16_000

    /// Two seconds of swelling tone then 0.6 s of silence, repeated to `seconds`.
    static func phrases(_ seconds: Int) -> [Float] {
        let phrase = Int(2.0 * Double(rate))
        let pause = Int(0.6 * Double(rate))
        let count = seconds * rate
        return (0..<count).map { index in
            guard index % (phrase + pause) < phrase else { return 0 }
            let time = Double(index) / Double(rate)
            let envelope = Float(0.7 + 0.3 * sin(2 * .pi * 3 * time))
            return 0.3 * envelope * Float(sin(2 * .pi * 180 * time))
        }
    }

    /// Samples the analyses read while `work` runs.
    static func samplesRead(_ work: () -> Void) -> Int {
        let tally = WorkTally()
        VoiceActivity.$samplesRead.withValue(tally) { work() }
        return tally.count
    }
}

@Suite("Audio analysis scaling")
struct AudioAnalysisScalingTests {
    static let short = Recording.phrases(30)
    static let long = Recording.phrases(240)

    @Test("finding the speech reads each sample at most once, so 8x the audio is at most 8x the work")
    func speechRangeIsLinear() {
        let short = Recording.samplesRead {
            _ = VoiceActivity.speechRange(in: Self.short, sampleRate: Recording.rate)
        }
        let long = Recording.samplesRead {
            _ = VoiceActivity.speechRange(in: Self.long, sampleRate: Recording.rate)
        }
        #expect(short > 0)
        #expect(short <= Self.short.count)
        #expect(long <= Self.long.count)
        #expect(long <= short * 8)
    }

    @Test("one cut reads no more of a 240 s recording than of a 30 s one, since a window never passes 30 s")
    func nextCutIsBoundedByTheWindow() {
        let windowing = SpeechWindowing.standard
        let short = Recording.samplesRead {
            _ = windowing.nextCut(in: Self.short, sampleRate: Recording.rate, from: 0)
        }
        let long = Recording.samplesRead {
            _ = windowing.nextCut(in: Self.long, sampleRate: Recording.rate, from: 0)
        }
        #expect(short > 0)
        #expect(long <= short)
        #expect(long <= Int(windowing.maximumLength) * Recording.rate * 2)
    }

    @Test("cutting a whole recording into windows reads each sample a bounded number of times")
    func windowsAreLinear() {
        let windowing = SpeechWindowing.standard
        let short = Recording.samplesRead {
            _ = windowing.windows(in: Self.short, sampleRate: Recording.rate)
        }
        let long = Recording.samplesRead {
            _ = windowing.windows(in: Self.long, sampleRate: Recording.rate)
        }
        #expect(short > 0)
        #expect(long <= Self.long.count * 6)
        #expect(long <= short * 8 * 3 / 2)
    }
}
