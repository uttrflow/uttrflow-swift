import AVFoundation
import Testing

@testable import UttrflowAudio
@testable import UttrflowCore

@Suite("AudioResampler")
struct AudioResamplerTests {
    @Test("targets the one format the rest of the pipeline expects")
    func canonicalFormat() throws {
        let format = try #require(AudioResampler.canonicalFormat)
        #expect(format.sampleRate == Double(AudioSamples.canonicalSampleRate))
        #expect(format.channelCount == 1)
        #expect(format.commonFormat == .pcmFormatFloat32)
    }

    @Test(
        "downsamples to the canonical rate from whatever the microphone offers",
        arguments: [44_100.0, 48_000.0, 96_000.0]
    )
    func downsamplesToCanonicalRate(inputRate: Double) throws {
        let format = try #require(SyntheticAudio.format(sampleRate: inputRate, channels: 1))
        let resampler = try #require(AudioResampler(inputFormat: format))
        let frames = AVAudioFrameCount(inputRate)  // exactly one second
        let buffer = try #require(SyntheticAudio.tone(frequency: 440, frames: frames, format: format))

        let samples = try resampler.resample(buffer)

        // One second in must be about one second out; converters trim a few frames of
        // filter latency, so this checks the ratio rather than an exact count.
        let expected = Double(AudioSamples.canonicalSampleRate)
        #expect(
            abs(Double(samples.count) - expected) < expected * 0.02,
            "got \(samples.count) samples from 1s at \(inputRate) Hz")
    }

    @Test("upsamples when the microphone runs slower than the canonical rate")
    func upsamples() throws {
        let format = try #require(SyntheticAudio.format(sampleRate: 8_000, channels: 1))
        let resampler = try #require(AudioResampler(inputFormat: format))
        let buffer = try #require(SyntheticAudio.tone(frequency: 220, frames: 8_000, format: format))

        let samples = try resampler.resample(buffer)
        #expect(samples.count > 15_000)
    }

    /// Above stereo the converter has no layout to mix down with and yields silence
    /// unless told which channel to take — a dead microphone on a 4-input interface.
    @Test(
        "mixes any microphone down to audible mono",
        arguments: [1, 2, 4, 6] as [AVAudioChannelCount]
    )
    func mixesToMono(channels: AVAudioChannelCount) throws {
        let format = try #require(SyntheticAudio.format(sampleRate: 48_000, channels: channels))
        let resampler = try #require(AudioResampler(inputFormat: format))
        let buffer = try #require(SyntheticAudio.constant(0.5, frames: 4_800, format: format))

        let samples = try resampler.resample(buffer)

        #expect(!samples.isEmpty)
        // Every channel held the same value, so the mix must hold it too — a mixdown
        // that summed instead of averaging would clip here.
        let loudest = samples.map(abs).max() ?? 0
        #expect(loudest <= 1.0)
        #expect(loudest > 0.3)
    }

    @Test("preserves a signal rather than merely producing the right sample count")
    func preservesSignal() throws {
        let format = try #require(SyntheticAudio.format(sampleRate: 48_000, channels: 1))
        let resampler = try #require(AudioResampler(inputFormat: format))
        let buffer = try #require(
            SyntheticAudio.tone(frequency: 440, frames: 48_000, format: format, amplitude: 0.5)
        )

        let samples = try resampler.resample(buffer)
        let peak = samples.map(abs).max() ?? 0

        #expect(peak > 0.4 && peak < 0.6, "amplitude drifted to \(peak)")
    }

    @Test("keeps silence silent")
    func silenceStaysSilent() throws {
        let format = try #require(SyntheticAudio.format(sampleRate: 48_000, channels: 1))
        let resampler = try #require(AudioResampler(inputFormat: format))
        let buffer = try #require(SyntheticAudio.constant(0, frames: 4_800, format: format))

        let samples = try resampler.resample(buffer)
        #expect(samples.allSatisfy { $0 == 0 })
    }

    @Test("passes canonical-format audio through unchanged")
    func canonicalInputIsIdentity() throws {
        let format = try #require(AudioResampler.canonicalFormat)
        let resampler = try #require(AudioResampler(inputFormat: format))
        let buffer = try #require(SyntheticAudio.constant(0.25, frames: 1_600, format: format))

        let samples = try resampler.resample(buffer)
        #expect(samples.count == 1_600)
        #expect(samples.allSatisfy { abs($0 - 0.25) < 0.001 })
    }

    @Test("returns nothing for an empty buffer instead of failing")
    func emptyBuffer() throws {
        let format = try #require(SyntheticAudio.format(sampleRate: 48_000, channels: 1))
        let resampler = try #require(AudioResampler(inputFormat: format))
        let buffer = try #require(AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 512))
        buffer.frameLength = 0

        #expect(try resampler.resample(buffer).isEmpty)
    }

    @Test("handles interleaved input, which some devices deliver")
    func interleavedInput() throws {
        let format = try #require(
            SyntheticAudio.format(sampleRate: 48_000, channels: 2, interleaved: true)
        )
        let resampler = try #require(AudioResampler(inputFormat: format))
        let buffer = try #require(AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 4_800))
        buffer.frameLength = 4_800

        #expect(try resampler.resample(buffer).isEmpty == false)
    }
}

@Suite("AudioResampler misuse")
struct AudioResamplerMisuseTests {
    @Test("reports a failure rather than corrupt audio when handed the wrong format")
    func mismatchedBufferFormat() throws {
        let configured = try #require(SyntheticAudio.format(sampleRate: 48_000, channels: 1))
        let resampler = try #require(AudioResampler(inputFormat: configured))

        let other = try #require(SyntheticAudio.format(sampleRate: 22_050, channels: 2))
        let buffer = try #require(SyntheticAudio.constant(0.5, frames: 1_024, format: other))

        // Assert the specific failure: a test that merely expects "some error" would
        // pass even if this failed for an unrelated reason.
        let thrown = #expect(throws: AudioCaptureError.self) { try resampler.resample(buffer) }
        guard case .engineFailed = thrown else {
            Issue.record("expected engineFailed, got \(String(describing: thrown))")
            return
        }
    }
}
