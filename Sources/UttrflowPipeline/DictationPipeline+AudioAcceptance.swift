// Accepts the captured or kept recording for processing. See `Docs/recordings.md`.
public import UttrflowCore
public import struct Foundation.Date
public import struct Foundation.UUID

extension DictationPipeline {
    /// Stops listening and runs the rest: transcribe, tidy, insert.
    public func finishRecording() async {
        await stopListening()?.value
    }

    /// Closes the microphone and returns, leaving the rest to the task it hands back. See Docs/pipeline-gestures.md.
    @discardableResult
    public func stopListening() async -> Task<Void, Never>? {
        // A second stop while the microphone drains is refused here, not sent to a microphone already closed.
        guard state == .recording, !hasTurn else { return nil }
        hasTurn = true
        sinceRelease = UttrflowCore.stopwatch(from: clock)
        readsBeforeRelease = screenReads.cost.duration

        // Carried through every stage below, so a later dictation cannot revive this one.
        let mine = generation

        let audio: AudioSamples
        do {
            // Draining and converting the buffer, which is the part Uttrflow costs the user.
            let captured = try await metrics.measuringInTime(.capture, clock: clock, generation: mine) {
                try await withStageTimeout(StageTimeout.captureStop, clock: clock) { [capture] in
                    try await capture.stop()
                }
            }
            guard let captured else {
                throw AudioCaptureError.engineFailed(
                    description: "the microphone did not stop")
            }
            audio = captured
            spokenFor = stopwatch?()
            stopwatch = nil
        } catch {
            hasTurn = false
            // The capture writes the recording before it refuses it, so the audio is claimed here too (#604).
            await claimRecording(mine)
            // A cancel during the drain leaves the pipeline at rest, so no failure is published over it.
            guard !wasCancelled(mine) else { return nil }
            // Through `fail`, so a refused capture reaches the same rule as every other lost dictation.
            await fail(DictationFailure(error))
            return nil
        }

        await claimRecording(mine)
        hasTurn = false
        guard !wasCancelled(mine) else { return nil }
        // Moved on before returning, so a gesture handled next sees the microphone closed and the pipeline busy.
        transition(to: .transcribing)
        let delivery: Delivery = recordingRoute == .command ? .command : .insert
        return Task { await process(audio, mine, delivery: delivery) }
    }

    /// Runs a kept recording to the clipboard, heard by `engine` if given; false when it never ran or was abandoned.
    @discardableResult
    public func retry(_ recording: UUID, hearingWith engine: (any SpeechEngine)? = nil) async -> Bool {
        guard !isBusy, early.pendingCaptureElapsed == nil else { return false }
        // A restore inside the window keeps the file from the deletion the window would bring.
        if restorable?.id == recording {
            restorable?.expiry.cancel()
            restorable = nil
        }
        // Held while the file is read, so a dictation cannot open the microphone underneath the retry.
        hasTurn = true
        generation += 1
        let mine = generation
        observers.updateGeneration(mine)

        let audio: AudioSamples
        do {
            audio = try await recordings.audio(of: recording)
        } catch {
            // A file that cannot be read cannot be retried, so it is not offered again.
            await recordings.discard(recording)
            hasTurn = false
            // A cancel during the read leaves the pipeline at rest, so no failure is published over it.
            guard !wasCancelled(mine) else { return false }
            transition(
                to: .failed(
                    DictationFailure(
                        message: "That recording couldn't be read, so it can't be retried.",
                        recovery: nil, severity: .recoverable)))
            return true
        }
        hasTurn = false
        // A cancel during the read abandons the retry before it claims the recording as its own.
        guard !wasCancelled(mine) else { return false }
        stopwatch = nil
        takeSettings(spendingFormat: false)
        spokenFor = audio.duration
        let kept = (await recordings.waiting(now: Date())).first(where: { $0.id == recording })
        recordingDestination = kept?.destination.map(AppContext.init(identity:))
        recordingFieldKind = kept?.fieldKind
        insertedInto = recordingDestination?.applicationName
        insertedIntoIdentifier = recordingDestination?.bundleIdentifier
        destinationIsSecure = false
        cleaningRecords = []
        droppedSpans = []
        openRecording = recording
        forgetTheLastAttempt()
        retrySpeech = engine
        defer { retrySpeech = nil }
        await process(audio, mine, delivery: .copy)
        return true
    }

    /// Takes the recording written while the key was held as this dictation's, or deletes a cancelled one.
    private func claimRecording(_ mine: Int) async {
        // Written beside the buffer while the key was held, so it exists before anything can fail.
        let kept = await recordings.current()
        // Asked after the lookup, since a cancel can arrive while it is suspended as well as before it.
        guard !wasCancelled(mine) else {
            // A cancel cannot see a recording not yet looked up, so it is deleted here instead.
            if let kept { await recordings.discard(kept.id) }
            return
        }
        openRecording = kept?.id
        if let destination = early.context ?? dictationContext?.app, let id = kept?.id {
            let fieldKind =
                dictationContext?.situation.destination
                ?? SituationResolver.resolve(from: destination, overrides: runningOverrides).destination
            await recordings.setDestination(destination, fieldKind: fieldKind, for: id)
        }
    }
}
