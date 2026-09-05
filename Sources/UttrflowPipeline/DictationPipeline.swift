public import UttrflowCore
public import struct Foundation.UUID

/// Speak, and the words appear where you were typing. See `Docs/pipeline.md`.
public actor DictationPipeline {
    private let capture: any AudioCaptureEngine
    private let speech: any SpeechEngine
    private let cleaner: any TranscriptCleaning
    private let context: any ContextEngine
    private let inserter: any TextInserting
    private let corrector: any WordCorrecting
    private let snippets: any SnippetExpanding
    private let learner: any DictationLearning
    private let vocabulary: any VocabularyLearning
    private let metrics: any MetricsRecording
    private let recordings: any RecordingKeeper
    /// Where a retried dictation's words go, since the field they were meant for is gone.
    private let clipboard: any TextInserting
    private let clock: any Clock<Duration>
    private let profile: UserProfile

    private var state: DictationState = .idle
    private let observers = StateObservers()

    /// Counts dictations, so a cancel can name the one it abandoned.
    private var generation = 0
    private var cancelledGeneration: Int?

    /// Claims the turn before the microphone opens, so two presses cannot both pass the guard.
    private var isStarting = false

    /// Reads how long the microphone has been open, closing over the injected clock.
    private var stopwatch: (() -> Duration)?
    private var spokenFor: Duration?

    /// The application named by the context read during tidying, before the user moved on.
    private var insertedInto: String?
    private var insertedIntoIdentifier: String?

    /// The kept audio of the dictation under way, deleted or left for a retry as it ends.
    private var openRecording: UUID?

    public init(
        capture: any AudioCaptureEngine,
        speech: any SpeechEngine,
        cleaner: any TranscriptCleaning,
        context: any ContextEngine,
        inserter: any TextInserting,
        corrector: any WordCorrecting = NoTextChanges(),
        snippets: any SnippetExpanding = NoTextChanges(),
        learner: any DictationLearning = NoTextChanges(),
        vocabulary: any VocabularyLearning = NoTextChanges(),
        metrics: any MetricsRecording = NoOpMetricsRecorder(),
        recordings: any RecordingKeeper = RecordingsNotKept(),
        clipboard: (any TextInserting)? = nil,
        clock: any Clock<Duration> = ContinuousClock(),
        profile: UserProfile = .default
    ) {
        self.capture = capture
        self.speech = speech
        self.cleaner = cleaner
        self.context = context
        self.inserter = inserter
        self.corrector = corrector
        self.snippets = snippets
        self.learner = learner
        self.vocabulary = vocabulary
        self.metrics = metrics
        self.recordings = recordings
        self.clipboard = clipboard ?? inserter
        self.clock = clock
        self.profile = profile
    }

    public var currentState: DictationState { state }

    /// Whether the recogniser has loaded and the next dictation will not wait for it.
    public private(set) var isReady = false

    /// Every state the pipeline passes through, from now on.
    public func states() -> AsyncStream<DictationState> {
        observers.makeStream(startingWith: state)
    }

    /// Loads the speech model so the first dictation is not the slow one. See `Docs/startup.md`.
    public func prepare() async {
        do {
            try await speech.prepare()
            isReady = true
            // A retry that works clears the notice the failed attempt left behind.
            if case .failed = state, !isBusy { transition(to: .idle) }
        } catch {
            isReady = false
            // Never over a dictation in progress: loading can run while the user speaks.
            if !isBusy { transition(to: .failed(DictationFailure(error))) }
        }
    }

    /// Opens the existential clock, which is what lets an instant be held on to.
    private static func stopwatch(from clock: some Clock<Duration>) -> () -> Duration {
        let start = clock.now
        return { start.duration(to: clock.now) }
    }

    // MARK: The sequence

    /// Whether a new dictation can begin, counting a start that has not opened the microphone yet.
    private var isBusy: Bool { isStarting || state.isBusy }

    /// Begins listening. Does nothing if a dictation is already under way.
    public func startRecording() async {
        guard !isBusy else { return }
        isStarting = true
        defer { isStarting = false }

        generation += 1
        let mine = generation
        do {
            try await capture.start()
            guard !wasCancelled(mine) else {
                // Cancelled while the microphone was opening: close it rather than listen on.
                await capture.cancel()
                return
            }
            stopwatch = Self.stopwatch(from: clock)
            spokenFor = nil
            insertedInto = nil
            insertedIntoIdentifier = nil
            transition(to: .recording)
        } catch {
            transition(to: .failed(DictationFailure(error)))
        }
    }

    /// Stops listening and runs the rest: transcribe, tidy, insert.
    public func finishRecording() async {
        guard state == .recording else { return }

        // Carried through every stage below, so a later dictation cannot revive this one.
        let mine = generation

        let audio: AudioSamples
        do {
            // Draining and converting the buffer, which is the part Uttrflow costs the user.
            let captured = try await metrics.measuring(.capture, clock: clock) {
                try await withStageTimeout(StageTimeout.quick, clock: clock) { [capture] in
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
            transition(to: .failed(DictationFailure(error)))
            return
        }

        // Written beside the buffer while the key was held, so it exists before anything can fail.
        openRecording = await recordings.current()?.id
        await process(audio, mine, delivery: .insert)
    }

    /// Runs a kept recording through the same stages, delivering the words to the clipboard.
    public func retry(_ recording: UUID) async {
        guard !isBusy else { return }
        generation += 1
        let mine = generation

        let audio: AudioSamples
        do {
            audio = try await recordings.audio(of: recording)
        } catch {
            // A file that cannot be read cannot be retried, so it is not offered again.
            await recordings.discard(recording)
            transition(to: .failed(DictationFailure(error)))
            return
        }
        stopwatch = nil
        spokenFor = audio.duration
        insertedInto = nil
        insertedIntoIdentifier = nil
        openRecording = recording
        await process(audio, mine, delivery: .copy)
    }

    /// Abandons the dictation at any stage: nothing is transcribed and nothing is inserted.
    public func cancel() async {
        cancelledGeneration = generation
        await capture.cancel()
        await discardOpenRecording()
        transition(to: .idle)
    }

    /// Whether the dictation that started at `mine` has since been abandoned, by it or by a later cancel.
    private func wasCancelled(_ mine: Int) -> Bool {
        guard let cancelledGeneration else { return false }
        return mine <= cancelledGeneration
    }

    /// Returns to rest after the interface has shown the result.
    public func acknowledge() {
        guard !isBusy else { return }
        transition(to: .idle)
    }

    // MARK: Stages

    /// Where the finished words go.
    private enum Delivery {
        case insert
        case copy
    }

    private func process(_ audio: AudioSamples, _ mine: Int, delivery: Delivery) async {
        transition(to: .transcribing)
        let transcription: Transcription
        do {
            let recognised = try await metrics.measuring(.transcription, clock: clock) {
                try await withStageTimeout(StageTimeout.transcription, clock: clock) { [speech] in
                    try await speech.transcribe(audio, options: .automatic)
                }
            }
            // Busy for ever is what refuses every later dictation. See `Docs/stuck-recording.md`.
            guard let recognised else {
                await fail(
                    DictationFailure(
                        SpeechEngineError.transcriptionFailed(
                            description: "the recogniser did not answer")))
                return
            }
            transcription = recognised
        } catch {
            await fail(DictationFailure(error))
            return
        }

        guard !wasCancelled(mine) else { return }

        // Silence is not a fault, but returning quietly to idle would look like a broken app.
        guard !transcription.isBlank else {
            await fail(DictationFailure(SpeechEngineError.nothingHeard))
            return
        }

        transition(to: .tidying)

        // Read once and handed to everything that needs it, so two stages see one screen.
        let appContext: AppContext
        switch delivery {
        case .insert:
            appContext =
                ((try? await withStageTimeout(StageTimeout.quick, clock: clock) { [context] in
                    await context.currentContext()
                }) ?? nil) ?? AppContext()
            // Kept from this read: by insertion time the user has often switched away.
            insertedInto = appContext.applicationName
            insertedIntoIdentifier = appContext.bundleIdentifier
        case .copy:
            // The screen now is Uttrflow's own window, which says nothing about what was said.
            appContext = AppContext()
        }

        // The dictionary before the tidier: a correction is argued from the sentence as heard.
        let corrected = await correct(transcription, seeing: appContext)
        guard !wasCancelled(mine) else { return }

        let cleaned = await tidy(transcription, saying: corrected.text, seeing: appContext)
        guard !wasCancelled(mine) else { return }

        // Inserting a blank would delete the user's selection, so it is refused like silence.
        guard !cleaned.text.isBlank else {
            await fail(DictationFailure(SpeechEngineError.nothingHeard))
            return
        }

        // Snippets after the tidier, whose punctuation is what stops a trigger crossing a sentence.
        let expanded = await expand(cleaned.text)
        guard !wasCancelled(mine) else { return }

        let changes = AppliedChanges(
            corrections: corrected.corrections, snippets: expanded.snippets,
            // The unrewritten sentence, which is the space the corrections' word ranges index.
            spokenWords: transcription.text.spokenWords.count)
        guard
            await insert(
                expanded.text, cleanedBy: cleaned.producedBy, changes: changes, delivery: delivery)
        else { return }

        // Both run after the words are on screen, and neither can fail the dictation. §19.
        await count(changes)
        await learnWords(heard: transcription.text, wrote: expanded.text, seeing: appContext)
    }

    /// Puts the user's own spellings in, leaving the transcript alone if it cannot. §19.
    private func correct(
        _ transcription: Transcription, seeing appContext: AppContext
    ) async -> CorrectedTranscript {
        do {
            return try await metrics.measuring(.correction, clock: clock) {
                let proposed =
                    try await withStageTimeout(StageTimeout.quick, clock: clock) { [corrector] in
                        try await corrector.corrections(for: transcription, seeing: appContext)
                    } ?? []
                // The commonest answer, and not worth rebuilding a string to arrive at itself.
                guard !proposed.isEmpty else {
                    return CorrectedTranscript.unchanged(transcription.text)
                }
                return DictationCorrection.applying(proposed, to: transcription.text)
            }
        } catch {
            return .unchanged(transcription.text)
        }
    }

    /// Tidies the transcript, falling back to exactly what was said. The only optional stage.
    private func tidy(
        _ transcription: Transcription, saying text: String, seeing appContext: AppContext
    ) async -> TransformationResult {
        let request = TransformationRequest(
            transcription: transcription.saying(text), context: appContext, profile: profile)
        let untidied = TransformationResult(text: text, producedBy: .rules)

        do {
            let tidied = try await metrics.measuring(.transformation, clock: clock) {
                try await withStageTimeout(StageTimeout.transformation, clock: clock) { [cleaner] in
                    try await cleaner.clean(request)
                }
            }
            // A language model that never answers costs the tidying, never the words.
            return tidied ?? untidied
        } catch {
            return untidied
        }
    }

    /// Expands the user's snippets, treating a blank expansion as nothing to do.
    private func expand(_ text: String) async -> ExpandedTranscript {
        do {
            return try await metrics.measuring(.expansion, clock: clock) {
                let expanded =
                    try await withStageTimeout(StageTimeout.quick, clock: clock) { [snippets] in
                        try await snippets.expand(text)
                    }
                guard let expanded, !expanded.text.isBlank else {
                    return ExpandedTranscript.unchanged(text)
                }
                return expanded
            }
        } catch {
            return .unchanged(text)
        }
    }

    /// Puts the finished text where the user was typing, answering whether it reached the screen.
    private func insert(
        _ text: String, cleanedBy: TransformerKind, changes: AppliedChanges, delivery: Delivery
    ) async -> Bool {
        let inserter = delivery == .copy ? clipboard : self.inserter
        do {
            let inserted = try await metrics.measuring(.insertion, clock: clock) {
                try await withStageTimeout(StageTimeout.quick, clock: clock) {
                    try await inserter.insert(text)
                }
            }
            // Either way the dictation has to end, so the next one can begin.
            guard let method = inserted else {
                throw TextInsertionError.insertionRejected(
                    description: "the application did not respond")
            }
            // The words landed, so the audio has done its job.
            await discardOpenRecording()
            transition(
                to: .inserted(
                    DictationOutcome(
                        text: text, method: method, cleanedBy: cleanedBy,
                        insertedInto: insertedInto,
                        insertedIntoIdentifier: insertedIntoIdentifier,
                        spokenFor: spokenFor, changes: changes,
                        fromRecording: delivery == .copy)))
            return true
        } catch {
            // The words survive the failure: the interface can still offer them.
            await fail(DictationFailure(error, transcript: text))
            return false
        }
    }

    /// Ends the dictation in failure, keeping the audio exactly when the words were lost. See `Docs/recordings.md`.
    private func fail(_ failure: DictationFailure) async {
        var failure = failure
        if let openRecording {
            self.openRecording = nil
            let wordsLost = failure.transcript == nil && failure.severity != .informational
            if !wordsLost {
                await recordings.discard(openRecording)
            } else if failure.recovery == nil || failure.recovery == .retry {
                failure = failure.offering(.retryFromRecording)
            }
        }
        transition(to: .failed(failure))
    }

    /// Deletes the kept audio of the dictation under way, if there is one.
    private func discardOpenRecording() async {
        guard let openRecording else { return }
        self.openRecording = nil
        await recordings.discard(openRecording)
    }

    /// Tells the stores what this dictation used, once the words are safely on screen.
    private func count(_ changes: AppliedChanges) async {
        guard !changes.isEmpty else { return }

        // Once per entry: the store counts dictations an entry was applied to, not words.
        var counted: Set<UUID> = []
        for correction in changes.corrections where counted.insert(correction.entryID).inserted {
            // Each on its own, so a store that refuses the first still counts the second.
            try? await learner.recordUse(ofEntry: correction.entryID)
        }

        guard !changes.snippets.isEmpty else { return }
        // One batch, duplicates left in, because the store counts firings not dictations.
        try? await learner.recordUse(ofSnippets: changes.snippets.map(\.snippetID))
    }

    /// Offers the dictionary what this dictation showed, once its words have landed.
    private func learnWords(heard: String, wrote: String, seeing context: AppContext) async {
        guard !context.isEmpty else { return }
        try? await vocabulary.learn(heard: heard, wrote: wrote, seeing: context)
    }

    private func transition(to next: DictationState) {
        state = next
        observers.send(next)
    }
}

extension String {
    /// Nothing but whitespace, the emptiness ``Transcription/isBlank`` means.
    fileprivate var isBlank: Bool { allSatisfy(\.isWhitespace) }
}

extension Transcription {
    /// The same recognised speech, with different words in it and the same timings.
    fileprivate func saying(_ text: String) -> Transcription {
        guard text != self.text else { return self }
        return Transcription(
            text: text, detectedLanguage: detectedLanguage, segments: segments,
            audioDuration: audioDuration)
    }
}
