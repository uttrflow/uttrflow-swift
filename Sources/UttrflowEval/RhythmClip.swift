// A long-form case spoken by a synthetic speaker with a chosen rhythm, and the gaps read back from its audio.
private import UttrflowCore

/// How one synthetic speaker paces a dictation: the voice and rate, and how long they hesitate and break.
public struct SpeakerProfile: Sendable, Equatable {
    public let voice: String
    /// Words a minute for `say -r`; the voice's own rate when `nil`.
    public let rate: Int?
    public let name: String
    /// Silence at a hesitation inside a sentence, in milliseconds; zero for none.
    public let hesitationMilliseconds: Int
    /// Silence at a break the case marks, in milliseconds.
    public let breakMilliseconds: Int

    public init(voice: String, rate: Int?, name: String, hesitation: Int, breakLength: Int) {
        self.voice = voice
        self.rate = rate
        self.name = name
        hesitationMilliseconds = hesitation
        breakMilliseconds = breakLength
    }

    /// A fast speaker whose breaks are short, an ordinary one, and a slow one who hesitates for nearly a second.
    public static func paces(voice: String) -> [SpeakerProfile] {
        [
            SpeakerProfile(voice: voice, rate: 230, name: "fast", hesitation: 0, breakLength: 500),
            SpeakerProfile(voice: voice, rate: nil, name: "ordinary", hesitation: 250, breakLength: 1000),
            SpeakerProfile(voice: voice, rate: 120, name: "slow", hesitation: 900, breakLength: 1800),
        ]
    }
}

/// A spoken dictation built from phrases joined by silences of known length.
public struct RhythmClip: Sendable, Equatable {
    /// A phrase to speak, and the silence built after it.
    public struct Part: Sendable, Equatable {
        public let text: String
        public let silenceMilliseconds: Int
        public let isBreak: Bool
    }

    /// Where a silence was built, in samples, and whether it stands for a break.
    struct Silence: Sendable, Equatable {
        let range: Range<Int>
        let isBreak: Bool
    }

    /// Every ninth word a hesitation may fall after, counted from this offset.
    private static let hesitationOffset = 4
    private static let hesitationSpacing = 9

    public let samples: [Float]
    let silences: [Silence]

    /// The phrases of `testCase` for `profile`: a break after each word the case pauses on, a hesitation between.
    public static func parts(of testCase: EvaluationCase, for profile: SpeakerProfile) -> [Part] {
        let words = WordTokens.words(testCase.spoken, .display)
        let breaks = Set(testCase.pausedAfter)
        var parts: [Part] = []
        var phrase: [String] = []
        for (index, word) in words.enumerated() {
            phrase.append(word)
            let isLast = index == words.count - 1
            let hesitates =
                profile.hesitationMilliseconds > 0 && !breaks.contains(index)
                && index % Self.hesitationSpacing == Self.hesitationOffset
            guard !isLast, breaks.contains(index) || hesitates else { continue }
            let isBreak = breaks.contains(index)
            parts.append(
                Part(
                    text: phrase.joined(separator: " "),
                    silenceMilliseconds: isBreak ? profile.breakMilliseconds : profile.hesitationMilliseconds,
                    isBreak: isBreak))
            phrase = []
        }
        if !phrase.isEmpty {
            parts.append(Part(text: phrase.joined(separator: " "), silenceMilliseconds: 0, isBreak: false))
        }
        return parts
    }

    /// The speech of each part cut to its words, joined by its silence, over seeded room noise; nil when a part has none.
    public static func joined(_ parts: [Part], speech: [[Float]], roomDecibels: Double) -> RhythmClip? {
        let rate = AudioSamples.canonicalSampleRate
        var samples: [Float] = []
        var silences: [Silence] = []
        for (part, heard) in zip(parts, speech) {
            guard let range = TailCut.speechRange(of: heard) else { return nil }
            samples += heard[range]
            guard part.silenceMilliseconds > 0 else { continue }
            let length = part.silenceMilliseconds * rate / 1000
            silences.append(Silence(range: samples.count..<(samples.count + length), isBreak: part.isBreak))
            samples += [Float](repeating: 0, count: length)
        }
        return RhythmClip(samples: PauseTiming.withRoom(samples, decibels: roomDecibels), silences: silences)
    }

    /// Every quiet run between words, in the order heard, each marked a break when it holds a built break silence.
    public func observations() -> [GapObservation] {
        let rate = AudioSamples.canonicalSampleRate
        return VoiceActivity.quietRuns(in: samples, sampleRate: rate).map { run in
            let built = silences.filter { $0.range.overlaps(run) }
            return GapObservation(
                milliseconds: Double(run.count) * 1000 / Double(rate), isBreak: built.contains { $0.isBreak })
        }
    }
}
