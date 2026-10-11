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

    static func speech(envelope: [Float]) -> [Float] {
        envelope.enumerated().flatMap { frame, level in
            (0..<(rate / 50)).map { sample in
                level * Float(sin(2 * .pi * 180 * Double(frame * (rate / 50) + sample) / Double(rate)))
            }
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

    @Test("cuts a long pause between short phrases once five seconds have been collected")
    func cutsLongEarlyPause() throws {
        let audio = Take.speech(3) + Take.silence(1.1) + Take.speech(3)
        let cut = try #require(windowing.nextCut(in: audio, sampleRate: Take.rate, from: 0))
        #expect(abs(Take.seconds(cut) - 3.55) < 0.05)
        #expect(windowing.windows(in: audio, sampleRate: Take.rate).count == 2)
    }

    @Test("cuts a one-and-a-half-second pause that starts before the early window is ready")
    func cutsLongPauseStartingBeforeEarlyWindow() throws {
        let audio = Take.speech(1.6) + Take.silence(1.5) + Take.speech(2.3)
        let cut = try #require(windowing.nextCut(in: audio, sampleRate: Take.rate, from: 0))
        #expect(abs(Take.seconds(cut) - 2.5) < 0.05)
        #expect(windowing.windows(in: audio, sampleRate: Take.rate).count == 2)
    }

    @Test("does not cut shorter early hesitations or speech before the early minimum")
    func leavesShortEarlyPauses() {
        let hesitation = Take.speech(3) + Take.silence(0.9) + Take.speech(3)
        let tooEarly = Take.speech(2) + Take.silence(1.2) + Take.speech(4)
        #expect(windowing.nextCut(in: hesitation, sampleRate: Take.rate, from: 0) == nil)
        #expect(windowing.nextCut(in: tooEarly, sampleRate: Take.rate, from: 0) == nil)
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

    @Test("cuts at a sentence pause the minimum length falls inside")
    func cutsAtPauseAcrossMinimum() throws {
        let audio = Take.speech(4.5) + Take.silence(1) + Take.speech(3)
        let cut = try #require(windowing.nextCut(in: audio, sampleRate: Take.rate, from: 0))
        #expect(abs(Take.seconds(cut) - 5) < 0.05)
    }

    @Test("still refuses a breath across the minimum, because it is short rather than early")
    func refusesShortPauseAcrossMinimum() {
        let audio = Take.speech(4.8) + Take.silence(0.5) + Take.speech(4)
        #expect(windowing.nextCut(in: audio, sampleRate: Take.rate, from: 0) == nil)
    }

    @Test("never cuts before the early minimum, however long the pause it opens on")
    func neverCutsBeforeMinimum() {
        let audio = Take.silence(2) + Take.speech(6)
        #expect(windowing.nextCut(in: audio, sampleRate: Take.rate, from: 0) == nil)
    }

    @Test("ignores a short pause while the window is still comfortable to grow")
    func ignoresShortPauseEarly() {
        let audio = Take.speech(7) + Take.silence(0.5) + Take.speech(4)
        #expect(windowing.nextCut(in: audio, sampleRate: Take.rate, from: 0) == nil)
    }

    @Test("does not cut on a breath just after the comfortable length")
    func leavesShortPauseAfterComfortableLength() {
        let audio = Take.speech(16) + Take.silence(0.5) + Take.speech(2)
        #expect(windowing.nextCut(in: audio, sampleRate: Take.rate, from: 0) == nil)
    }

    @Test("keeps a sentence pause sufficient while the window approaches its maximum")
    func takesSentencePauseLater() throws {
        let audio =
            Take.speech(16) + Take.silence(0.5) + Take.speech(10) + Take.silence(0.9)
            + Take.speech(2)
        let cut = try #require(windowing.nextCut(in: audio, sampleRate: Take.rate, from: 0))
        #expect(Take.seconds(cut) > 26.5)
        #expect(Take.seconds(cut) < 27)
        let windows = windowing.windows(in: audio, sampleRate: Take.rate)
        #expect(windows.count == 2)
        #expect(windows.first?.upperBound == cut)
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
        // The cut is the middle of the quietest 0.12 s stretch holding the dip, so it may sit up to three frames past it.
        #expect(abs(Take.seconds(cut) - 22.5) < 0.07)
        #expect(windowing.nextCut(in: Take.speech(29), sampleRate: Take.rate, from: 0) == nil)
    }

    @Test("a hard cut prefers a word gap over a single-frame stop closure")
    func hardCutPrefersQuietStretch() throws {
        var envelope = (0..<(32 * 50)).map { frame in
            frame % 20 < 15 ? Float(0.1) : Float(0.03)
        }
        envelope[20 * 50 + 10] = 0.004
        envelope[20 * 50 + 11] = 0.004
        // The gap after the closure is the quietest, so the expected cut does not rest on a tie between equal gaps.
        for frame in (20 * 50 + 15)..<(20 * 50 + 20) { envelope[frame] = 0.02 }
        let cut = try #require(
            windowing.nextCut(in: Take.speech(envelope: envelope), sampleRate: Take.rate, from: 0))
        let seconds = Take.seconds(cut)
        #expect(seconds >= 20.3 && seconds <= 20.4)
        #expect((20.2..<20.24).contains(seconds) == false)
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

    /// Issue 2319: one short word between long pauses is carried into the next window rather than decoded alone.
    @Test("never gives a window holding only a short word said between long pauses")
    func carriesALoneWord() {
        let audio =
            Take.speech(1) + Take.silence(4) + Take.speech(0.3) + Take.silence(4) + Take.speech(1)
        let windows = windowing.windows(in: audio, sampleRate: Take.rate)
        let wordStart = 5 * Take.rate
        let wordEnd = wordStart + Int(0.3 * Double(Take.rate))
        let holding = windows.filter { $0.lowerBound <= wordStart && $0.upperBound >= wordEnd }
        #expect(holding.count == 1)
        let nextPhrase = 9 * Take.rate + Take.rate / 3
        #expect(holding.allSatisfy { $0.lowerBound < Take.rate || $0.upperBound > nextPhrase })
    }

    @Test("joins a last window holding only a short word onto the window before it")
    func joinsAShortTail() {
        let audio = Take.speech(7) + Take.silence(3) + Take.speech(0.3) + Take.silence(0.5)
        let windows = windowing.windows(in: audio, sampleRate: Take.rate)
        #expect(windows == [0..<audio.count])
    }

    @Test("keeps a silent tail its own window, so no silence is added to the speech before it")
    func keepsASilentTail() {
        let audio = Take.speech(7) + Take.silence(8)
        #expect(windowing.windows(in: audio, sampleRate: Take.rate).count == 2)
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

    @Test("windowing a finished recording does not slow down quadratically with its length")
    func windowsScalesLinearly() {
        /// The CPU time this thread spends windowing `seconds` of speech, least of three, so waiting for a core is not counted.
        func cost(_ seconds: Double) -> UInt64 {
            let audio = Take.speech(seconds, level: 0.3)
            let runs = (0..<3).map { _ in
                let start = clock_gettime_nsec_np(CLOCK_THREAD_CPUTIME_ID)
                _ = windowing.windows(in: audio, sampleRate: Take.rate)
                return clock_gettime_nsec_np(CLOCK_THREAD_CPUTIME_ID) - start
            }
            return runs.min() ?? 0
        }
        let short = cost(30)
        let long = cost(240)
        // Eight times the audio costs about ten times the work when linear, and over thirty times when quadratic.
        #expect(long < short * 20, "30 s took \(short) ns of CPU, 240 s took \(long) ns")
    }

    @Test("carries the lengths it was given")
    func carriesParameters() {
        let custom = SpeechWindowing(
            minimumLength: 1, sentencePause: 0.2, comfortableLength: 2, anyPause: 0.1,
            maximumLength: 3)
        #expect(custom.minimumLength == 1)
        #expect(custom.earlyLength == 2.5)
        #expect(custom.earlyPause == 1.0)
        #expect(custom.maximumLength == 3)
        #expect(custom != .standard)
    }

    /// A microphone change 40% into a minute of unbroken speech, where no pause offers a cut.
    @Test("no window spans a discontinuity, and one ends exactly on it")
    func discontinuityEndsAWindow() {
        let audio = Take.speech(60)
        let change = audio.count * 2 / 5
        let windows = windowing.windows(in: audio, sampleRate: Take.rate, boundaries: [change])

        #expect(windows.contains { $0.upperBound == change })
        #expect(!windows.contains { $0.lowerBound < change && $0.upperBound > change })
        #expect(windows.first?.lowerBound == 0 && windows.last?.upperBound == audio.count)
    }

    @Test("a word or two after a discontinuity is not joined to the window before it")
    func fragmentAfterDiscontinuityStaysApart() {
        let audio = Take.speech(6) + Take.speech(0.3)
        let change = Take.speech(6).count
        let windows = windowing.windows(in: audio, sampleRate: Take.rate, boundaries: [change])

        #expect(windows == [0..<change, change..<audio.count])
    }
}
