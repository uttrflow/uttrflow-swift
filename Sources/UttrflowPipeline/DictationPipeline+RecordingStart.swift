// Begins one recording through ordinary or modifier capture. See `Docs/pipeline-gestures.md`.
import UttrflowCore

extension DictationPipeline {
    /// Begins listening. Does nothing if a dictation is already under way.
    public func startRecording() async {
        guard !isBusy, early.pendingCaptureElapsed == nil else { return }
        // Said rather than recorded: the words would wait behind the load, under a button saying nothing.
        guard !isLoading else { return transition(to: .failed(.stillLoading)) }
        hasTurn = true
        generation += 1
        let mine = generation
        observers.updateGeneration(mine)
        defer { hasTurn = false }
        await speech.warm()
        await startRecordingUsingOpenCapture(for: mine)
    }

    /// Opens the microphone before a modifier shortcut settles, keeping speech from key-down onward.
    public func beginModifierPress(measuring elapsed: @escaping @Sendable () -> Duration) async {
        guard early.pendingCapture == nil, !isBusy, !isLoading else { return }
        generation += 1
        let mine = generation
        observers.updateGeneration(mine)
        early.pendingCaptureElapsed = elapsed
        do {
            try await metrics.measuring(.microphoneOpen, clock: clock, generation: mine) { [capture] in
                try await capture.start()
            }
        } catch {
            early.pendingCaptureElapsed = nil
            transition(to: .failed(DictationFailure(error)))
            return
        }
        early.pendingCapture = Task {}
    }

    /// Makes a modifier press's already-open microphone the recording under way.
    @discardableResult
    public func adoptModifierPress() async -> Bool {
        guard !isBusy, !isLoading else {
            await cancelModifierPress()
            // Told as a shortcut press is told, so the press is not met with silence.
            if !isBusy { transition(to: .failed(.stillLoading)) }
            return false
        }
        hasTurn = true
        let mine = generation
        defer { hasTurn = false }
        await speech.warm()
        await startRecordingUsingOpenCapture(for: mine)
        return state.isListening
    }

    /// Cancels a modifier press that became another shortcut before it settled.
    public func cancelModifierPress() async {
        guard early.pendingCapture != nil else { return }
        early.pendingCapture = nil
        early.pendingCaptureElapsed = nil
        await capture.cancel()
    }

    /// Adopts audio already arriving as a dictation after the modifier press settles.
    private func startRecordingUsingOpenCapture(for mine: Int) async {
        screenReads = DictationScreenReads()
        if let pendingCapture = early.pendingCapture {
            await pendingCapture.value
            early.pendingCapture = nil
            let elapsed = early.pendingCaptureElapsed
            early.pendingCaptureElapsed = nil
            if let elapsed {
                await metrics.record(
                    .init(stage: .keyDownToAudio, duration: elapsed(), succeeded: true, generation: mine))
            }
        } else {
            do {
                try await metrics.measuring(.microphoneOpen, clock: clock, generation: mine) { [capture] in
                    try await capture.start()
                }
            } catch {
                guard !wasCancelled(mine) else { return }
                transition(to: .failed(DictationFailure(error)))
                return
            }
        }
        guard !wasCancelled(mine) else {
            await capture.cancel()
            return
        }
        recordingRoute = nextRoute
        nextRoute = .dictation
        stopwatch = UttrflowCore.stopwatch(from: clock)
        takeSettings()
        spokenFor = nil
        insertedInto = nil
        insertedIntoIdentifier = nil
        destinationIsSecure = false
        cleaningRecords = []
        droppedSpans = []
        transition(to: .recording)
        beginWorkingAhead(mine)
    }
}
