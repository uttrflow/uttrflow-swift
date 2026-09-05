// Tests for SpeechWindowing.

import Foundation
import Testing

@testable import UttrflowCore

/// Recordings shaped like the pauses a windowing has to find.
private enum Take {
    static let rate = 16_000

    static func silence(_ seconds: Double) -> [Float] {
        [Float](repeating: 0, count: Int(seconds * Double(rate)))
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

    static func seconds(_ samples: Int) -> Double { Double(samples) / Double(rate) }
}

@Suite("SpeechWindowing")
struct SpeechWindowingTests {
    private let windowing = SpeechWindowing.standard

    @Test("gives no cut while the window is still too short")
    func noCutBeforeMinimum() {
        let audio = Take.speech(3) + Take.silence(1)
        #expect(windowing.nextCut(in: audio, sampleRate: Take.rate, from: 0) == nil)
    }

    @Test("gives no cut for an empty recording, a bad rate or a start past the end")
    func refusesNonsense() {
        let audio = Take.speech(10)
        #expect(windowing.nextCut(in: [], sampleRate: Take.rate, from: 0) == nil)
        #expect(windowing.nextCut(in: audio, sampleRate: 0, from: 0) == nil)
        #expect(windowing.nextCut(in: audio, sampleRate: Take.rate, from: audio.count) == nil)
        #expect(windowing.nextCut(in: audio, sampleRate: Take.rate, from: -1) == nil)
    }

    @Test("cuts in the middle of a sentence-long pause once the window is long enough")
    func cutsAtSentencePause() throws {
        let audio = Take.speech(7) + Take.silence(1) + Take.speech(4)
        let cut = try #require(windowing.nextCut(in: audio, sampleRate: Take.rate, from: 0))
        #expect(abs(Take.seconds(cut) - 7.5) < 0.05)
    }

    @Test("ignores a short pause while the window is still comfortable to grow")
    func ignoresShortPauseEarly() {
        let audio = Take.speech(7) + Take.silence(0.5) + Take.speech(4)
        #expect(windowing.nextCut(in: audio, sampleRate: Take.rate, from: 0) == nil)
    }

    @Test("takes a short pause once the window has grown past the comfortable length")
    func takesShortPauseLater() throws {
        let audio = Take.speech(16) + Take.silence(0.5) + Take.speech(2)
        let cut = try #require(windowing.nextCut(in: audio, sampleRate: Take.rate, from: 0))
        #expect(abs(Take.seconds(cut) - 16.25) < 0.05)
    }

    @Test("counts a pause the speaker is still in, so a cut need not wait for the next word")
    func countsOpenPause() throws {
        let audio = Take.speech(7) + Take.silence(1)
        let cut = try #require(windowing.nextCut(in: audio, sampleRate: Take.rate, from: 0))
        #expect(abs(Take.seconds(cut) - 7.5) < 0.05)
    }

    @Test("cuts at the quietest moment of the second half when nobody pauses")
    func hardCutAtQuietestMoment() throws {
        var audio = Take.speech(32)
        // A dip in a single frame, the kind that sits between two words.
        let dip = Int(22.5 * Double(Take.rate))
        for index in dip..<(dip + Take.rate / 50) { audio[index] *= 0.2 }
        let cut = try #require(windowing.nextCut(in: audio, sampleRate: Take.rate, from: 0))
        #expect(abs(Take.seconds(cut) - 22.5) < 0.03)
        #expect(windowing.nextCut(in: Take.speech(29), sampleRate: Take.rate, from: 0) == nil)
    }

    @Test("a hard cut never comes before the comfortable length")
    func hardCutStaysLate() throws {
        var audio = Take.speech(31)
        let dip = Int(8 * Double(Take.rate))
        for index in dip..<(dip + Take.rate / 50) { audio[index] *= 0.2 }
        let cut = try #require(windowing.nextCut(in: audio, sampleRate: Take.rate, from: 0))
        #expect(Take.seconds(cut) >= 15)
    }

    @Test("measures from where the last window ended")
    func startsFromTheCut() throws {
        let audio = Take.speech(7) + Take.silence(1) + Take.speech(6) + Take.silence(1) + Take.speech(1)
        let first = try #require(windowing.nextCut(in: audio, sampleRate: Take.rate, from: 0))
        let second = try #require(windowing.nextCut(in: audio, sampleRate: Take.rate, from: first))
        #expect(abs(Take.seconds(second) - 14.5) < 0.05)
    }

    @Test("splits a finished recording into every window, keeping the short tail whole")
    func windowsOverWholeRecording() {
        let audio = Take.speech(7) + Take.silence(1) + Take.speech(6) + Take.silence(1) + Take.speech(1)
        let windows = windowing.windows(in: audio, sampleRate: Take.rate)
        #expect(windows.count == 3)
        #expect(windows.first?.lowerBound == 0)
        #expect(windows.last?.upperBound == audio.count)
        #expect(zip(windows, windows.dropFirst()).allSatisfy { $0.upperBound == $1.lowerBound })
    }

    @Test("a short recording is one window, and nothing is none")
    func shortAndEmptyRecordings() {
        #expect(windowing.windows(in: Take.speech(3), sampleRate: Take.rate) == [0..<(3 * Take.rate)])
        #expect(windowing.windows(in: [], sampleRate: Take.rate).isEmpty)
    }

    @Test("leaves a recording with no speech in it as one piece, however long")
    func silenceIsOnePiece() {
        let quiet = Take.silence(200)
        #expect(windowing.nextCut(in: quiet, sampleRate: Take.rate, from: 0) == nil)
        #expect(windowing.windows(in: quiet, sampleRate: Take.rate) == [0..<quiet.count])
    }

    @Test("still cuts when the only speech is past the recogniser's window")
    func cutsAheadOfLateSpeech() throws {
        let audio = Take.silence(40) + Take.speech(3)
        let cut = try #require(windowing.nextCut(in: audio, sampleRate: Take.rate, from: 0))
        #expect(cut > 5 * Take.rate && cut <= 30 * Take.rate)
    }

    @Test("carries the lengths it was given")
    func carriesParameters() {
        let custom = SpeechWindowing(
            minimumLength: 1, sentencePause: 0.2, comfortableLength: 2, anyPause: 0.1,
            maximumLength: 3)
        #expect(custom.minimumLength == 1)
        #expect(custom.maximumLength == 3)
        #expect(custom != .standard)
    }
}
