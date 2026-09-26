// Tests building the system recogniser's input buffers from canonical samples.
import AVFoundation
import Testing

@testable import UttrflowSpeech

@Suite("Analyser input")
struct AnalyserInputTests {
    /// One second of a 440 Hz tone at the canonical rate.
    private let tone = (0..<16_000).map { Float(sin(2 * Double.pi * 440 * Double($0) / 16_000)) * 0.5 }

    @Test("copies canonical samples into a 16 kHz mono 16-bit buffer")
    func copiesInt16() throws {
        let format = try #require(
            AVAudioFormat(commonFormat: .pcmFormatInt16, sampleRate: 16_000, channels: 1, interleaved: true))
        let buffer = try #require(AnalyserInput.buffer(tone, format: format))
        #expect(buffer.frameLength == 16_000)
        let int16 = try #require(buffer.int16ChannelData)
        #expect(int16[0][100] == Int16(clampingAudioSample: tone[100]))
    }

    @Test("copies canonical samples into a 16 kHz mono float buffer unchanged")
    func copiesFloat() throws {
        let format = try #require(AnalyserInput.canonicalFormat)
        let buffer = try #require(AnalyserInput.buffer(tone, format: format))
        #expect(buffer.frameLength == 16_000)
        #expect(try #require(buffer.floatChannelData)[0][123] == tone[123])
    }

    @Test("resamples to the analyser's rate and fills every channel, keeping the whole clip")
    func convertsRateAndChannels() throws {
        let format = try #require(
            AVAudioFormat(
                commonFormat: .pcmFormatFloat32, sampleRate: 48_000, channels: 2, interleaved: false))
        let buffer = try #require(AnalyserInput.buffer(tone, format: format))
        // Within a few milliseconds of three times as many frames: nothing truncated past the converter's slice.
        #expect(abs(Int(buffer.frameLength) - 48_000) < 200)
        let channels = try #require(buffer.floatChannelData)
        for channel in 0..<2 {
            let energy = (1_000..<47_000).reduce(Float(0)) {
                $0 + channels[channel][$1] * channels[channel][$1]
            }
            #expect(energy > 1_000)
        }
    }

    @Test("resamples into 16-bit at another rate")
    func convertsToInt16() throws {
        let format = try #require(
            AVAudioFormat(commonFormat: .pcmFormatInt16, sampleRate: 8_000, channels: 1, interleaved: true))
        let buffer = try #require(AnalyserInput.buffer(tone, format: format))
        #expect(abs(Int(buffer.frameLength) - 8_000) < 100)
    }

    @Test("an empty clip becomes an empty buffer")
    func emptyClip() throws {
        let format = try #require(
            AVAudioFormat(
                commonFormat: .pcmFormatFloat32, sampleRate: 48_000, channels: 1, interleaved: false))
        #expect(AnalyserInput.buffer([], format: format)?.frameLength == 0)
    }
}
