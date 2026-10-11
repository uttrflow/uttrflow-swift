// Joins the early work to the released recording. See `Docs/pipeline.md`.
import UttrflowCore

extension DictationPipeline {
    func process(_ audio: AudioSamples, _ mine: Int, delivery: Delivery) async {
        // Checked before the state moves, so an abandoned run never overwrites the rest a cancel sets.
        guard !wasCancelled(mine) else { return }
        if state != .transcribing { transition(to: .transcribing) }
        if let quality = CaptureQuality.measure(
            samples: audio.samples, sampleRate: audio.sampleRate, gaps: audio.gaps,
            chosenInputMissing: audio.chosenInputMissing)
        {
            inputTooLoud = InputTooLoud.isTooLoud(clippedFraction: quality.clippedFraction)
            await metrics.recordCaptureQuality(quality)
        }
        show(heard: nil)

        let handed = await takeOver(for: audio, delivery: delivery, generation: mine)
        let tally = StageTally()
        var appContext = handed.context
        if let backlog = handed.backlog { await metrics.recordBacklog(backlog) }

        if dictationContext == nil {
            let seeing: AppContext
            if let appContext {
                seeing = appContext
            } else {
                seeing = await contextFor(delivery)
            }
            appContext = seeing
            await resolveDictationContext(
                seeing, cleaner: runningCleaner, overrides: runningOverrides)
        }
        let message: RunningMessage
        switch await recognise(
            audio, handed.spans + handed.remainder.map(Span.pending), early: handed.context,
            seeing: appContext, delivery: delivery, recording: tally, for: mine)
        {
        case .failed(let failure):
            await tally.report(to: metrics)
            guard !wasCancelled(mine) else { return }
            await fail(failure)
            return
        case .abandoned:
            return
        case .heard(let heard, let seen):
            appContext = seen
            var running = handed.running
            let situation =
                dictationContext?.situation
                ?? SituationResolver.resolve(from: seen ?? AppContext(), overrides: runningOverrides)
            for piece in heard.dropFirst(running.pieces.count) {
                running.fold(piece, going: situation)
            }
            message = RunningMessage(heard, keeping: running)
        }
        guard !wasCancelled(mine) else { return }
        await tally.report(to: metrics)
        await deliver(message, from: audio, read: appContext, recording: tally, delivery: delivery, for: mine)
    }

    /// How recognising the rest of a dictation ended; an exit that is not one of these does not compile.
    enum Recognition {
        case heard([Piece], seeing: AppContext?)
        case failed(DictationFailure)
        case abandoned
    }

    /// Finishes the early loop's work and takes it over, dropping pieces cut from other audio than this.
    private func takeOver(
        for audio: AudioSamples, delivery: Delivery, generation mine: Int
    ) async -> Takeover {
        // Read before the drain: a piece under way has not moved the cut yet and is part of the backlog.
        let cutAtKeyUp = early.cut
        // A piece under way is finished, not thrown away; the loop then ends itself, as the state has left `.recording`.
        if !early.recognising { early.task?.cancel() }
        if let earlyWork = early.task {
            // Measured only where a piece really is in flight, so working ahead of nothing gains no row.
            if early.pieceInFlight {
                await metrics.measuring(.drain, clock: clock, generation: mine) { await earlyWork.value }
            } else {
                await earlyWork.value
            }
        }
        let handed = early.handOff()
        var spans = handed.spans
        var cut = handed.cut
        let previousWindowStart = handed.lastWindowStart
        // Pieces cut from other audio than this cannot be joined to it.
        let otherAudio = delivery == .copy || cut > audio.samples.count
        if otherAudio {
            for span in spans { await withdraw(span) }
            spans = []
            cut = 0
            cleaningRecords = []
        }

        let backlog =
            otherAudio
            ? nil
            : WorkAheadBacklog(
                seconds: Double(max(0, audio.samples.count - cutAtKeyUp)) / Double(audio.sampleRate),
                pieces: runningWindowing.windows(
                    in: audio.samples, sampleRate: audio.sampleRate, from: cutAtKeyUp,
                    joiningPreviousWindowFrom: nil, boundaries: audio.discontinuities
                ).count)
        var remainder = runningWindowing.windows(
            in: audio.samples, sampleRate: audio.sampleRate, from: cut,
            joiningPreviousWindowFrom: delivery != .copy ? previousWindowStart : nil,
            boundaries: audio.discontinuities)
        if let first = remainder.first, first.lowerBound < cut, let dropped = spans.popLast() {
            await withdraw(dropped)
        }
        // Nothing at all still goes to the recogniser, whose refusal names the reason.
        if spans.isEmpty, remainder.isEmpty { remainder = [cut..<audio.samples.count] }
        return Takeover(
            spans: spans, running: handed.running, remainder: remainder, context: handed.context,
            backlog: backlog)
    }
}
