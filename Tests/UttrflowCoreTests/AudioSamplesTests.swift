import Testing

@testable import UttrflowCore

@Suite("AudioSamples")
struct AudioSamplesTests {
    @Test("computes duration from sample count and rate")
    func duration() throws {
        let samples = try #require(
            AudioSamples(samples: Array(repeating: 0, count: 32_000), sampleRate: 16_000)
        )
        #expect(samples.duration == .seconds(2))
    }

    @Test("reports an empty buffer as zero-length rather than failing")
    func emptyBuffer() {
        #expect(AudioSamples.empty.isEmpty)
        #expect(AudioSamples.empty.duration == .zero)
        #expect(AudioSamples.empty.sampleRate == AudioSamples.canonicalSampleRate)
    }

    @Test("rejects a non-positive sample rate", arguments: [0, -1, -16_000])
    func rejectsInvalidSampleRate(rate: Int) {
        #expect(AudioSamples(samples: [0, 1], sampleRate: rate) == nil)
    }

    @Test("accepts a sample rate other than the canonical one")
    func acceptsOtherSampleRates() throws {
        let samples = try #require(AudioSamples(samples: [0, 0, 0], sampleRate: 48_000))
        #expect(samples.sampleRate == 48_000)
        #expect(!samples.isEmpty)
    }

    @Test("declares one sample rate for the whole pipeline")
    func canonicalRateIsWhisperCompatible() {
        #expect(AudioSamples.canonicalSampleRate == 16_000)
    }

    @Test("compares equal only when samples and rate both match")
    func equatable() throws {
        let a = try #require(AudioSamples(samples: [0.1, 0.2], sampleRate: 16_000))
        let b = try #require(AudioSamples(samples: [0.1, 0.2], sampleRate: 16_000))
        let differentRate = try #require(AudioSamples(samples: [0.1, 0.2], sampleRate: 48_000))
        let differentSamples = try #require(AudioSamples(samples: [0.1, 0.3], sampleRate: 16_000))

        #expect(a == b)
        #expect(a != differentRate)
        #expect(a != differentSamples)
    }
}
