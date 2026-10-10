// Trim error of VoiceActivity under DC offset, low-frequency rumble and a noise floor that steps up.

import Foundation
import Testing

@testable import UttrflowCore

/// One synthetic recording with known speech boundaries.
private struct TrimCase {
    let label: String
    let samples: [Float]
    let speech: Range<Int>
}

private enum Grid {
    static let rate = 16_000
    static let margin = Int(VoiceActivity.margin * Double(rate))

    static func seconds(_ value: Double) -> Int { Int(value * Double(rate)) }

    static func noise(_ count: Int, rms: Double, seed: UInt64) -> [Float] {
        var state = seed &+ 0x9E37_79B9_7F4A_7C15
        let scale = Float(pow(10, rms / 20)) * Float(3).squareRoot()
        return (0..<count).map { _ in
            state = state &* 6_364_136_223_846_793_005 &+ 1_442_695_040_888_963_407
            return (Float(state >> 40) / Float(1 << 24) - 0.5) * 2 * scale
        }
    }

    /// A voiced phrase at `rms` dBFS whose envelope swells and fades.
    static func phrase(_ count: Int, rms: Double) -> [Float] {
        let peak = Float(pow(10, rms / 20)) / 0.62
        return (0..<count).map { index in
            let time = Double(index) / Double(rate)
            let envelope = Float(0.7 + 0.3 * sin(2 * .pi * 3 * time))
            return peak * envelope * Float(sin(2 * .pi * 180 * time))
        }
    }

    /// Two phrases with a pause between them, over room noise at -65 dBFS, ten seconds long.
    static func recording(speechLevel: Double, condition: String) -> TrimCase {
        let total = seconds(10)
        var audio = noise(total, rms: -65, seed: 7)
        let first = seconds(2)..<seconds(4)
        let second = seconds(6)..<seconds(8)
        for span in [first, second] {
            for (offset, sample) in phrase(span.count, rms: speechLevel).enumerated() {
                audio[span.lowerBound + offset] += sample
            }
        }
        switch condition {
        case "dc":
            audio = audio.map { $0 + 0.01 }
        case "rumble":
            let amplitude = Float(pow(10, -30.0 / 20)) * Float(2).squareRoot()
            audio = audio.enumerated().map { index, sample in
                sample + amplitude * Float(sin(2 * .pi * 60 * Double(index) / Double(rate)))
            }
        case "step":
            let extra = noise(total - total / 2, rms: -65 + 15, seed: 11)
            for (offset, sample) in extra.enumerated() { audio[total / 2 + offset] += sample }
        default:
            break
        }
        return TrimCase(
            label: "\(Int(speechLevel)) dBFS \(condition)", samples: audio,
            speech: first.lowerBound..<second.upperBound)
    }

    /// `samples` through a high-pass at 100 Hz of `order` 1 or 2, as a candidate front end for the measure.
    static func highPassed(_ samples: [Float], order: Int) -> [Float] {
        let omega = tan(Double.pi * 100 / Double(rate))
        var output = samples
        for _ in 0..<order {
            let coefficient = Float((1 - omega) / (1 + omega))
            let gain = (1 + coefficient) / 2
            var previousInput: Float = 0
            var previousOutput: Float = 0
            output = output.map { sample in
                previousOutput = gain * (sample - previousInput) + coefficient * previousOutput
                previousInput = sample
                return previousOutput
            }
        }
        return output
    }

    /// Milliseconds the trim falls inside the speech (clip) or beyond speech plus margin (over-include).
    static func error(of found: Range<Int>?, for trim: TrimCase) -> (clip: Int, over: Int)? {
        guard let found else { return nil }
        let clip =
            max(0, found.lowerBound - trim.speech.lowerBound)
            + max(0, trim.speech.upperBound - found.upperBound)
        let over =
            max(0, trim.speech.lowerBound - margin - found.lowerBound)
            + max(0, found.upperBound - trim.speech.upperBound - margin)
        return (clip * 1000 / rate, over * 1000 / rate)
    }
}

@Suite("VoiceActivity under recording conditions")
struct VoiceActivityConditionTests {
    @Test("reports the trim error for each level and condition")
    func reportsGrid() {
        for level in [-25.0, -40.0, -55.0] {
            for condition in ["clean", "dc", "rumble", "step"] {
                let trim = Grid.recording(speechLevel: level, condition: condition)
                for order in 0...2 {
                    let audio = order == 0 ? trim.samples : Grid.highPassed(trim.samples, order: order)
                    let found = VoiceActivity.speechRange(in: audio, sampleRate: Grid.rate)
                    let error = Grid.error(of: found, for: trim)
                    let cell = error.map { "clip \($0.clip) ms, over \($0.over) ms" } ?? "rejected"
                    print("TRIMGRID \(trim.label) high-pass order \(order): \(cell)")
                }
            }
        }
    }
}
