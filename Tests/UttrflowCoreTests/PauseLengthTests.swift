// Tests for PauseLength and the windowing it adjusts.

import Foundation
import Testing

@testable import UttrflowCore

private let rate = 16_000

private func silence(_ seconds: Double) -> [Float] {
    [Float](repeating: 0, count: Int(seconds * Double(rate)))
}

/// A tone that swells and fades the way a spoken phrase does, never reaching zero.
private func speech(_ seconds: Double) -> [Float] {
    (0..<Int(seconds * Double(rate))).map { index in
        let time = Double(index) / Double(rate)
        return 0.3 * Float(0.7 + 0.3 * sin(2 * .pi * 3 * time)) * Float(sin(2 * .pi * 180 * time))
    }
}

/// Phrases of `phrase` seconds separated by `pause` seconds of silence, `count` phrases long.
private func pausing(_ pause: Double, phrase: Double = 3, count: Int) -> [Float] {
    (0..<count).flatMap { index in speech(phrase) + (index < count - 1 ? silence(pause) : []) }
}

@Suite("PauseLength")
struct PauseLengthTests {
    @Test("leaves the shipped windowing exactly as it is for usual pauses")
    func usualChangesNothing() {
        #expect(SpeechWindowing.standard.adjusted(for: .usual) == .standard)
    }

    @Test(
        "cuts pieces at mid-sentence pauses only for usual pauses",
        arguments: [(1.1, 4, 1), (1.5, 4, 1), (2.5, 4, 3)])
    func countsCuts(pause: Double, usual: Int, long: Int) {
        let audio = pausing(pause, count: 4)
        let cuts = { (pauses: PauseLength) in
            SpeechWindowing.standard.adjusted(for: pauses).windows(in: audio, sampleRate: rate).count
        }
        #expect(cuts(.usual) == usual)
        #expect(cuts(.long) == long)
        #expect(cuts(.veryLong) == 1)
    }

    @Test("never lets a piece outgrow the recogniser's window, however long the pauses are asked to be")
    func veryLongStillCutsAtTheWindow() {
        let audio = pausing(1.5, count: 9)
        let windows = SpeechWindowing.standard.adjusted(for: .veryLong).windows(in: audio, sampleRate: rate)
        #expect(windows.count == 2)
        #expect(windows.allSatisfy { Double($0.count) <= SpeechWindowing.standard.maximumLength * Double(rate) })
    }

    @Test("reads a profile saved before the setting existed as usual pauses")
    func oldProfileReadsAsUsual() throws {
        let saved = Data(#"{"preferredLanguages":["en"]}"#.utf8)
        #expect(try JSONDecoder().decode(UserProfile.self, from: saved).pauses == .usual)
        let long = UserProfile(pauses: .long)
        #expect(try JSONDecoder().decode(UserProfile.self, from: JSONEncoder().encode(long)) == long)
    }
}
