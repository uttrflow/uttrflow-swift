// Tests for the quiet that ends a recording no key is holding.
import Foundation
import Testing

@testable import UttrflowCore

/// Phrases and pauses shaped like a person dictating into a quiet room.
private enum Spoken {
    static let rate = 16_000

    /// Stationary noise at -60 dBFS, which is a quiet room rather than digital zeros.
    static func room(_ seconds: Double, seed: UInt64 = 7) -> [Float] {
        var state = seed &+ 0x9E37_79B9_7F4A_7C15
        return (0..<Int(seconds * Double(rate))).map { _ in
            state = state &* 6_364_136_223_846_793_005 &+ 1_442_695_040_888_963_407
            return (Float(state >> 40) / Float(1 << 24) - 0.5) * 0.002
        }
    }

    /// A tone that swells and fades the way a phrase does, over the room.
    static func phrase(_ seconds: Double) -> [Float] {
        zip(room(seconds, seed: 11), 0..<Int(seconds * Double(rate))).map { noise, index in
            let time = Double(index) / Double(rate)
            let envelope = Float(0.7 + 0.3 * sin(2 * .pi * 3 * time))
            return noise + 0.3 * envelope * Float(sin(2 * .pi * 180 * time))
        }
    }
}

@Suite("Silence stop")
struct SilenceStopTests {
    @Test("measures the quiet after the last phrase, to within a frame")
    func measuresTrailingQuiet() throws {
        let samples = Spoken.phrase(2) + Spoken.room(0.6) + Spoken.phrase(1) + Spoken.room(3)
        let quiet = try #require(VoiceActivity.trailingSilence(in: samples, sampleRate: Spoken.rate))
        #expect(abs(quiet / .seconds(1) - 3) <= 0.02)
    }

    @Test("has nothing to measure before anything is said", arguments: [0.0, 0.002])
    func nothingBeforeSpeech(level: Double) {
        let room = level == 0 ? [Float](repeating: 0, count: 10 * Spoken.rate) : Spoken.room(10)
        #expect(VoiceActivity.trailingSilence(in: room, sampleRate: Spoken.rate) == nil)
        #expect(SilenceStop(seconds: 2)?.isReached(in: room, sampleRate: Spoken.rate) == false)
    }

    @Test("stops once the quiet reaches the wait, and not while a pause is shorter")
    func reachesTheWait() throws {
        let stop = try #require(SilenceStop(seconds: 4))
        let paused = Spoken.phrase(3) + Spoken.room(3.9)
        #expect(!stop.isReached(in: paused, sampleRate: Spoken.rate))
        #expect(stop.isReached(in: paused + Spoken.room(0.2), sampleRate: Spoken.rate))
        #expect(!stop.isReached(in: paused + Spoken.phrase(0.5), sampleRate: Spoken.rate))
    }

    @Test("a click in the quiet is not speech, so it does not start the wait again")
    func clickIsNotSpeech() throws {
        let stop = try #require(SilenceStop(seconds: 2))
        let click = (0..<(Spoken.rate * 6 / 100)).map { $0.isMultiple(of: 2) ? Float(0.5) : -0.5 }
        let samples = Spoken.phrase(2) + Spoken.room(1.5) + click + Spoken.room(0.6)
        #expect(stop.isReached(in: samples, sampleRate: Spoken.rate))
    }

    @Test("offers only the listed waits, and reads back the wait and five seconds before it")
    func choices() throws {
        let waits = SilenceStop.choices.compactMap(SilenceStop.init(seconds:)).map(\.wait)
        #expect(waits == [.seconds(2), .seconds(4), .seconds(8)])
        #expect(SilenceStop(seconds: 0) == nil)
        #expect(SilenceStop(seconds: 3) == nil)
        #expect(try #require(SilenceStop(seconds: 8)).lookBack(atRate: Spoken.rate) == 13 * Spoken.rate)
    }
}
