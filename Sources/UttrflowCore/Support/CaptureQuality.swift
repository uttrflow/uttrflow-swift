// What a recording sounded like, as aggregates only. See `Docs/capture-quality.md`.
private import Darwin

/// Level, noise floor, clipping and offset of one recording, measured the way `VoiceActivity` hears it.
public struct CaptureQuality: Sendable, Equatable {
    /// A sample at or above this magnitude is counted as clipped.
    static let clippingMagnitude: Float = 0.999

    /// The loudest sample, in dBFS; negative infinity for digital silence.
    public let peakDecibels: Double
    /// The ``VoiceActivity/ceilingPercentile`` frame loudness as RMS, in dBFS.
    public let speechLevelDecibels: Double
    /// The ``VoiceActivity/floorPercentile`` frame loudness as RMS, in dBFS.
    public let noiseFloorDecibels: Double
    /// The share of samples at or above ``clippingMagnitude``, in `0...1`.
    public let clippedFraction: Double
    /// The mean sample, which is the DC offset as a fraction of full scale.
    public let offset: Double
    /// Samples per second of the audio measured.
    public let sampleRate: Int
    /// Time the capture timeline lost before these samples, which the samples alone cannot show.
    public let gaps: CaptureGaps

    /// Speech level over noise floor in dB, or `nil` when the floor is digital silence.
    public var signalToNoiseDecibels: Double? {
        noiseFloorDecibels.isFinite ? speechLevelDecibels - noiseFloorDecibels : nil
    }

    /// Measures `samples`, carrying the timeline's `gaps`, or `nil` when they hold fewer than two whole frames.
    public static func measure(
        samples: [Float], sampleRate: Int, gaps: CaptureGaps = .none
    ) -> CaptureQuality? {
        guard sampleRate > 0 else { return nil }
        let frameLength = max(1, Int(VoiceActivity.frameDuration * Double(sampleRate)))
        let loudness = VoiceActivity.frameLoudness(of: samples, frameLength: frameLength).sorted()
        guard loudness.count >= 2 else { return nil }
        let speech = VoiceActivity.percentile(loudness, VoiceActivity.ceilingPercentile)
        let noise = VoiceActivity.percentile(loudness, VoiceActivity.floorPercentile)

        var peak: Float = 0
        var clipped = 0
        var sum: Double = 0
        for sample in samples where sample.isFinite {
            let magnitude = Swift.abs(sample)
            peak = Swift.max(peak, magnitude)
            if magnitude >= clippingMagnitude { clipped += 1 }
            sum += Double(sample)
        }
        return CaptureQuality(
            peakDecibels: decibels(peak),
            speechLevelDecibels: decibels(speech),
            noiseFloorDecibels: decibels(noise),
            clippedFraction: Double(clipped) / Double(samples.count),
            offset: sum / Double(samples.count),
            sampleRate: sampleRate,
            gaps: gaps)
    }

    /// A linear magnitude relative to full scale, in decibels.
    static func decibels(_ magnitude: Float) -> Double {
        magnitude > 0 ? 20 * log10(Double(magnitude)) : -.infinity
    }
}
