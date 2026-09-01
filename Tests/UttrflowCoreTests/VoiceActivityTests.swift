import Foundation
import Testing

@testable import UttrflowCore

/// Signals shaped like the recordings this has to tell apart.
private enum Signal {
    static let rate = 16_000

    static func silence(_ seconds: Double) -> [Float] {
        [Float](repeating: 0, count: Int(seconds * Double(rate)))
    }

    /// Stationary noise at one level, which is what a fan or a hissing microphone is.
    static func noise(_ seconds: Double, level: Float, seed: UInt64 = 1) -> [Float] {
        var state = seed &+ 0x9E37_79B9_7F4A_7C15
        return (0..<Int(seconds * Double(rate))).map { _ in
            state = state &* 6_364_136_223_846_793_005 &+ 1_442_695_040_888_963_407
            return (Float(state >> 40) / Float(1 << 24) - 0.5) * 2 * level
        }
    }

    /// A tone that swells and fades the way a spoken phrase does, never reaching zero.
    static func speech(_ seconds: Double, level: Float = 0.3) -> [Float] {
        let count = Int(seconds * Double(rate))
        return (0..<count).map { index in
            let time = Double(index) / Double(rate)
            let envelope = Float(0.7 + 0.3 * sin(2 * .pi * 3 * time))
            return level * envelope * Float(sin(2 * .pi * 180 * time))
        }
    }
}

@Suite("VoiceActivity")
struct VoiceActivityTests {
    @Test("hears nothing in digital silence")
    func rejectsSilence() {
        #expect(VoiceActivity.speechRange(in: Signal.silence(20), sampleRate: Signal.rate) == nil)
    }

    @Test("hears nothing in a quiet room")
    func rejectsQuietRoom() {
        let room = Signal.noise(20, level: 0.002)
        #expect(VoiceActivity.speechRange(in: room, sampleRate: Signal.rate) == nil)
    }

    @Test("hears nothing in a hissing microphone, which is above the absolute floor")
    func rejectsLoudHiss() {
        let hiss = Signal.noise(20, level: 0.04)
        #expect(hiss.contains { Swift.abs($0) > VoiceActivity.absoluteFloor })
        #expect(VoiceActivity.speechRange(in: hiss, sampleRate: Signal.rate) == nil)
    }

    @Test("keeps evenly-spoken speech, which is as stationary as noise is")
    func keepsSteadySpeech() {
        // The stationarity test cannot tell these apart, so loudness decides, and it
        // decides in favour of keeping the words.
        #expect(VoiceActivity.speechRange(in: Signal.speech(3), sampleRate: Signal.rate) != nil)
    }

    @Test("hears nothing in an empty recording")
    func rejectsEmpty() {
        #expect(VoiceActivity.speechRange(in: [], sampleRate: Signal.rate) == nil)
    }

    @Test("finds speech and reports a range covering it")
    func findsSpeech() throws {
        let range = try #require(
            VoiceActivity.speechRange(in: Signal.speech(3), sampleRate: Signal.rate))
        #expect(range.count > Signal.rate * 2)
    }

    @Test("trims the silence around speech, keeping the speech itself")
    func trimsSurroundingSilence() throws {
        let audio = Signal.silence(4) + Signal.speech(3) + Signal.silence(5)
        let range = try #require(
            VoiceActivity.speechRange(in: audio, sampleRate: Signal.rate))

        // Inside the silence on each side, and around the speech on both.
        #expect(range.lowerBound > Signal.rate * 3)
        #expect(range.lowerBound <= Signal.rate * 4)
        #expect(range.upperBound >= Signal.rate * 7)
        #expect(range.upperBound < Signal.rate * 8)
    }

    @Test("keeps a margin either side so no onset is clipped")
    func keepsAMargin() throws {
        let leadIn = 4.0
        let audio = Signal.silence(leadIn) + Signal.speech(3) + Signal.silence(4)
        let range = try #require(
            VoiceActivity.speechRange(in: audio, sampleRate: Signal.rate))

        let speechStart = Int(leadIn * Double(Signal.rate))
        #expect(range.lowerBound < speechStart)
        #expect(speechStart - range.lowerBound <= Int(VoiceActivity.margin * Double(Signal.rate)) + 1)
    }

    @Test("hears speech spoken over a noisy room")
    func findsSpeechOverNoise() throws {
        let room = Signal.noise(10, level: 0.01)
        var audio = room
        for (offset, sample) in Signal.speech(3, level: 0.3).enumerated() {
            audio[Signal.rate * 3 + offset] += sample
        }
        let range = try #require(
            VoiceActivity.speechRange(in: audio, sampleRate: Signal.rate))
        #expect(range.lowerBound < Signal.rate * 4)
        #expect(range.upperBound > Signal.rate * 5)
    }

    @Test("a single click is too short to be a word")
    func rejectsAClick() {
        var audio = Signal.silence(20)
        for index in 0..<(Signal.rate / 100) { audio[Signal.rate * 5 + index] = 0.6 }
        #expect(VoiceActivity.speechRange(in: audio, sampleRate: Signal.rate) == nil)
    }

    @Test("speech still running when the recording ends is kept")
    func keepsSpeechRunningToTheEnd() throws {
        let audio = Signal.silence(3) + Signal.speech(3)
        let range = try #require(
            VoiceActivity.speechRange(in: audio, sampleRate: Signal.rate))
        #expect(range.upperBound == audio.count)
    }

    @Test("a non-finite sample cannot pin the meter and pass silence off as speech")
    func ignoresNonFiniteSamples() {
        var audio = Signal.silence(20)
        audio[Signal.rate] = .infinity
        audio[Signal.rate + 1] = .nan
        #expect(VoiceActivity.speechRange(in: audio, sampleRate: Signal.rate) == nil)
    }
}

@Suite("AudioSamples.speechOnly")
struct IsolatedSpeechTests {
    @Test("reports where in the recording the speech began")
    func reportsOffset() throws {
        let audio = AudioSamples.canonical(Signal.silence(4) + Signal.speech(3) + Signal.silence(4))
        let speech = try #require(audio.speechOnly())

        #expect(speech.start > .seconds(3.5))
        #expect(speech.start <= .seconds(4))
        #expect(speech.audio.duration < audio.duration)
    }

    @Test("answers nothing for a recording with no speech in it")
    func answersNothingForSilence() {
        #expect(AudioSamples.canonical(Signal.silence(20)).speechOnly() == nil)
    }
}
