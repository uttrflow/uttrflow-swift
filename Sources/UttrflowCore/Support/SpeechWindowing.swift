/// Cuts a recording into pieces the recogniser can take one at a time, at pauses. See `Docs/early-transcription.md`.
public struct SpeechWindowing: Sendable, Equatable {
    /// Audio a window must hold before any pause is allowed to end it, in seconds.
    public var minimumLength: Double

    /// A pause this long ends a window that has reached ``minimumLength``, in seconds.
    public var sentencePause: Double

    /// A window this long is ended by the shorter ``anyPause`` instead, in seconds.
    public var comfortableLength: Double

    /// A pause this long ends a window that has reached ``comfortableLength``, in seconds.
    public var anyPause: Double

    /// A window never holds more than this, which is the recogniser's own window, in seconds.
    public var maximumLength: Double

    public init(
        minimumLength: Double = 5, sentencePause: Double = 0.8,
        comfortableLength: Double = 15, anyPause: Double = 0.4, maximumLength: Double = 30
    ) {
        self.minimumLength = minimumLength
        self.sentencePause = sentencePause
        self.comfortableLength = comfortableLength
        self.anyPause = anyPause
        self.maximumLength = maximumLength
    }

    /// The windowing the product ships with.
    public static let standard = SpeechWindowing()

    /// Where the window beginning at `start` ends, or `nil` while the audio so far gives no reason to end it.
    public func nextCut(in samples: [Float], sampleRate: Int, from start: Int) -> Int? {
        guard sampleRate > 0, start >= 0, start < samples.count else { return nil }
        let available = samples.count - start
        guard Double(available) >= minimumLength * Double(sampleRate) else { return nil }

        let limit = Swift.min(samples.count, start + Int(maximumLength * Double(sampleRate)))
        let frameLength = Swift.max(1, Int(VoiceActivity.frameDuration * Double(sampleRate)))
        let everything = VoiceActivity.frameLoudness(
            of: Array(samples[start...]), frameLength: frameLength)
        // A recording with no speech left in it is one piece, whatever its length.
        guard (everything.max() ?? 0) >= VoiceActivity.absoluteFloor else { return nil }

        let loudness = Array(everything.prefix((limit - start) / frameLength))
        let sorted = loudness.sorted()
        let floor = VoiceActivity.percentile(sorted, 0.1)
        // Louder than the room by a margin, but never so high that steady speech counts as quiet.
        let threshold = Swift.max(
            VoiceActivity.absoluteFloor,
            Swift.min(floor * VoiceActivity.signalToNoise, VoiceActivity.assumedSpeechLevel))

        let earliest = Int(minimumLength / VoiceActivity.frameDuration)
        let comfortable = Int(comfortableLength / VoiceActivity.frameDuration)
        if let pause = firstPause(
            in: loudness, below: threshold, after: earliest, comfortableAt: comfortable)
        {
            return start + pause * frameLength
        }
        return limit - start >= Int(maximumLength * Double(sampleRate)) ? limit : nil
    }

    /// Every window in a finished recording, the last one taken whole however short it is.
    public func windows(in samples: [Float], sampleRate: Int, from start: Int = 0) -> [Range<Int>] {
        var windows: [Range<Int>] = []
        var cursor = start
        while let end = nextCut(in: samples, sampleRate: sampleRate, from: cursor), end > cursor {
            windows.append(cursor..<end)
            cursor = end
        }
        if cursor < samples.count { windows.append(cursor..<samples.count) }
        return windows
    }

    /// The middle frame of the first quiet run long enough for where it falls, counting a run still open at the end.
    private func firstPause(
        in loudness: [Float], below threshold: Float, after earliest: Int, comfortableAt comfortable: Int
    ) -> Int? {
        let sentenceFrames = Swift.max(1, Int(sentencePause / VoiceActivity.frameDuration))
        let anyFrames = Swift.max(1, Int(anyPause / VoiceActivity.frameDuration))
        var runStart: Int?
        for index in earliest..<loudness.count {
            if loudness[index] < threshold {
                if runStart == nil { runStart = index }
            } else if let began = runStart {
                if let middle = middle(ofRun: began..<index, comfortable, sentenceFrames, anyFrames) {
                    return middle
                }
                runStart = nil
            }
        }
        if let began = runStart {
            return middle(ofRun: began..<loudness.count, comfortable, sentenceFrames, anyFrames)
        }
        return nil
    }

    /// The middle of `run` when it is long enough for its position, else `nil`.
    private func middle(
        ofRun run: Range<Int>, _ comfortable: Int, _ sentenceFrames: Int, _ anyFrames: Int
    ) -> Int? {
        let required = run.lowerBound >= comfortable ? anyFrames : sentenceFrames
        guard run.count >= required else { return nil }
        return run.lowerBound + run.count / 2
    }
}
