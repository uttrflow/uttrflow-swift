// Compares the gap between two words in the recogniser's word times with the pause built into the audio.
private import Foundation
public import UttrflowCore

/// Builds a clip with a pause of known length and reads that pause back by the two measures a dictation has.
public enum PauseTiming {
    /// A clip of two phrases a known pause apart: the first ends at `firstEnd`, the second starts at `secondStart`.
    public struct Clip: Sendable, Equatable {
        public let samples: [Float]
        public let firstEnd: Int
        public let secondStart: Int
    }

    /// `first`, a pause of `gapMilliseconds`, then `second`, each cut to its speech, over seeded room noise; nil without speech.
    public static func joined(
        _ first: [Float], _ second: [Float], gapMilliseconds: Int, roomDecibels: Double
    ) -> Clip? {
        guard let head = TailCut.speechRange(of: first), let tail = TailCut.speechRange(of: second) else {
            return nil
        }
        let rate = AudioSamples.canonicalSampleRate
        let gap = max(0, gapMilliseconds) * rate / 1000
        let speech = Array(first[head]) + [Float](repeating: 0, count: gap) + Array(second[tail])
        let samples = withRoom(speech, decibels: roomDecibels)
        return Clip(samples: samples, firstEnd: head.count, secondStart: head.count + gap)
    }

    /// `speech` with seeded room noise under it, so a pause is a quiet room and not digital zeros.
    public static func withRoom(_ speech: [Float], decibels: Double) -> [Float] {
        let level = Float(pow(10, decibels / 20)) * 3.46
        var state: UInt64 = 0x9E37_79B9_7F4A_7C15
        return speech.map { sample -> Float in
            state = state &* 6_364_136_223_846_793_005 &+ 1_442_695_040_888_963_407
            return sample + (Float(state >> 40) / Float(1 << 24) - 0.5) * level
        }
    }

    /// The quiet `VoiceActivity` finds after the first phrase, read from the clip as far as the second begins.
    public static func voiceActivityGapMilliseconds(in clip: Clip) -> Double? {
        let heard = Array(clip.samples[..<clip.secondStart])
        guard
            let quiet = VoiceActivity.trailingSilence(in: heard, sampleRate: AudioSamples.canonicalSampleRate)
        else { return nil }
        return quiet / .milliseconds(1)
    }

    /// The gap between the word at `index` and the word after it, in milliseconds; nil when either is untimed.
    public static func wordGapMilliseconds(after index: Int, in words: [TranscribedWord]) -> Double? {
        guard words.indices.contains(index), words.indices.contains(index + 1),
            let end = words[index].end, let start = words[index + 1].start
        else { return nil }
        return (start - end) / .milliseconds(1)
    }

    /// The shortest pause from which every length has median error within `tolerance` and a gap of `shown` in `reliability` of trials.
    public static func trustedMinimum(
        _ trials: [Trial], tolerance: Double, shown: Double, reliability: Double
    ) -> Int? {
        let lengths = Set(trials.map(\.truth)).sorted()
        var trusted: Int?
        for length in lengths.reversed() {
            let rows = trials.filter { $0.truth == length }
            let timed = rows.compactMap(\.wordGap)
            guard !timed.isEmpty,
                median(timed.map { abs($0 - Double(length)) }) <= tolerance,
                Double(timed.filter { $0 >= shown }.count) / Double(rows.count) >= reliability
            else { break }
            trusted = length
        }
        return trusted
    }

    /// The median of `values`, the mean of the middle two when the count is even; zero when empty.
    public static func median(_ values: [Double]) -> Double {
        let sorted = values.sorted()
        guard !sorted.isEmpty else { return 0 }
        let middle = sorted.count / 2
        return sorted.count.isMultiple(of: 2) ? (sorted[middle - 1] + sorted[middle]) / 2 : sorted[middle]
    }

    /// One built pause, read back by both measures. A nil measure means the boundary could not be found.
    public struct Trial: Sendable, Equatable {
        public let kind: String
        public let truth: Int
        public let wordGap: Double?
        public let audioGap: Double?

        public init(kind: String, truth: Int, wordGap: Double?, audioGap: Double?) {
            self.kind = kind
            self.truth = truth
            self.wordGap = wordGap
            self.audioGap = audioGap
        }
    }

    /// The table by pause length and by word type; `pause` is the length that counts as a real pause.
    public static func markdown(_ trials: [Trial], skipped: Int, pause: Double = 300) -> String {
        let head = [
            "| | Trials | Timed | Word-time error ms (median) | Absolute error ms (median) | "
                + "Audio error ms (median) | Real pause missing | Pause invented |",
            "|---|---|---|---|---|---|---|---|",
        ]
        let lengths = Set(trials.map(\.truth)).sorted()
        let kinds = Array(Set(trials.map(\.kind))).sorted()
        let long = lengths.filter { Double($0) >= pause }
        let byLength = lengths.map { length in
            row("\(length) ms", trials.filter { $0.truth == length }, pause: pause)
        }
        let byKind = kinds.map { kind in row(kind, trials.filter { $0.kind == kind }, pause: pause) }
        let byKindLong = kinds.map { kind in
            row(kind, trials.filter { $0.kind == kind && long.contains($0.truth) }, pause: pause)
        }
        return
            (["By pause length", ""] + head + byLength + ["", "By word before the pause", ""] + head + byKind
            + ["", "By word before the pause, pauses of \(Int(pause)) ms and longer only", ""] + head
            + byKindLong
            + ["", "Clips skipped because the recogniser wrote a different number of words: \(skipped)"])
            .joined(separator: "\n")
    }

    private static func row(_ label: String, _ rows: [Trial], pause: Double) -> String {
        let timed = rows.compactMap(\.wordGap)
        let errors = rows.compactMap { trial in trial.wordGap.map { $0 - Double(trial.truth) } }
        let audio = rows.compactMap { trial in trial.audioGap.map { $0 - Double(trial.truth) } }
        let real = rows.filter { Double($0.truth) >= pause }
        let short = rows.filter { Double($0.truth) < pause }
        let absent = real.filter { ($0.wordGap ?? 0) < pause }.count
        let made = short.filter { ($0.wordGap ?? 0) >= pause }.count
        return "| \(label) | \(rows.count) | \(timed.count) | \(signed(median(errors))) | "
            + "\(String(format: "%.0f", median(errors.map(abs)))) | \(signed(median(audio))) | "
            + "\(percent(absent, real.count)) | \(percent(made, short.count)) |"
    }

    private static func signed(_ value: Double) -> String { String(format: "%+.0f", value) }

    private static func percent(_ count: Int, _ total: Int) -> String {
        total == 0 ? "n/a" : String(format: "%.0f%%", Double(count) / Double(total) * 100)
    }
}
