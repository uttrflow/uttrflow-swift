// Signed trim error of VoiceActivity against exact speech boundaries, across onset type, level and noise floor.

import Foundation
import Testing

@testable import UttrflowCore

private enum OnsetGrid {
    static let rate = 16_000

    static func samples(_ seconds: Double) -> Int { Int(seconds * Double(rate)) }

    static func amplitude(_ dBFS: Double) -> Float { Float(pow(10, dBFS / 20)) }

    static func noise(_ count: Int, rms: Double, seed: UInt64) -> [Float] {
        var state = seed &+ 0x9E37_79B9_7F4A_7C15
        let scale = amplitude(rms) * Float(3).squareRoot()
        return (0..<count).map { _ in
            state = state &* 6_364_136_223_846_793_005 &+ 1_442_695_040_888_963_407
            return (Float(state >> 40) / Float(1 << 24) - 0.5) * 2 * scale
        }
    }

    static func tone(_ count: Int, hertz: Double, rms: Double) -> [Float] {
        let peak = amplitude(rms) * Float(2).squareRoot()
        return (0..<count).map { peak * Float(sin(2 * .pi * hertz * Double($0) / Double(rate))) }
    }

    /// The sound before the vowel, with the vowel at `level` dBFS: a fricative 20 dB down, a nasal 12 dB down, a plosive burst then its gap.
    static func onset(_ kind: String, level: Double) -> [Float] {
        switch kind {
        case "fricative": return noise(samples(0.1), rms: level - 20, seed: 3)
        case "nasal": return tone(samples(0.08), hertz: 220, rms: level - 12)
        case "plosive":
            return noise(samples(0.01), rms: level - 6, seed: 5) + [Float](repeating: 0, count: samples(0.04))
        default: return []
        }
    }

    /// One word whose first and last samples are its exact boundaries: onset, vowel, onset reversed.
    static func word(_ kind: String, level: Double) -> [Float] {
        let edge = onset(kind, level: level)
        return edge + tone(samples(0.3), hertz: 150, rms: level) + edge.reversed()
    }

    /// One second of room, two words with 150 ms between them, one second of room; and where the speech is.
    static func clip(onset kind: String, level: Double, floor: Double) -> (audio: [Float], speech: Range<Int>)
    {
        let spoken = word(kind, level: level)
        let lead = samples(1)
        var speech = spoken + [Float](repeating: 0, count: samples(0.15)) + spoken
        var audio = noise(lead * 2 + speech.count, rms: floor, seed: 7)
        speech = speech.enumerated().map { $1 + audio[lead + $0] }
        audio.replaceSubrange(lead..<(lead + speech.count), with: speech)
        return (audio, lead..<(lead + speech.count))
    }
}

@Suite("VoiceActivity against known speech boundaries")
struct VoiceActivityOnsetGridTests {
    @Test("reports signed start and end error for each onset, level and floor")
    func reportsGrid() {
        var clipped: [String] = []
        for kind in ["vowel", "plosive", "nasal", "fricative"] {
            for level in [-45.0, -35.0, -25.0, -15.0] {
                for floor in [-70.0, -60.0, -50.0, -40.0, -35.0] {
                    let clip = OnsetGrid.clip(onset: kind, level: level, floor: floor)
                    let label = "\(kind) speech \(Int(level)) floor \(Int(floor))"
                    guard let found = VoiceActivity.speechRange(in: clip.audio, sampleRate: OnsetGrid.rate)
                    else {
                        print("ONSETGRID \(label): rejected")
                        if level - floor >= 10 { clipped.append(label) }
                        continue
                    }
                    let start = (found.lowerBound - clip.speech.lowerBound) * 1000 / OnsetGrid.rate
                    let end = (found.upperBound - clip.speech.upperBound) * 1000 / OnsetGrid.rate
                    let lost = start > 0 || end < 0
                    print(
                        "ONSETGRID \(label): start \(start) ms, end \(end) ms\(lost ? ", speech clipped" : "")"
                    )
                    if lost { clipped.append(label) }
                }
            }
        }
        // Speech 10 dB or more above the room is never clipped or refused.
        #expect(clipped.isEmpty, "\(clipped)")
    }
}
