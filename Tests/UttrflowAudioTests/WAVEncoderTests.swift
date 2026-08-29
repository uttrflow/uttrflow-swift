import Foundation
import Testing

@testable import UttrflowAudio
@testable import UttrflowCore

@Suite("WAVEncoder")
struct WAVEncoderTests {
    private func encode(_ samples: [Float]) -> Data {
        WAVEncoder.encode(.canonical(samples))
    }

    private func string(_ data: Data, _ range: Range<Int>) -> String {
        String(decoding: data[range], as: UTF8.self)
    }

    private func uint32(_ data: Data, at offset: Int) -> UInt32 {
        data[offset..<offset + 4].reversed().reduce(UInt32(0)) { ($0 << 8) | UInt32($1) }
    }

    private func uint16(_ data: Data, at offset: Int) -> UInt16 {
        data[offset..<offset + 2].reversed().reduce(UInt16(0)) { ($0 << 8) | UInt16($1) }
    }

    private func int16(_ data: Data, at offset: Int) -> Int16 {
        Int16(bitPattern: uint16(data, at: offset))
    }

    @Test("writes the chunk names a WAV reader looks for")
    func chunkNames() {
        let data = encode([0])
        #expect(string(data, 0..<4) == "RIFF")
        #expect(string(data, 8..<12) == "WAVE")
        #expect(string(data, 12..<16) == "fmt ")
        #expect(string(data, 36..<40) == "data")
    }

    @Test("declares 16-bit mono PCM at the canonical rate")
    func formatChunk() {
        let data = encode([0, 0])
        #expect(uint32(data, at: 16) == 16, "fmt chunk length")
        #expect(uint16(data, at: 20) == 1, "PCM format tag")
        #expect(uint16(data, at: 22) == 1, "channel count")
        #expect(uint32(data, at: 24) == UInt32(AudioSamples.canonicalSampleRate))
        #expect(uint32(data, at: 28) == UInt32(AudioSamples.canonicalSampleRate * 2), "byte rate")
        #expect(uint16(data, at: 32) == 2, "block align")
        #expect(uint16(data, at: 34) == 16, "bits per sample")
    }

    @Test("sizes both headers to match the payload")
    func sizesAgree() {
        let data = encode(Array(repeating: 0, count: 100))
        #expect(data.count == 44 + 200)
        #expect(uint32(data, at: 4) == UInt32(36 + 200), "RIFF size")
        #expect(uint32(data, at: 40) == 200, "data size")
    }

    @Test("writes a valid header for an empty recording")
    func emptyRecording() {
        let data = encode([])
        #expect(data.count == 44)
        #expect(uint32(data, at: 40) == 0)
        #expect(uint32(data, at: 4) == 36)
    }

    @Test(
        "scales normalised floats to the full 16-bit range",
        arguments: [
            (0, 0), (1.0, Int16.max), (-1.0, -Int16.max), (0.5, 16_384), (-0.5, -16_384),
        ] as [(Float, Int16)]
    )
    func scalesSamples(input: Float, expected: Int16) {
        #expect(int16(encode([input]), at: 44) == expected)
    }

    @Test("clamps out-of-range samples instead of wrapping them", arguments: [Float(1.4), -1.4, 9, -9])
    func clampsOutOfRange(input: Float) {
        let value = int16(encode([input]), at: 44)
        #expect(value == (input > 0 ? Int16.max : Int16.min))
    }

    @Test("writes silence for a non-finite sample", arguments: [Float.nan, .infinity, -.infinity])
    func nonFiniteBecomesSilence(input: Float) {
        #expect(int16(encode([input]), at: 44) == 0)
    }

    @Test("writes samples little-endian, in order")
    func sampleOrder() {
        let data = encode([1.0, -1.0])
        #expect(int16(data, at: 44) == Int16.max)
        #expect(int16(data, at: 46) == -Int16.max)
    }

    @Test("records whatever sample rate the audio actually carries")
    func honoursSampleRate() throws {
        let audio = try #require(AudioSamples(samples: [0], sampleRate: 44_100))
        #expect(uint32(WAVEncoder.encode(audio), at: 24) == 44_100)
    }
}
