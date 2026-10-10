// Tests for InputSilence, the warning given while a recording's input stays below the floor.

import Foundation
import Testing

@testable import UttrflowCore

/// Readings at the dock's 20 Hz, each the RMS of one block of synthetic audio.
private enum Readings {
    static let interval = 0.05

    /// RMS of a sine at `amplitude`, which is what a steady tone or hum reads as.
    static func tone(_ amplitude: Float) -> Float { amplitude / Float(2).squareRoot() }

    /// Feeds `levels` from `start` seconds and returns the times a warning started.
    static func feed(_ levels: [Float], into watch: inout InputSilence, from start: Double = 0) -> [Double] {
        var started: [Double] = []
        for (index, level) in levels.enumerated() {
            let time = start + Double(index) * interval
            if watch.read(level, at: time) { started.append(time) }
        }
        return started
    }

    static func seconds(_ seconds: Double, at level: Float) -> [Float] {
        [Float](repeating: level, count: Int((seconds / interval).rounded()))
    }
}

@Suite("Telling the person the microphone is not picking them up")
struct InputSilenceTests {
    @Test("exact silence warns once, after the patience and not before")
    func exactSilenceWarnsOnce() {
        var watch = InputSilence()
        let started = Readings.feed(Readings.seconds(10, at: 0), into: &watch)
        #expect(started.count == 1)
        #expect(started.first.map { $0 >= InputSilence.patience && $0 < InputSilence.patience + 0.1 } == true)
        #expect(watch.isSilent)
    }

    @Test("a sub-floor hiss at -100 dBFS warns like silence does")
    func subFloorWarns() {
        var watch = InputSilence()
        let started = Readings.feed(Readings.seconds(5, at: 0.00001), into: &watch)
        #expect(started.count == 1)
    }

    @Test("quiet speech at -60 dBFS, far above the floor, never warns")
    func quietSpeechNeverWarns() {
        var watch = InputSilence()
        let started = Readings.feed(Readings.seconds(30, at: Readings.tone(0.001)), into: &watch)
        #expect(started.isEmpty)
        #expect(!watch.isSilent)
    }

    @Test("a three-second pause in room tone never warns")
    func naturalPauseNeverWarns() {
        var watch = InputSilence()
        let speech = Readings.seconds(1, at: 0.03)
        let room = Readings.seconds(3, at: 0.0003)  // about -70 dBFS
        let started = Readings.feed(speech + room + speech, into: &watch)
        #expect(started.isEmpty)
    }

    @Test("the warning clears on the first reading that reaches the floor, and can start again")
    func clearsAndReturns() {
        var watch = InputSilence()
        let first = Readings.feed(Readings.seconds(3, at: 0), into: &watch)
        #expect(first.count == 1)
        let rose = watch.read(0.03, at: 3)
        #expect(!rose)
        #expect(!watch.isSilent)
        let again = Readings.feed(Readings.seconds(3, at: 0), into: &watch, from: 3.05)
        #expect(again.count == 1)
    }

    @Test("a driver's nan counts as no signal")
    func nanIsSilence() {
        var watch = InputSilence()
        let started = Readings.feed(Readings.seconds(3, at: .nan), into: &watch)
        #expect(started.count == 1)
    }

    @Test("the floor is the one the silence refusal applies")
    func sharesTheRefusalFloor() {
        var watch = InputSilence()
        let atFloor = watch.read(VoiceActivity.absoluteFloor, at: 0)
        #expect(!atFloor)
        let below = Readings.feed(
            Readings.seconds(3, at: VoiceActivity.absoluteFloor * 0.99), into: &watch, from: 1)
        #expect(below.count == 1)
    }
}
