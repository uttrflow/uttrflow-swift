// Tests for CaptureQuality on synthetic signals whose figures are known in advance.

import Foundation
import Testing

@testable import UttrflowCore

/// Signals whose level, floor, clipping and offset follow from how they are built.
private enum Synthetic {
    static let rate = 16_000

    /// A 440 Hz sine of `amplitude`, shifted by `offset` and hard-clipped to full scale.
    static func sine(_ seconds: Double, amplitude: Double, offset: Double = 0) -> [Float] {
        (0..<Int(seconds * Double(rate))).map { index in
            let value = offset + amplitude * sin(2 * .pi * 440 * Double(index) / Double(rate))
            return Float(Swift.min(1, Swift.max(-1, value)))
        }
    }

    /// Uniform white noise of peak `level`, from a fixed seed so every run is the same.
    static func noise(_ seconds: Double, level: Double, seed: UInt64 = 7) -> [Float] {
        var state = seed &+ 0x9E37_79B9_7F4A_7C15
        return (0..<Int(seconds * Double(rate))).map { _ in
            state = state &* 6_364_136_223_846_793_005 &+ 1_442_695_040_888_963_407
            return Float((Double(state >> 40) / Double(1 << 24) - 0.5) * 2 * level)
        }
    }

    static func decibels(_ magnitude: Double) -> Double { 20 * log10(magnitude) }
}

@Suite("CaptureQuality")
struct CaptureQualityTests {
    @Test("a sine at a known level reports its peak and its RMS level")
    func sineLevels() throws {
        let quality = try #require(
            CaptureQuality.measure(samples: Synthetic.sine(2, amplitude: 0.1), sampleRate: Synthetic.rate))

        #expect(abs(quality.peakDecibels - -20) < 0.5)
        #expect(abs(quality.speechLevelDecibels - Synthetic.decibels(0.1 / 2.squareRoot())) < 0.5)
        #expect(abs(quality.noiseFloorDecibels - Synthetic.decibels(0.1 / 2.squareRoot())) < 0.5)
        #expect(quality.clippedFraction == 0)
        #expect(abs(quality.offset) < 0.005)
        #expect(quality.sampleRate == Synthetic.rate)
    }

    @Test("a hard-clipped sine reports the share of samples held at full scale")
    func clippedSine() throws {
        let quality = try #require(
            CaptureQuality.measure(samples: Synthetic.sine(2, amplitude: 2), sampleRate: Synthetic.rate))
        let expected = 1 - 2 / Double.pi * asin(Double(CaptureQuality.clippingMagnitude) / 2)

        #expect(abs(quality.clippedFraction - expected) < 0.005)
        #expect(quality.peakDecibels == 0)
    }

    @Test("a sine carried on an offset reports the offset")
    func offsetSine() throws {
        let samples = Synthetic.sine(2, amplitude: 0.2, offset: 0.05)
        let quality = try #require(CaptureQuality.measure(samples: samples, sampleRate: Synthetic.rate))

        #expect(abs(quality.offset - 0.05) < 0.005)
        #expect(abs(quality.peakDecibels - Synthetic.decibels(0.25)) < 0.5)
    }

    @Test("speech over white noise recovers the noise floor and the ratio between them")
    func signalToNoise() throws {
        let noiseLevel = 0.01
        let noise = Synthetic.noise(4, level: noiseLevel)
        let tone = Synthetic.sine(2, amplitude: 0.3)
        let samples = noise.enumerated().map { index, sample in
            index < tone.count ? sample : sample + tone[index - tone.count]
        }
        let quality = try #require(CaptureQuality.measure(samples: samples, sampleRate: Synthetic.rate))
        let noiseRMS = noiseLevel / 3.squareRoot()
        let speechRMS = (0.3 * 0.3 / 2 + noiseRMS * noiseRMS).squareRoot()
        let ratio = try #require(quality.signalToNoiseDecibels)

        #expect(abs(quality.noiseFloorDecibels - Synthetic.decibels(noiseRMS)) < 0.5)
        #expect(abs(quality.speechLevelDecibels - Synthetic.decibels(speechRMS)) < 0.5)
        #expect(abs(ratio - (Synthetic.decibels(speechRMS) - Synthetic.decibels(noiseRMS))) < 0.5)
    }

    @Test("digital silence has no level and no ratio, rather than a number standing in for one")
    func silence() throws {
        let samples = [Float](repeating: 0, count: Synthetic.rate)
        let quality = try #require(CaptureQuality.measure(samples: samples, sampleRate: Synthetic.rate))

        #expect(quality.peakDecibels == -.infinity)
        #expect(quality.noiseFloorDecibels == -.infinity)
        #expect(quality.signalToNoiseDecibels == nil)
    }

    @Test("a sample a misbehaving driver sent as nan counts towards nothing")
    func ignoresNonFiniteSamples() throws {
        var samples = Synthetic.sine(1, amplitude: 0.1)
        samples[100] = .nan
        let quality = try #require(CaptureQuality.measure(samples: samples, sampleRate: Synthetic.rate))

        #expect(abs(quality.peakDecibels - -20) < 0.5)
        #expect(quality.offset.isFinite)
    }

    @Test("too little audio to compare two frames, or no sample rate, measures nothing")
    func tooLittleToMeasure() {
        #expect(CaptureQuality.measure(samples: [0.5, -0.5], sampleRate: Synthetic.rate) == nil)
        #expect(CaptureQuality.measure(samples: [], sampleRate: Synthetic.rate) == nil)
        #expect(CaptureQuality.measure(samples: Synthetic.sine(1, amplitude: 0.1), sampleRate: 0) == nil)
    }

    @Test("carries the timeline's holes, which the samples alone cannot show")
    func carriesGaps() throws {
        let holes = CaptureGaps(holes: 3, milliseconds: 120, lostBuffers: 1)
        let quality = try #require(
            CaptureQuality.measure(
                samples: Synthetic.sine(2, amplitude: 0.1), sampleRate: Synthetic.rate, gaps: holes))
        #expect(quality.gaps == holes)
        #expect(holes + holes == CaptureGaps(holes: 6, milliseconds: 240, lostBuffers: 2))
    }

    @Test("says when the chosen input was missing, and only then")
    func carriesChosenInputMissing() throws {
        let missing = try #require(
            CaptureQuality.measure(
                samples: Synthetic.sine(2, amplitude: 0.1), sampleRate: Synthetic.rate,
                chosenInputMissing: true))
        let present = try #require(
            CaptureQuality.measure(samples: Synthetic.sine(2, amplitude: 0.1), sampleRate: Synthetic.rate))
        #expect(missing.chosenInputMissing)
        #expect(present.chosenInputMissing == false)
    }
}
