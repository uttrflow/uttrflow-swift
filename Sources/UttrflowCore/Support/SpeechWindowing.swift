/// Cuts a recording into pieces the recogniser can take one at a time, at pauses. See `Docs/early-transcription.md`.
public struct SpeechWindowing: Sendable, Equatable {
    /// Audio collected before the window is checked for a cut, in seconds.
    public var minimumLength: Double

    /// Audio a window must hold before a long early pause may end it, in seconds.
    public var earlyLength: Double

    /// A pause this long ends a window before ``minimumLength``, in seconds.
    public var earlyPause: Double

    /// A pause this long ends a window that has reached ``minimumLength``, in seconds.
    public var sentencePause: Double

    /// A window this long begins accepting pauses shorter than ``sentencePause``, in seconds.
    public var comfortableLength: Double

    /// The shortest pause that may end a window as it approaches ``maximumLength``, in seconds.
    public var anyPause: Double

    /// A window never holds more than this, which is the recogniser's own window, in seconds.
    public var maximumLength: Double

    /// Speech a window must hold before a pause may end it, so one word after a long pause is never decoded alone, in seconds.
    public var minimumSpeech: Double

    public init(
        minimumLength: Double = 5, earlyLength: Double = 2.5, earlyPause: Double = 1.0,
        sentencePause: Double = 0.8,
        comfortableLength: Double = 15, anyPause: Double = 0.4, maximumLength: Double = 30,
        minimumSpeech: Double = 0.8
    ) {
        self.minimumLength = minimumLength
        self.earlyLength = earlyLength
        self.earlyPause = earlyPause
        self.sentencePause = sentencePause
        self.comfortableLength = comfortableLength
        self.anyPause = anyPause
        self.maximumLength = maximumLength
        self.minimumSpeech = minimumSpeech
    }

    /// The windowing the product ships with.
    public static let standard = SpeechWindowing()

    /// Where the window beginning at `start` ends, or `nil` while the audio so far gives no reason to end it.
    public func nextCut(
        in samples: [Float], sampleRate: Int, from start: Int, boundaries: [Int] = []
    ) -> Int? {
        // A discontinuity always ends a window, at a pause before it when there is one.
        if let boundary = boundaries.first(where: { $0 > start && $0 < samples.count }) {
            return nextCut(in: Array(samples[..<boundary]), sampleRate: sampleRate, from: start)
                ?? boundary
        }
        guard sampleRate > 0, start >= 0, start < samples.count else { return nil }
        let available = samples.count - start
        guard Double(available) >= minimumLength * Double(sampleRate) else { return nil }

        let limit = Swift.min(samples.count, start + Int(maximumLength * Double(sampleRate)))
        let frameLength = Swift.max(1, Int(VoiceActivity.frameDuration * Double(sampleRate)))
        let loudness = VoiceActivity.frameLoudness(
            of: Array(samples[start..<limit]), frameLength: frameLength)
        // A recording with no speech left in it is one piece, whatever its length.
        let hasSpeechAhead =
            (loudness.max() ?? 0) >= VoiceActivity.absoluteFloor
            || VoiceActivity.hasSpeech(in: samples[limit...], frameLength: frameLength)
        guard hasSpeechAhead else { return nil }

        let sorted = loudness.sorted()
        let floor = VoiceActivity.percentile(sorted, 0.1)
        let threshold = VoiceActivity.threshold(forFloor: floor)

        let earliest = Int(Swift.min(earlyLength, minimumLength) / VoiceActivity.frameDuration)
        let ordinary = Int(minimumLength / VoiceActivity.frameDuration)
        let comfortable = Int(comfortableLength / VoiceActivity.frameDuration)
        let maximum = Int(maximumLength / VoiceActivity.frameDuration)
        var spoken = [0]
        for value in loudness { spoken.append(spoken[spoken.count - 1] + (value >= threshold ? 1 : 0)) }
        if let pause = firstPause(
            in: loudness, below: threshold, after: earliest, ordinaryAt: ordinary,
            comfortableAt: comfortable, maximumAt: maximum, spoken: spoken)
        {
            return start + pause * frameLength
        }
        guard limit - start >= Int(maximumLength * Double(sampleRate)) else { return nil }
        // A quiet stretch separates words more reliably than a single stop-closure frame.
        let quietFrames = Swift.max(1, Int((0.12 / VoiceActivity.frameDuration).rounded()))
        let candidates = comfortable..<(loudness.count - quietFrames + 1)
        let quietest = candidates.min { left, right in
            let leftMean = loudness[left..<(left + quietFrames)].reduce(0, +)
            let rightMean = loudness[right..<(right + quietFrames)].reduce(0, +)
            return leftMean < rightMean
        }
        let frame = quietest.map { $0 + quietFrames / 2 } ?? loudness.count
        return start + frame * frameLength
    }

    /// Every window in a finished recording; a last one holding only a word or two joins the window before it.
    public func windows(
        in samples: [Float], sampleRate: Int, from start: Int = 0,
        joiningPreviousWindowFrom previousStart: Int? = nil, boundaries: [Int] = []
    ) -> [Range<Int>] {
        var windows: [Range<Int>] = []
        var cursor = start
        while let end = nextCut(
            in: samples, sampleRate: sampleRate, from: cursor, boundaries: boundaries), end > cursor
        {
            windows.append(cursor..<end)
            cursor = end
        }
        guard cursor < samples.count else { return windows }
        if isFragment(samples[cursor...], sampleRate: sampleRate) {
            let previous = windows.last?.lowerBound ?? previousStart
            let crossesBoundary = boundaries.contains { $0 > (previous ?? cursor) && $0 <= cursor }
            if let previous, previous >= 0, previous <= samples.count, !crossesBoundary,
                Double(samples.count - previous) <= maximumLength * Double(sampleRate)
            {
                if windows.isEmpty {
                    windows.append(previous..<samples.count)
                } else {
                    windows[windows.count - 1] = previous..<samples.count
                }
            } else {
                windows.append(cursor..<samples.count)
            }
        } else {
            windows.append(cursor..<samples.count)
        }
        return windows
    }

    /// Whether the audio holds some speech but less than ``minimumSpeech`` of it.
    private func isFragment(_ samples: ArraySlice<Float>, sampleRate: Int) -> Bool {
        let frameLength = Swift.max(1, Int(VoiceActivity.frameDuration * Double(sampleRate)))
        let loudness = VoiceActivity.frameLoudness(of: Array(samples), frameLength: frameLength)
        let threshold = VoiceActivity.threshold(forFloor: VoiceActivity.percentile(loudness.sorted(), 0.1))
        let voiced = loudness.filter { $0 >= threshold }.count
        return voiced > 0 && Double(voiced) * VoiceActivity.frameDuration < minimumSpeech
    }

    /// The middle frame of the first quiet run long enough for where that middle falls, counting a run still open at the end.
    private func firstPause(
        in loudness: [Float], below threshold: Float, after earliest: Int,
        ordinaryAt ordinary: Int, comfortableAt comfortable: Int, maximumAt maximum: Int,
        spoken: [Int]
    ) -> Int? {
        let speechFrames = Int((minimumSpeech / VoiceActivity.frameDuration).rounded())
        let earlyFrames = Swift.max(1, Int(earlyPause / VoiceActivity.frameDuration))
        let longPauseFrames = Swift.max(1, Int((1.5 / VoiceActivity.frameDuration).rounded()))
        let sentenceFrames = Swift.max(1, Int(sentencePause / VoiceActivity.frameDuration))
        let anyFrames = Swift.max(1, Int(anyPause / VoiceActivity.frameDuration))
        var runStart: Int?
        // A long pause can start before the early window is long enough to cut.
        for index in 0..<loudness.count {
            if loudness[index] < threshold {
                if runStart == nil { runStart = index }
            } else if let began = runStart {
                if let cut = pauseCut(
                    in: began..<index, earliest: earliest, ordinary: ordinary,
                    comfortable: comfortable, maximum: maximum, earlyFrames: earlyFrames,
                    longPauseFrames: longPauseFrames, sentenceFrames: sentenceFrames,
                    anyFrames: anyFrames, spoken: spoken, speechFrames: speechFrames)
                {
                    return cut
                }
                runStart = nil
            }
        }
        if let began = runStart,
            let cut = pauseCut(
                in: began..<loudness.count, earliest: earliest, ordinary: ordinary,
                comfortable: comfortable, maximum: maximum, earlyFrames: earlyFrames,
                longPauseFrames: longPauseFrames, sentenceFrames: sentenceFrames,
                anyFrames: anyFrames, spoken: spoken, speechFrames: speechFrames)
        {
            return cut
        }
        return nil
    }

    /// A long pause may end a piece at the earliest safe boundary even when it began before that boundary.
    private func pauseCut(
        in run: Range<Int>, earliest: Int, ordinary: Int, comfortable: Int, maximum: Int,
        earlyFrames: Int, longPauseFrames: Int, sentenceFrames: Int, anyFrames: Int,
        spoken: [Int], speechFrames: Int
    ) -> Int? {
        let rawMiddle = run.lowerBound + run.count / 2
        let cut = Swift.max(rawMiddle, earliest)
        guard cut < run.upperBound else { return nil }
        let longEnough: Bool
        if run.lowerBound < earliest {
            longEnough = run.count >= longPauseFrames
        } else {
            longEnough =
                middle(
                    ofRun: run, ordinary, comfortable, maximum, earlyFrames, sentenceFrames,
                    anyFrames) != nil
        }
        guard longEnough, spoken[cut] >= speechFrames else { return nil }
        return cut
    }

    /// The middle of `run` when a cut may fall there and the pause is long enough for where it falls, else `nil`.
    private func middle(
        ofRun run: Range<Int>, _ ordinary: Int, _ comfortable: Int, _ maximum: Int,
        _ earlyFrames: Int, _ sentenceFrames: Int, _ anyFrames: Int
    ) -> Int? {
        let middle = run.lowerBound + run.count / 2
        let required: Int
        if middle >= comfortable {
            let progress =
                maximum > comfortable
                ? Swift.min(1, Double(middle - comfortable) / Double(maximum - comfortable))
                : 1
            required = Int(
                (Double(sentenceFrames) + progress * Double(anyFrames - sentenceFrames)).rounded(.up))
        } else {
            required = middle >= ordinary ? sentenceFrames : earlyFrames
        }
        guard run.count >= required else { return nil }
        return middle
    }
}
