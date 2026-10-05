// Measures what the resampler does to a signal, not only how many samples it returns.
import AVFoundation
import Foundation
import Testing

@testable import UttrflowAudio
@testable import UttrflowCore

/// The fidelity matrix behind the table in Docs/audio-capture.md; its floors are the measured highest quality, so a regression fails.
@Suite("AudioResampler fidelity")
struct AudioResamplerFidelityTests {
    static let inputRates: [Double] = [8_000, 16_000, 22_050, 44_100, 48_000, 88_200, 96_000, 192_000]
    static let layouts: [Layout] = [
        Layout(channels: 1, interleaved: false), Layout(channels: 2, interleaved: false),
        Layout(channels: 2, interleaved: true), Layout(channels: 9, interleaved: false),
    ]
    /// Passband probes from the issue's 100 Hz to 7 kHz band.
    static let passbandTones: [Double] = [100, 1_000, 4_000, 7_000]
    /// Stopband probes above the canonical Nyquist, each used only where the input can carry it.
    static let stopbandTones: [Double] = [9_000, 10_000, 12_000, 16_000, 20_000]
    static let floorDecibels = -200.0

    struct Layout: CustomStringConvertible, Sendable {
        let channels: AVAudioChannelCount
        let interleaved: Bool
        var description: String { "\(channels)ch\(interleaved ? " interleaved" : "")" }
    }

    struct Row {
        let lengthError: Double
        let passbandSpread: Double
        let worstAlias: Double?
    }

    /// The worst alias the converter's highest quality reaches, per input rate, with a few dB of headroom.
    static let aliasCeilings: [Double: Double] = [
        22_050: -100, 44_100: -100, 48_000: -95, 88_200: -25, 96_000: -22, 192_000: -10,
    ]

    @Test(
        "every input rate and layout keeps length, passband and stopband within their floors",
        arguments: inputRates)
    func matrix(inputRate: Double) throws {
        for layout in Self.layouts {
            let row = try Self.measure(inputRate: inputRate, layout: layout)
            print(Self.line(inputRate: inputRate, layout: layout, row: row))
            #expect(row.lengthError < 0.005, "\(inputRate) \(layout): length error \(row.lengthError)")
            #expect(
                row.passbandSpread < 6, "\(inputRate) \(layout): passband spread \(row.passbandSpread) dB")
            if let alias = row.worstAlias {
                let ceiling = try #require(Self.aliasCeilings[inputRate])
                #expect(alias < ceiling, "\(inputRate) \(layout): alias \(alias) dB")
            }
        }
    }

    @Test("the production resampler runs at the converter's highest quality")
    func highestQuality() throws {
        let row = try Self.measure(inputRate: 48_000, layout: Layout(channels: 1, interleaved: false))
        let alias = try #require(row.worstAlias)
        #expect(alias < -95, "default quality leaks about -19 dB here; got \(alias) dB")
    }

    @Test("CPU cost per second of 48 kHz audio")
    func cpuCost() throws {
        let format = try #require(SyntheticAudio.format(sampleRate: 48_000, channels: 1))
        let tone = try #require(SyntheticAudio.tone(frequency: 1_000, frames: 4_096, format: format))
        let seconds = 60.0
        let blocks = Int(seconds * 48_000 / 4_096)
        let resampler = try #require(AudioResampler(inputFormat: format))
        let start = Date()
        for _ in 0..<blocks { _ = try resampler.resample(tone) }
        let perAudioSecond = Date().timeIntervalSince(start) / seconds * 1e6
        print("resampler-cpu: \(perAudioSecond) µs per audio second")
    }

    static func line(inputRate: Double, layout: Layout, row: Row) -> String {
        let alias = row.worstAlias.map { String(format: "%.1f", $0) } ?? "n/a"
        return String(
            format: "resampler-fidelity %.0f Hz %@: length %.4f%% passband ±%.3f dB alias %@ dB",
            inputRate, layout.description, row.lengthError * 100, row.passbandSpread / 2, alias)
    }

    static func resampler(format: AVAudioFormat) -> ((AVAudioPCMBuffer) throws -> [Float])? {
        guard let resampler = AudioResampler(inputFormat: format) else { return nil }
        return { try resampler.resample($0) }
    }

    static func measure(inputRate: Double, layout: Layout) throws -> Row {
        let format = try #require(
            SyntheticAudio.format(
                sampleRate: inputRate, channels: layout.channels, interleaved: layout.interleaved))
        let frames = AVAudioFrameCount(inputRate)
        let nyquist = inputRate / 2

        var gains: [Double] = []
        var lengthError = 0.0
        for frequency in passbandTones where frequency < nyquist * 0.9 {
            let convert = try #require(resampler(format: format))
            let input = try #require(tone(frequency: frequency, frames: frames, format: format))
            let output = try convert(input)
            lengthError = max(
                lengthError, abs(Double(output.count) / Double(AudioSamples.canonicalSampleRate) - 1))
            gains.append(decibels(rms(steady(output)) / (0.5 / 2.0.squareRoot())))
        }
        var aliases: [Double] = []
        for frequency in stopbandTones where frequency < nyquist * 0.9 {
            let convert = try #require(resampler(format: format))
            let input = try #require(tone(frequency: frequency, frames: frames, format: format))
            aliases.append(decibels(rms(steady(try convert(input))) / (0.5 / 2.0.squareRoot())))
        }
        return Row(
            lengthError: lengthError,
            passbandSpread: (gains.max() ?? 0) - (gains.min() ?? 0),
            worstAlias: aliases.max())
    }

    /// A 0.5 amplitude sine on channel 0 only, silence elsewhere, in either layout.
    static func tone(frequency: Double, frames: AVAudioFrameCount, format: AVAudioFormat) -> AVAudioPCMBuffer?
    {
        guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frames) else { return nil }
        buffer.frameLength = frames
        let channels = Int(format.channelCount)
        let lists = UnsafeMutableAudioBufferListPointer(buffer.mutableAudioBufferList)
        for list in lists {
            guard let data = list.mData else { return nil }
            memset(data, 0, Int(list.mDataByteSize))
        }
        guard let first = lists[0].mData?.assumingMemoryBound(to: Float.self) else { return nil }
        let stride = format.isInterleaved ? channels : 1
        let step = 2 * Double.pi * frequency / format.sampleRate
        for frame in 0..<Int(frames) {
            first[frame * stride] = 0.5 * Float(sin(step * Double(frame)))
        }
        return buffer
    }

    /// The middle half, away from the filter's start-up and tail.
    static func steady(_ samples: [Float]) -> ArraySlice<Float> {
        samples[(samples.count / 4)..<(samples.count * 3 / 4)]
    }

    static func rms(_ samples: ArraySlice<Float>) -> Double {
        guard !samples.isEmpty else { return 0 }
        return (samples.reduce(0.0) { $0 + Double($1) * Double($1) } / Double(samples.count)).squareRoot()
    }

    static func decibels(_ ratio: Double) -> Double {
        ratio > 0 ? 20 * log10(ratio) : floorDecibels
    }
}
