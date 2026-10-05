// Recovers the audio after a decode that stopped because the decoder ran out of positions.
public import UttrflowCore

/// Calls a recogniser, then calls it again on whatever audio the first call did not cover, until it stops hitting the cap.
public enum CappedDecodeRetry {
    /// The most retries, so a decode that cannot make progress gives up rather than spinning.
    public static let maxRetries = 10
    /// A token count past which a decode is treated as having stopped because the decoder ran out of positions, not at an end-of-text token. WhisperKit's 223-position shared decode budget leaves room for about 47 Hindi words or 200+ English ones, so this catches Hindi without firing on English.
    public static let tokenCapThreshold = 215
    /// A word longer than this is taken to be the fragment the recogniser stretched to fill the rest of the audio after the decoder stopped mid-word; the previous word's end is where the real decode stopped.
    public static let fragmentWordDuration: Duration = .milliseconds(900)
    /// The recogniser's fixed window; a segment that ends at one without inner timestamps is where a window collapsed.
    public static let windowSeconds = 30.0
    /// Silence between a collapsed segment's last word and its end past which words are taken to have been dropped.
    public static let collapsedGapSeconds = 1.0

    /// Re-decodes an empty vocabulary-biased result once without vocabulary.
    static func transcribeRecoveringEmptyPrompt(
        samples: [Float],
        sampleRate: Double = Double(AudioSamples.canonicalSampleRate),
        languageHint: LanguageCode?,
        vocabulary: [String],
        using backend: any TranscriptionBackend
    ) async throws(SpeechEngineError) -> RawTranscript {
        let biased = try await transcribe(
            samples: samples, sampleRate: sampleRate, languageHint: languageHint,
            vocabulary: vocabulary, using: backend)
        guard !vocabulary.isEmpty, biased.text.isEmpty else { return biased }

        let retried = try await transcribe(
            samples: samples, sampleRate: sampleRate, languageHint: languageHint,
            vocabulary: [], using: backend)
        return RawTranscript(
            text: retried.text,
            languageIdentifier: retried.languageIdentifier,
            languageProbability: retried.languageProbability,
            segments: retried.segments,
            effort: biased.effort.addingRetry(retried.effort),
            tokensUsed: retried.tokensUsed,
            vocabularyPrompt: retried.vocabularyPrompt)
    }

    /// Decodes `samples` with `backend`, retrying the tail when the decoder's token cap stops a decode early.
    public static func transcribe(
        samples: [Float],
        sampleRate: Double = Double(AudioSamples.canonicalSampleRate),
        languageHint: LanguageCode?,
        vocabulary: [String],
        using backend: any TranscriptionBackend
    ) async throws(SpeechEngineError) -> RawTranscript {
        var accumulatedText = ""
        var accumulatedSegments: [RawSegment] = []
        var languageIdentifier: String?
        var languageProbability: Double?
        var totalEffort = DecodeEffort.none
        var totalTokensUsed = 0
        var vocabularyPrompt: [String] = []
        var remaining = samples
        var sliceStartSeconds = 0.0
        var stillCapped = false

        for _ in 0..<maxRetries {
            guard !remaining.isEmpty else { break }
            stillCapped = false
            let result = try await backend.transcribe(
                remaining, languageHint: languageHint, biasedTowards: vocabulary)
            languageIdentifier = result.languageIdentifier ?? languageIdentifier
            languageProbability = result.languageProbability ?? languageProbability
            totalEffort = totalEffort.adding(result.effort)
            totalTokensUsed += result.tokensUsed
            vocabularyPrompt = result.vocabularyPrompt

            let sliceDuration = Duration.seconds(Double(remaining.count) / sampleRate)
            let collapse = collapsedWindow(in: result.segments, sliceSeconds: sliceDuration.inSeconds)
            // The token count is the reliable signal — a recogniser that reports it has run out of room at ~223 positions. A backend that does not report tokens falls back to the segment-end heuristic.
            let hitCap =
                result.tokensUsed > 0
                ? result.tokensUsed >= tokenCapThreshold
                : result.appearsCapped(audioDuration: sliceDuration)
            // A collapsed window is checked first; otherwise the recogniser may stretch the final fragment word to the audio end, so the last *normal* word is where it stopped.
            let cutoff: Double? =
                collapse?.lastWordEnd ?? (hitCap ? cappedCutoffSeconds(in: result.segments) : nil)
            // Only what ends by the resume point is kept, since the next slice decodes everything after it again.
            let kept: (segments: [RawSegment], changed: Bool) =
                if let collapse {
                    (Array(result.segments[...collapse.index]), true)
                } else if let cutoff {
                    segments(in: result.segments, endingBy: cutoff)
                } else {
                    (result.segments, false)
                }
            let text =
                kept.changed
                ? kept.segments.map { $0.text.trimmingCharacters(in: .whitespaces) }.joined(separator: " ")
                : result.text
            if !text.isEmpty {
                accumulatedText += (accumulatedText.isEmpty ? "" : " ") + text
            }
            let shifted = kept.segments.map { segment in
                RawSegment(
                    text: segment.text,
                    start: segment.start + sliceStartSeconds,
                    end: segment.end + sliceStartSeconds,
                    words: segment.words?.map { word in
                        RawWord(
                            text: word.text,
                            start: word.start + sliceStartSeconds,
                            end: word.end + sliceStartSeconds,
                            probability: word.probability)
                    },
                    reliability: segment.reliability)
            }
            accumulatedSegments.append(contentsOf: shifted)

            guard collapse != nil || hitCap else { break }
            guard let cutoff else {
                totalEffort = totalEffort.markingCapUnresolved()
                break
            }
            let consumedSamples = Int((cutoff * sampleRate).rounded(.down))
            guard consumedSamples > 0, consumedSamples < remaining.count else {
                totalEffort = totalEffort.markingCapUnresolved()
                break
            }
            remaining = Array(remaining[consumedSamples...])
            sliceStartSeconds += cutoff
            stillCapped = true
        }
        // Out of retries with audio still undecoded after a cap is as incomplete as a cap with no resume point.
        if stillCapped, !remaining.isEmpty {
            totalEffort = totalEffort.markingCapUnresolved()
        }

        return RawTranscript(
            text: accumulatedText.trimmingCharacters(in: .whitespacesAndNewlines),
            languageIdentifier: languageIdentifier,
            languageProbability: languageProbability,
            segments: accumulatedSegments,
            effort: totalEffort,
            tokensUsed: totalTokensUsed,
            vocabularyPrompt: vocabularyPrompt
        )
    }

    /// The first segment that ran to the end of a fixed window with its words stopping well short of it, while audio continues past. See `Docs/speech-engines.md`.
    static func collapsedWindow(
        in segments: [RawSegment], sliceSeconds: Double
    ) -> (index: Int, lastWordEnd: Double)? {
        for (index, segment) in segments.enumerated() {
            guard let lastWordEnd = segment.words?.last?.end, lastWordEnd > 0 else { continue }
            let windows = (segment.end / windowSeconds).rounded()
            let endsAtWindow = windows >= 1 && abs(segment.end - windows * windowSeconds) <= 0.1
            let spansWindow = segment.end - segment.start >= windowSeconds - 0.5
            guard endsAtWindow || spansWindow else { continue }
            guard segment.end - lastWordEnd > collapsedGapSeconds else { continue }
            guard sliceSeconds - segment.end > collapsedGapSeconds else { continue }
            return (index, lastWordEnd)
        }
        return nil
    }

    /// The segments as far as `cutoff`, a segment cut short rebuilt from the words it keeps; `changed` says whether any word went.
    static func segments(
        in segments: [RawSegment], endingBy cutoff: Double
    ) -> (segments: [RawSegment], changed: Bool) {
        var kept: [RawSegment] = []
        var changed = false
        for segment in segments {
            guard let words = segment.words, !words.isEmpty else {
                if segment.start < cutoff { kept.append(segment) } else { changed = true }
                continue
            }
            let inside = words.filter { $0.end <= cutoff }
            guard inside.count < words.count else {
                kept.append(segment)
                continue
            }
            changed = true
            guard !inside.isEmpty else { continue }
            kept.append(
                RawSegment(
                    text: inside.map { $0.text.trimmingCharacters(in: .whitespaces) }.joined(separator: " "),
                    start: segment.start, end: min(segment.end, cutoff), words: inside,
                    reliability: segment.reliability))
        }
        return (kept, changed)
    }

    /// Where in the recogniser's view the decoder actually stopped, in seconds from the start of the slice, ignoring any final fragment word it stretched past the cap.
    fileprivate static func cappedCutoffSeconds(in segments: [RawSegment]) -> Double? {
        // Walk newest-to-oldest so the first non-fragment found is the chronologically last word the recogniser finished, not the first.
        let allWords = segments.reversed().flatMap { ($0.words ?? []).reversed() }
        guard !allWords.isEmpty else {
            return segments.last?.end
        }
        let fragmentSeconds = fragmentWordDuration.inSeconds
        for word in allWords {
            let duration = word.end - word.start
            guard duration > 0, duration <= fragmentSeconds else { continue }
            return word.end
        }
        return segments.last?.end
    }
}
