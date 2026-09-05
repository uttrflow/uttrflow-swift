/// Finds the speech inside a recording, and says when there is none. See `Docs/silence.md`.
public enum VoiceActivity: Sendable {
    /// Loudness is measured over frames this long, in seconds.
    static let frameDuration = 0.02

    /// A frame this quiet is silence however quiet the room is, at about -46 dBFS.
    static let absoluteFloor: Float = 0.005

    /// Speech is this many times louder than the room it was spoken in.
    static let signalToNoise: Float = 3

    /// A burst shorter than this is a click or a bump rather than a word, in seconds.
    static let minimumSpeech = 0.12

    /// Above this, audio is speech whatever its shape, at about -26 dBFS.
    static let assumedSpeechLevel: Float = 0.05

    /// Audio kept either side of the speech, in seconds, so no onset is clipped.
    static let margin = 0.2

    /// The samples worth transcribing, or `nil` when the recording holds no speech.
    public static func speechRange(in samples: [Float], sampleRate: Int) -> Range<Int>? {
        let frameLength = max(1, Int(frameDuration * Double(sampleRate)))
        let loudness = frameLoudness(of: samples, frameLength: frameLength)
        guard loudness.count >= 2 else { return nil }

        let sorted = loudness.sorted()
        let floor = percentile(sorted, 0.1)
        let ceiling = percentile(sorted, 0.95)

        // A quiet room fails the first test; a fan passes it and fails the second.
        guard ceiling >= absoluteFloor else { return nil }
        guard ceiling >= assumedSpeechLevel || ceiling >= floor * signalToNoise else { return nil }

        let threshold = Swift.max(absoluteFloor, floor * signalToNoise)
        let minimumFrames = Swift.max(1, Int(minimumSpeech / frameDuration))
        guard let voiced = voicedFrames(in: loudness, above: threshold, lasting: minimumFrames)
        else {
            // Loud and modulated, but no run long enough to point at: keep all of it.
            return samples.isEmpty ? nil : 0..<samples.count
        }

        let margin = Int(Self.margin * Double(sampleRate))
        let start = Swift.max(0, voiced.lowerBound * frameLength - margin)
        let end = Swift.min(samples.count, voiced.upperBound * frameLength + margin)
        return start < end ? start..<end : nil
    }

    /// Root-mean-square loudness of each whole frame, ignoring any partial last one.
    private static func frameLoudness(of samples: [Float], frameLength: Int) -> [Float] {
        var loudness: [Float] = []
        loudness.reserveCapacity(samples.count / frameLength)
        var start = 0
        while start + frameLength <= samples.count {
            var sum: Float = 0
            for index in start..<(start + frameLength) {
                let sample = samples[index]
                // A `nan` from a misbehaving driver compares false against every threshold.
                if sample.isFinite { sum += sample * sample }
            }
            loudness.append((sum / Float(frameLength)).squareRoot())
            start += frameLength
        }
        return loudness
    }

    /// The value at `fraction` through an already-sorted list.
    private static func percentile(_ sorted: [Float], _ fraction: Double) -> Float {
        guard !sorted.isEmpty else { return 0 }
        let index = Int((Double(sorted.count - 1) * fraction).rounded())
        return sorted[Swift.min(Swift.max(index, 0), sorted.count - 1)]
    }

    /// First to last frame belonging to a run of at least `minimumFrames` above `threshold`.
    private static func voicedFrames(
        in loudness: [Float], above threshold: Float, lasting minimumFrames: Int
    ) -> Range<Int>? {
        var first: Int?
        var last: Int?
        var runStart: Int?
        for (index, value) in loudness.enumerated() {
            if value >= threshold {
                if runStart == nil { runStart = index }
            } else if let start = runStart {
                if index - start >= minimumFrames {
                    if first == nil { first = start }
                    last = index
                }
                runStart = nil
            }
        }
        // A run still open at the end counts: speech need not stop before the key does.
        if let start = runStart, loudness.count - start >= minimumFrames {
            if first == nil { first = start }
            last = loudness.count
        }
        guard let first, let last else { return nil }
        return first..<last
    }
}

/// Speech cut out of a longer recording, and where in it the cut began.
public struct IsolatedSpeech: Sendable, Equatable {
    public let audio: AudioSamples
    /// How far into the recording the speech starts, so timings can be put back.
    public let start: Duration

    public init(audio: AudioSamples, start: Duration) {
        self.audio = audio
        self.start = start
    }
}

extension AudioSamples {
    /// The speech in this recording, or `nil` when it holds none.
    public func speechOnly() -> IsolatedSpeech? {
        guard let range = VoiceActivity.speechRange(in: samples, sampleRate: sampleRate),
            let trimmed = AudioSamples(samples: Array(samples[range]), sampleRate: sampleRate)
        else { return nil }
        return IsolatedSpeech(
            audio: trimmed,
            start: .seconds(Double(range.lowerBound) / Double(sampleRate)))
    }
}
