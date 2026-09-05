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
    /// How a recording is cut into pieces the recogniser and tidier take one at a time.
    private let windowing: SpeechWindowing
    /// How often the recording is looked at for a piece to work on while the key is held.
    private let earlyPoll: Duration
    /// Paces that look on its own clock, so a test driving the stage clock wakes only stages.
    private let pollClock: any Clock<Duration>

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

    /// Pieces finished while the key was still held, and where the audio they cover ends. See `Docs/early-transcription.md`.
    private var earlyPieces: [Piece] = []
    private var earlyCut = 0
    private var earlyWork: Task<Void, Never>?
    private var earlyContext: AppContext?

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
        profile: UserProfile = .default,
        windowing: SpeechWindowing = .standard,
        earlyPoll: Duration = .seconds(1),
        pollClock: any Clock<Duration> = ContinuousClock()
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
        self.windowing = windowing
        self.earlyPoll = earlyPoll
        self.pollClock = pollClock
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
            beginWorkingAhead(mine)
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
        earlyWork?.cancel()
        earlyPieces = []
        earlyCut = 0
        await capture.cancel()
        if let openRecording {
            self.openRecording = nil
            await recordings.discard(openRecording)
        }
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

    // MARK: Working ahead

    /// One piece of the recording, through every stage that runs before the words are joined.
    fileprivate struct Piece: Sendable {
        let heard: Transcription
        let corrected: CorrectedTranscript
        let cleaned: TransformationResult
    }

    /// Starts the tidier warming and the recogniser working on the recording as it grows.
    private func beginWorkingAhead(_ mine: Int) {
        earlyPieces = []
        earlyCut = 0
        earlyContext = nil
        earlyWork = Task { [cleaner] in
            await cleaner.warm()
            await self.workAhead(mine)
        }
    }

    /// Transcribes and tidies each piece the moment a pause ends it, until the key is released.
    private func workAhead(_ mine: Int) async {
        while state == .recording, generation == mine, !wasCancelled(mine), !Task.isCancelled {
            try? await pollClock.sleep(for: earlyPoll)
            guard state == .recording, generation == mine, !wasCancelled(mine), !Task.isCancelled
            else { return }

            let audio = await capture.capturedSoFar()
            guard
                let end = windowing.nextCut(
                    in: audio.samples, sampleRate: audio.sampleRate, from: earlyCut)
            else { continue }

            // A piece that fails is left for the end, where its failure can be reported.
            let heard: Transcription?
            do {
                heard = try await transcribe(audio, earlyCut..<end, recording: NoOpMetricsRecorder())
            } catch {
                return
            }
            guard generation == mine, !wasCancelled(mine) else { return }
            if let heard {
                let seeing = await earlyContextRead()
                let piece = await finish(heard, seeing: seeing, recording: NoOpMetricsRecorder())
                guard generation == mine, !wasCancelled(mine) else { return }
                earlyPieces.append(piece)
            }
            earlyCut = end
        }
    }

    /// The screen as it was while the key was held, read once for every early piece.
    private func earlyContextRead() async -> AppContext {
        if let earlyContext { return earlyContext }
        let read = await readContext()
        earlyContext = read
        insertedInto = read.applicationName
        insertedIntoIdentifier = read.bundleIdentifier
        return read
    }

    /// Asks what is on screen, within a budget, answering nothing rather than waiting.
    private func readContext() async -> AppContext {
        ((try? await withStageTimeout(StageTimeout.quick, clock: clock) { [context] in
            await context.currentContext()
        }) ?? nil) ?? AppContext()
    }

    // MARK: Stages

    /// Where the finished words go.
    private enum Delivery {
        case insert
        case copy
    }

    private func process(_ audio: AudioSamples, _ mine: Int, delivery: Delivery) async {
        transition(to: .transcribing)

        // A piece under way is finished, not thrown away: its words are needed either way.
        earlyWork?.cancel()
        await earlyWork?.value
        earlyWork = nil
        var pieces = earlyPieces
        var cut = earlyCut
        let earlyContext = self.earlyContext
        earlyPieces = []
        earlyCut = 0
        self.earlyContext = nil
        // Pieces cut from other audio than this cannot be joined to it.
        if delivery == .copy || cut > audio.samples.count {
            pieces = []
            cut = 0
        }

        var remainder = windowing.windows(in: audio.samples, sampleRate: audio.sampleRate, from: cut)
        // Nothing at all still goes to the recogniser, whose refusal names the reason.
        if pieces.isEmpty, remainder.isEmpty { remainder = [cut..<audio.samples.count] }

        let tally = StageTally()
        var appContext = earlyContext
        for window in remainder {
            let heard: Transcription?
            do {
                heard = try await transcribe(audio, window, recording: tally)
            } catch {
                await tally.report(to: metrics)
                await fail(DictationFailure(error))
                return
            }
            guard !wasCancelled(mine) else { return }
            guard let heard else { continue }

            if appContext == nil {
                transition(to: .tidying)
                appContext = await contextFor(delivery)
            }
            let seeing = appContext ?? AppContext()
            pieces.append(await finish(heard, seeing: seeing, recording: tally))
            guard !wasCancelled(mine) else { return }
        }
        await tally.report(to: metrics)

        // Silence is not a fault, but returning quietly to idle would look like a broken app.
        guard !pieces.isEmpty else {
            await fail(DictationFailure(SpeechEngineError.nothingHeard))
            return
        }
        // Every piece was done while recording, and the screen it was read against still applies.
        if state == .transcribing { transition(to: .tidying) }
        let whole = Piece.joining(pieces)

        // Inserting a blank would delete the user's selection, so it is refused like silence.
        guard !whole.cleaned.text.isBlank else {
            await fail(DictationFailure(SpeechEngineError.nothingHeard))
            return
        }

        // Snippets after the tidier, whose punctuation is what stops a trigger crossing a sentence.
        let expanded = await expand(whole.cleaned.text)
        guard !wasCancelled(mine) else { return }

        let changes = AppliedChanges(
            corrections: whole.corrected.corrections, snippets: expanded.snippets,
            // The unrewritten sentence, which is the space the corrections' word ranges index.
            spokenWords: whole.heard.text.spokenWordCount)
        guard
            await insert(
                expanded.text, cleanedBy: whole.cleaned.producedBy, changes: changes,
                delivery: delivery)
        else { return }

        // Both run after the words are on screen, and neither can fail the dictation. §19.
        await count(changes)
        await learnWords(heard: whole.heard.text, wrote: expanded.text, seeing: appContext ?? AppContext())
    }

    /// The screen to tidy against, which for a retry is Uttrflow's own window and says nothing.
    private func contextFor(_ delivery: Delivery) async -> AppContext {
        switch delivery {
        case .insert:
            let read = await readContext()
            // Kept from this read: by insertion time the user has often switched away.
            insertedInto = read.applicationName
            insertedIntoIdentifier = read.bundleIdentifier
            return read
        case .copy:
            return AppContext()
        }
    }

    /// Recognises one window of the audio, answering `nil` when nothing was said in it.
    private func transcribe(
        _ audio: AudioSamples, _ window: Range<Int>, recording metrics: any MetricsRecording
    ) async throws -> Transcription? {
        let slice =
            AudioSamples(samples: Array(audio.samples[window]), sampleRate: audio.sampleRate) ?? .empty
        let heard = try await metrics.measuring(.transcription, clock: clock) {
            try await withStageTimeout(StageTimeout.transcription, clock: clock) {
                [speech] () async throws -> Heard in
                do {
                    return Heard.words(try await speech.transcribe(slice, options: .automatic))
                } catch SpeechEngineError.nothingHeard, SpeechEngineError.audioTooShort {
                    // Only when there is nothing else: alone, silence is refused below.
                    guard window != audio.samples.indices else { throw SpeechEngineError.nothingHeard }
                    return Heard.nothing
                }
            }
        }
        // Busy for ever is what refuses every later dictation. See `Docs/stuck-recording.md`.
        guard let heard else {
            throw SpeechEngineError.transcriptionFailed(description: "the recogniser did not answer")
        }
        guard case .words(let transcription) = heard, !transcription.isBlank else { return nil }
        return transcription
    }

    /// What the recogniser made of one window.
    private enum Heard: Sendable {
        case words(Transcription)
        case nothing
    }

    /// Runs the dictionary and the tidier over one recognised piece.
    private func finish(
        _ heard: Transcription, seeing appContext: AppContext, recording metrics: any MetricsRecording
    ) async -> Piece {
        // The dictionary before the tidier: a correction is argued from the sentence as heard.
        let corrected = await correct(heard, seeing: appContext, recording: metrics)
        let cleaned = await tidy(heard, saying: corrected.text, seeing: appContext, recording: metrics)
        return Piece(heard: heard, corrected: corrected, cleaned: cleaned)
    }

    /// Puts the user's own spellings in, leaving the transcript alone if it cannot. §19.
    private func correct(
        _ transcription: Transcription, seeing appContext: AppContext,
        recording metrics: any MetricsRecording
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
        _ transcription: Transcription, saying text: String, seeing appContext: AppContext,
        recording metrics: any MetricsRecording
    ) async -> TransformationResult {
        // Every piece of a dictation is tidied against the one screen read, so all see one situation.
        let request = TransformationRequest(
            transcription: transcription.saying(text), context: appContext, profile: profile,
            situation: SituationResolver.resolve(from: appContext))

        do {
            let tidied = try await metrics.measuring(.transformation, clock: clock) {
                try await withStageTimeout(StageTimeout.transformation, clock: clock) { [cleaner] in
                    try await cleaner.clean(request)
                }
            }
            // A language model that never answers costs the tidying, never the words.
            return tidied ?? TransformationResult(text: text, producedBy: .rules)
        } catch {
            return TransformationResult(text: text, producedBy: .rules)
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
            if let openRecording {
                self.openRecording = nil
                await recordings.discard(openRecording)
            }
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

extension DictationPipeline.Piece {
    /// Every piece as one, with the corrections' word ranges moved to where their piece begins.
    fileprivate static func joining(_ pieces: [Self]) -> Self {
        guard pieces.count > 1, let first = pieces.first else {
            return pieces.first
                ?? Self(
                    heard: Transcription(text: ""), corrected: .unchanged(""),
                    cleaned: TransformationResult(text: "", producedBy: .rules))
        }
        var corrections: [DictationCorrection] = []
        var wordsBefore = 0
        var heardText: [String] = []
        var correctedText: [String] = []
        var cleanedText: [String] = []
        var producedBy = first.cleaned.producedBy
        for piece in pieces {
            corrections += piece.corrected.corrections.map { $0.shifted(by: wordsBefore) }
            wordsBefore += piece.heard.text.spokenWordCount
            heardText.append(piece.heard.text)
            correctedText.append(piece.corrected.text)
            cleanedText.append(piece.cleaned.text)
            // Any piece the model left to the rules makes the whole a rules result.
            if piece.cleaned.producedBy != producedBy { producedBy = .rules }
        }
        let heard = Transcription(
            text: heardText.joined(separator: " "),
            detectedLanguage: first.heard.detectedLanguage,
            segments: pieces.flatMap(\.heard.segments),
            audioDuration: pieces.reduce(.zero) { $0 + $1.heard.audioDuration })
        return Self(
            heard: heard,
            corrected: CorrectedTranscript(
                text: correctedText.joined(separator: " "), corrections: corrections),
            cleaned: TransformationResult(text: cleanedText.joined(separator: " "), producedBy: producedBy))
    }
}

extension DictationCorrection {
    /// The same correction, indexing words `offset` further into a longer sentence.
    fileprivate func shifted(by offset: Int) -> Self {
        Self(
            heard: heard, wrote: wrote,
            wordRange: (wordRange.lowerBound + offset)..<(wordRange.upperBound + offset),
            entryID: entryID, reason: reason, heardConfidence: heardConfidence)
    }
}

extension String {
    /// Nothing but whitespace, the emptiness ``Transcription/isBlank`` means.
    fileprivate var isBlank: Bool { allSatisfy(\.isWhitespace) }

    /// How many words were spoken, counted the way the corrections' ranges count them.
    fileprivate var spokenWordCount: Int { split(whereSeparator: \.isWhitespace).count }
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
