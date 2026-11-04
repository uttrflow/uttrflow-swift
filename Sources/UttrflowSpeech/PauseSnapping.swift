// Puts the pauses of a transcription where the audio shows them, since the word times do not.
public import UttrflowCore

/// Sets the gap between two words to the quiet the audio holds there; see `Docs/pause-timing.md`.
public enum PauseSnapping {
    /// The shortest quiet taken as a pause; shorter dips are the closure of a stop consonant.
    static let minimumPause: Duration = .milliseconds(100)

    /// The shortest word-time gap taken as invented when the audio holds no quiet under it.
    static let inventedGap: Duration = .milliseconds(300)

    /// How far a word boundary may lie from a quiet run and still be where that pause was spoken.
    static let tolerance: Duration = .milliseconds(150)

    /// `transcription` with each word gap timed by the quiet in `audio`, left as heard when the audio holds none.
    public static func snapped(
        _ transcription: Transcription, to audio: AudioSamples, startingAt offset: Duration
    ) -> Transcription {
        let quiet = quietRuns(in: audio, startingAt: offset)
        guard !quiet.isEmpty else { return transcription }
        var words = transcription.segments.map(\.words)
        var timed: [Position] = []
        for segment in words.indices {
            for word in words[segment].indices
            where words[segment][word].start != nil && words[segment][word].end != nil {
                timed.append(Position(segment: segment, word: word))
            }
        }
        guard timed.count > 1 else { return transcription }

        func span(_ index: Int) -> (start: Duration, end: Duration) {
            let word = words[timed[index].segment][timed[index].word]
            return (word.start ?? .zero, word.end ?? .zero)
        }
        func place(_ index: Int, start: Duration? = nil, end: Duration? = nil) {
            let at = timed[index]
            let word = words[at.segment][at.word]
            words[at.segment][at.word] = word.timed(start: start ?? word.start, end: end ?? word.end)
        }

        var claimed: Set<Int> = []
        for run in quiet {
            guard let boundary = boundary(of: run, among: Array(timed.indices.dropLast()), span: span),
                !claimed.contains(boundary)
            else { continue }
            let before = span(boundary)
            let after = span(boundary + 1)
            guard run.lowerBound > before.start, run.upperBound < after.end else { continue }
            claimed.insert(boundary)
            place(boundary, end: min(before.end, run.lowerBound))
            place(boundary + 1, start: max(after.start, run.upperBound))
        }
        for boundary in timed.indices.dropLast() where !claimed.contains(boundary) {
            let before = span(boundary)
            let after = span(boundary + 1)
            let gap = after.start - before.end
            guard gap >= inventedGap, quietLength(under: before.end..<after.start, in: quiet) * 2 < gap else {
                continue
            }
            place(boundary, end: after.start)
        }

        return Transcription(
            text: transcription.text, detectedLanguage: transcription.detectedLanguage,
            segments: zip(transcription.segments, words).map {
                TranscriptionSegment(
                    text: $0.text, start: $0.start, end: $0.end, words: $1, reliability: $0.reliability)
            },
            audioDuration: transcription.audioDuration, effort: transcription.effort,
            vocabularyPrompt: transcription.vocabularyPrompt, conditioning: transcription.conditioning,
            leadingSilence: transcription.leadingSilence, trailingSilence: transcription.trailingSilence)
    }

    private struct Position {
        let segment: Int
        let word: Int
    }

    /// The pauses of `audio` as spans of the recording, with the audio starting `offset` into it.
    private static func quietRuns(in audio: AudioSamples, startingAt offset: Duration) -> [Range<Duration>] {
        let rate = Double(audio.sampleRate)
        return VoiceActivity.quietRuns(in: audio.samples, sampleRate: audio.sampleRate).compactMap { run in
            let start = offset + .seconds(Double(run.lowerBound) / rate)
            let end = offset + .seconds(Double(run.upperBound) / rate)
            return end - start >= minimumPause ? start..<end : nil
        }
    }

    /// The boundary, after the word at the index returned, that lies nearest `run` and within ``tolerance`` of it.
    private static func boundary(
        of run: Range<Duration>, among candidates: [Int], span: (Int) -> (start: Duration, end: Duration)
    ) -> Int? {
        func distance(_ boundary: Int) -> Duration {
            let middle = (span(boundary).end + span(boundary + 1).start) / 2
            if middle < run.lowerBound { return run.lowerBound - middle }
            if middle > run.upperBound { return middle - run.upperBound }
            return .zero
        }
        func offset(_ boundary: Int) -> Duration {
            let end = span(boundary).end
            return end < run.lowerBound ? run.lowerBound - end : end - run.lowerBound
        }
        return candidates.filter { distance($0) <= tolerance }
            .min { (distance($0), offset($0)) < (distance($1), offset($1)) }
    }

    /// How much of `window` the quiet runs cover.
    private static func quietLength(under window: Range<Duration>, in runs: [Range<Duration>]) -> Duration {
        runs.reduce(.zero) { total, run in
            let overlap = min(run.upperBound, window.upperBound) - max(run.lowerBound, window.lowerBound)
            return overlap > .zero ? total + overlap : total
        }
    }
}
