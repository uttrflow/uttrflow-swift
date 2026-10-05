// Builds the non-speech corpus and scores what a recogniser types from it: invented text and looped phrases.
private import Foundation
private import UttrflowCore

/// One kind of sound that holds no words of its own; see `Docs/silence.md`.
public enum NonSpeechKind: String, CaseIterable, Sendable {
    case silence, roomTone, hiss, keyboard, breath, music

    /// Seconds of each generated clip.
    public static let clipSeconds = 5.0

    /// `seconds` of this sound as canonical samples, the same for the same `seed`.
    public func samples(seconds: Double = clipSeconds, seed: UInt64) -> [Float] {
        let count = Int(seconds * Double(AudioSamples.canonicalSampleRate))
        var random = SeededNoise(seed: seed)
        switch self {
        case .silence: return [Float](repeating: 0, count: count)
        case .roomTone: return NonSpeechSound.lowPassed(random.white(count), keeping: 0.05, rms: -60)
        case .hiss: return NonSpeechSound.scaled(random.white(count), toRMSDecibels: -30)
        case .keyboard: return NonSpeechSound.clicks(count: count, every: 0.18, random: &random)
        case .breath: return NonSpeechSound.breaths(count: count, random: &random)
        case .music: return NonSpeechSound.chords(count: count, rms: -20)
        }
    }
}

/// A repeatable white-noise source, so a clip is the same on every run and every Mac.
public struct SeededNoise {
    private var state: UInt64

    public init(seed: UInt64) { state = seed &+ 0x9E37_79B9_7F4A_7C15 }

    /// The next value, uniform in -1...1 (splitmix64).
    public mutating func next() -> Float {
        state &+= 0x9E37_79B9_7F4A_7C15
        var mixed = state
        mixed = (mixed ^ (mixed >> 30)) &* 0xBF58_476D_1CE4_E5B9
        mixed = (mixed ^ (mixed >> 27)) &* 0x94D0_49BB_1331_11EB
        mixed ^= mixed >> 31
        return Float(Double(mixed >> 11) / Double(1 << 53) * 2 - 1)
    }

    /// `count` values of white noise.
    public mutating func white(_ count: Int) -> [Float] { (0..<count).map { _ in next() } }
}

/// The signal shapes the non-speech kinds are built from.
public enum NonSpeechSound {
    /// The root mean square of `samples`, in dBFS; minus infinity for silence.
    public static func rmsDecibels(of samples: [Float]) -> Double {
        guard !samples.isEmpty else { return -.infinity }
        let power = samples.reduce(0.0) { $0 + Double($1 * $1) } / Double(samples.count)
        return power > 0 ? 10 * log10(power) : -.infinity
    }

    /// `samples` scaled so their RMS sits at `decibels` dBFS; silence stays silent.
    public static func scaled(_ samples: [Float], toRMSDecibels decibels: Double) -> [Float] {
        let current = rmsDecibels(of: samples)
        guard current.isFinite else { return samples }
        let gain = Float(pow(10, (decibels - current) / 20))
        return samples.map { $0 * gain }
    }

    /// One-pole low-pass of `samples`, the rumble of a room rather than a hiss, at `rms` dBFS.
    static func lowPassed(_ samples: [Float], keeping coefficient: Float, rms: Double) -> [Float] {
        var level: Float = 0
        return scaled(
            samples.map {
                level += coefficient * ($0 - level); return level
            }, toRMSDecibels: rms)
    }

    /// Key presses: a 15 ms decaying burst every `every` seconds, jittered, peaking near -12 dBFS.
    static func clicks(count: Int, every: Double, random: inout SeededNoise) -> [Float] {
        let rate = Double(AudioSamples.canonicalSampleRate)
        let length = Int(0.015 * rate)
        var output = [Float](repeating: 0, count: count)
        var start = Int(0.2 * rate)
        while start + length < count {
            for index in 0..<length {
                output[start + index] = 0.25 * random.next() * Float(exp(-Double(index) / Double(length) * 5))
            }
            start += Int(every * rate * (0.6 + 0.8 * Double(abs(random.next()))))
        }
        return output
    }

    /// Breathing: a soft rumble that rises and falls once every 2.5 seconds, near -40 dBFS.
    static func breaths(count: Int, random: inout SeededNoise) -> [Float] {
        let rate = Double(AudioSamples.canonicalSampleRate)
        let rumble = lowPassed(random.white(count), keeping: 0.2, rms: -36)
        return rumble.enumerated().map { index, sample in
            let phase = Double(index) / rate / 2.5 * 2 * .pi
            return sample * Float(max(0, sin(phase)))
        }
    }

    /// Instrumental music: a three-note chord that changes every half second, at `rms` dBFS.
    static func chords(count: Int, rms: Double) -> [Float] {
        let rate = Double(AudioSamples.canonicalSampleRate)
        let roots = [220.0, 246.94, 196.0, 174.61]
        let chord = (0..<count).map { index -> Float in
            let time = Double(index) / rate
            let root = roots[Int(time / 0.5) % roots.count]
            return Float([1.0, 1.25, 1.5].reduce(0) { $0 + sin(2 * .pi * root * $1 * time) })
        }
        return scaled(chord, toRMSDecibels: rms)
    }
}

/// What one clip's transcript added that nobody said, and whether it looped.
public struct NonSpeechScore: Sendable, Equatable {
    /// Words after the last spoken word that the reference does not hold; every word for a clip with none.
    public let insertedWords: Int
    /// Whether one phrase of at least three words follows itself at least three times.
    public let looped: Bool
    /// Whether the words after the last spoken word repeat the recogniser's own prompt.
    public let echoedPrompt: Bool

    /// Scores normalised `hypothesis` words against what was said, `reference`, empty for a non-speech clip; `prompt` is the normalised conditioning text, empty without one.
    public init(reference: [String], hypothesis: [String], prompt: [String] = []) {
        let alignment = WordErrorRate.measure(reference: reference, hypothesis: hypothesis).alignment
        let tail = alignment.reversed().prefix { $0.kind == .insertion }
        insertedWords = tail.count
        looped = Self.loops(hypothesis)
        echoedPrompt = Self.echoes(Array(hypothesis.suffix(tail.count)), prompt: prompt)
    }

    /// Whether `inserted` is non-empty and made only of `prompt` words in prompt order.
    static func echoes(_ inserted: [String], prompt: [String]) -> Bool {
        guard !inserted.isEmpty, !prompt.isEmpty else { return false }
        var rest = prompt[...]
        for word in inserted {
            guard let found = rest.firstIndex(of: word) else { return false }
            rest = rest[(found + 1)...]
        }
        return true
    }

    /// The fewest words in one copy, and the fewest copies in a row, that count as a loop.
    public static let fewestLoopWords = 3
    public static let fewestLoopCopies = 3

    /// Whether `words` hold a phrase repeated back to back `fewestLoopCopies` times.
    static func loops(_ words: [String]) -> Bool {
        let longest = words.count / fewestLoopCopies
        guard longest >= fewestLoopWords else { return false }
        for length in fewestLoopWords...longest {
            for start in 0...(words.count - length * fewestLoopCopies) {
                let phrase = words[start..<(start + length)]
                let copies = (1..<fewestLoopCopies).allSatisfy { copy in
                    words[(start + copy * length)..<(start + (copy + 1) * length)] == phrase
                }
                if copies { return true }
            }
        }
        return false
    }
}

/// The two corpus rates: clips whose transcript invented text, and clips whose transcript looped.
public struct NonSpeechRates: Sendable, Equatable {
    public let clips: Int
    public let inserted: Int
    public let looped: Int
    public let echoed: Int

    public init(_ scores: [NonSpeechScore]) {
        clips = scores.count
        inserted = scores.count { $0.insertedWords > 0 }
        looped = scores.count { $0.looped }
        echoed = scores.count { $0.echoedPrompt }
    }

    public var insertionRate: Double { clips == 0 ? 0 : Double(inserted) / Double(clips) }
    public var loopRate: Double { clips == 0 ? 0 : Double(looped) / Double(clips) }
    public var echoRate: Double { clips == 0 ? 0 : Double(echoed) / Double(clips) }

    /// The gate's failures: each rate above its ceiling, named.
    public func exceeded(insertionCeiling: Double, loopCeiling: Double, echoCeiling: Double) -> [String] {
        var failures: [String] = []
        if insertionRate > insertionCeiling { failures.append("insertion rate") }
        if loopRate > loopCeiling { failures.append("repetition-loop rate") }
        if echoRate > echoCeiling { failures.append("prompt-echo rate") }
        return failures
    }
}
