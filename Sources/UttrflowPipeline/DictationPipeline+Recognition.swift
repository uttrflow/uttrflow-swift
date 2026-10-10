// Recognition: turning a recording's audio into words, and naming why when it cannot.
import UttrflowAI
import UttrflowCore

extension DictationPipeline {
    /// Recognises every pending span in order, with one tidy running beside the next recognition.
    func recognise(
        _ audio: AudioSamples, _ work: [Span], early earlyContext: AppContext?, seeing read: AppContext?,
        delivery: Delivery, recording tally: StageTally, for mine: Int
    ) async -> Recognition {
        var appContext = read
        var pieces: [Piece] = []
        let vocabularyContext = earlyContext ?? AppContext()
        // One tidy runs beside the next recognition, which the two stages allow. See `Docs/early-transcription.md`.
        let ending: Recognition? = await withTaskGroup(of: Piece.self) { tidying in
            // A span the early loop left unfinished is done here, in its place, so the words stay in order.
            let finalPending = work.indices.last(where: {
                if case .pending = work[$0] { return true }
                return false
            })
            // The previous span's words as heard, the one context every path has. See `Docs/early-transcription.md`.
            var precedingHeard: Transcription?
            for (spanIndex, span) in work.enumerated() {
                let window: Range<Int>
                if let heard = span.heard { precedingHeard = heard }
                switch span {
                case .done(let piece, _):
                    if let earlier = await tidying.next() { pieces.append(earlier) }
                    pieces.append(piece)
                    continue
                case .tidying(let running):
                    let task = running.task
                    // The recognition after it can start before this tidy is done; the group still drains it first.
                    if let earlier = await tidying.next() { pieces.append(earlier) }
                    if spanIndex == work.indices.last {
                        await runningCleaner.reserveFinalPiece(dictationContext?.situation)
                    }
                    tidying.addTask { await task.value }
                    continue
                case .pending(let range):
                    window = range
                }
                let heard: Transcription?
                do {
                    heard = try await transcribe(
                        audio, window,
                        biasedTowards: await vocabulary(mine, seeing: vocabularyContext),
                        recording: tally, skippingAMiss: true, for: mine)
                } catch {
                    tidying.cancelAll()
                    return .failed(
                        Self.failure(error, in: audio, speechEngineKind: (retrySpeech ?? speech).kind))
                }
                // The tidy that ran beside this recognition is taken before the next one starts, so one is ever in flight.
                if let earlier = await tidying.next() { pieces.append(earlier) }
                guard !wasCancelled(mine) else {
                    tidying.cancelAll()
                    return .abandoned
                }
                guard let heard else { continue }

                // The first piece ends transcribing, whether or not the screen was read while recording.
                if state == .transcribing { transition(to: .tidying) }
                if appContext == nil { appContext = await contextFor(delivery) }
                let seeing = appContext ?? AppContext()
                let finalPiece = spanIndex == finalPending
                let preceding = precedingHeard
                precedingHeard = heard
                tidying.addTask {
                    await self.finish(
                        heard, seeing: seeing, correctionSeeing: seeing,
                        finalPiece: finalPiece, after: preceding, recording: tally, for: mine)
                }
            }
            while let last = await tidying.next() { pieces.append(last) }
            return nil
        }
        return ending ?? .heard(pieces, seeing: appContext)
    }

    /// Recognises one window of the audio, answering `nil` when nothing was said in it; speech with no words is decoded twice.
    func transcribe(
        _ audio: AudioSamples, _ window: Range<Int>, biasedTowards words: [String],
        recording metrics: any MetricsRecording, skippingAMiss skips: Bool, for mine: Int
    ) async throws -> Transcription? {
        let whole = window == audio.samples.indices
        // Reuse the full recording when this window already covers it.
        let slice =
            whole
            ? audio
            : AudioSamples(samples: Array(audio.samples[window]), sampleRate: audio.sampleRate) ?? .empty
        // The dictation's one read, so every piece is conditioned on the same caret. See `Docs/context-budget.md`.
        let preceding = dictationContext?.app.recognitionContext
        var heard = try await decode(
            slice, whole: whole, biasedTowards: words, after: preceding, recording: metrics, generation: mine)
        // The second decode goes without the prompt, which is the one input a retry can change.
        if case .missed = heard {
            let retrying = UttrflowCore.stopwatch(from: clock)
            heard = try await decode(
                slice, whole: whole, biasedTowards: [], after: nil, recording: metrics, generation: mine)
            // The second decode is this piece's retry; what it already names, such as fallbacks, is left out.
            if case .words(let transcription) = heard {
                let spent = retrying().inSeconds - transcription.effort.namedSeconds
                heard = .words(transcription.spending(DecodeEffort(retrySeconds: max(0, spent))))
            }
        }
        switch heard {
        case .words(let transcription):
            // Kept beside the timing, since a re-decode is most of what a long transcription time is.
            await metrics.recordDecoding(transcription.effort)
            await metrics.recordReliability(transcription.segments.compactMap(\.reliability))
            return transcription
        case .nothing:
            return nil
        case .missed:
            // Alone, or while recording where the end decodes it again, a miss fails; otherwise the rest still go in.
            guard skips, !whole else { throw SpeechEngineError.speechWithoutWords }
            missedPieces += 1
            return nil
        }
    }

    /// One decode of a slice, telling words, silence and speech that produced no words apart.
    private func decode(
        _ slice: AudioSamples, whole: Bool, biasedTowards words: [String], after preceding: String?,
        recording metrics: any MetricsRecording, generation mine: Int
    ) async throws -> Heard {
        // The default profile detects each piece; a Hindi-only profile pins each piece to Hindi. See `Docs/speech-engines.md`.
        let policy = dictationContext?.listening ?? ListeningLanguages(profile: runningProfile)
        let language = policy.hint(afterFirstPiece: nil)
        // The dictation's one read, so every piece is conditioned on the same caret. See `Docs/context-budget.md`.
        let preceding = dictationContext?.app.recognitionContext
        let speaks = VoiceActivity.speechRange(in: slice.samples, sampleRate: slice.sampleRate) != nil
        let speech = retrySpeech ?? speech
        let heard = try await metrics.measuringInTime(
            .transcription, clock: clock, generation: mine
        ) {
            try await withStageTimeout(StageTimeout.transcription, clock: clock) {
                [speech] () async throws -> Heard in
                do {
                    let transcription = try await speech.transcribe(
                        slice,
                        options: TranscriptionOptions(
                            languageHint: language, vocabulary: words,
                            precedingText: preceding))
                    await metrics.recordVocabularyPrompt(transcription.vocabularyPrompt)
                    await metrics.recordConditioning(transcription.conditioning)
                    // A piece mostly in a script neither language is written in is a recognition failure, not words.
                    if transcription.isBlank || LatinScript.isMostlyUntranscribedScript(transcription.text) {
                        return speaks ? Heard.missed : Heard.nothing
                    }
                    return Heard.words(transcription)
                } catch SpeechEngineError.audioTooShort {
                    // Alone, a hold too brief to transcribe says so, since the fix is to hold longer.
                    guard !whole else { throw SpeechEngineError.audioTooShort }
                    return speaks ? Heard.missed : Heard.nothing
                } catch SpeechEngineError.nothingHeard {
                    if speaks { return Heard.missed }
                    // Only when there is nothing else: alone, silence is refused below.
                    guard !whole else { throw SpeechEngineError.nothingHeard }
                    return Heard.nothing
                }
            }
        }
        // Busy for ever is what refuses every later dictation. See `Docs/stuck-recording.md`.
        guard let heard else {
            throw SpeechEngineError.recogniserTimedOut
        }
        isReady = true
        return heard
    }

    /// A recognition failure, where silence a refusal names reads the same as silence found in blank windows.
    private static func failure(
        _ error: any Error, in audio: AudioSamples, speechEngineKind kind: SpeechEngineKind
    ) -> DictationFailure {
        switch error as? SpeechEngineError {
        case .nothingHeard?: silence(.nothingHeard, in: audio)
        case .speechWithoutWords?: silence(.speechWithoutWords, in: audio)
        default: DictationFailure(error, speechEngineKind: kind)
        }
    }

    /// Silence is not a recogniser fault, so it names no engine; a recording of digital zeros is a muted input.
    static func silence(_ heard: SpeechEngineError, in audio: AudioSamples) -> DictationFailure {
        DictationFailure(heard == .nothingHeard && audio.carriesNoSignal ? SpeechEngineError.noSignal : heard)
    }

    /// Times the wait since key-up, names its cause against the last dictations, and records both.
    func timeWait(recorded tally: StageTally) async -> SlowDictationCause? {
        guard let waited = sinceRelease?() else { return nil }
        sinceRelease = nil
        let screenReads = max(.zero, self.screenReads.cost.duration - readsBeforeRelease)
        let wait = DictationWait(
            wait: waited, stages: await tally.measurements, decoding: await tally.efforts,
            screenReads: screenReads)
        let timed = waits.classify(wait)
        await metrics.recordWait(timed)
        return timed.cause
    }
}
