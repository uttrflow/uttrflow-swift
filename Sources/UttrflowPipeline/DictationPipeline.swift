// The whole product in one actor: from the key going down to the text landing.
import UttrflowAI
public import UttrflowCore
public import struct Foundation.Date
public import struct Foundation.UUID

/// Speak, and the words appear where you were typing. See `Docs/pipeline.md`.
public actor DictationPipeline {
    let capture: any AudioCaptureEngine
    private let speech: any SpeechEngine
    /// The engine a retry asked for in place of `speech`, for that one retry only.
    private var retrySpeech: (any SpeechEngine)?
    /// A `var` so a clean-up step switched off takes effect on the next dictation rather than the next launch.
    private var cleaner: any TranscriptCleaning
    private let context: any ContextEngine
    /// The dictation's words, ranked against its initial screen; a closure so speech stays out of here.
    private let speechWords: @Sendable (AppContext) async -> [String]
    private let inserter: any TextInserting
    let corrector: any WordCorrecting
    let snippets: any SnippetExpanding
    private let learner: any DictationLearning
    private let consent: any LearningConsent
    private let vocabulary: any VocabularyLearning
    /// The spelling the user prefers for each listed word, read once per join.
    let spellings: @Sendable () async -> [String: String]
    let metrics: any MetricsRecording
    /// Which quality layers run; a layer that is off leaves its stage's input as it came.
    let layers: QualityLayers
    /// Where the account of what the clean-up steps did to each dictation goes.
    private let cleaningRecorder: any CleaningRecording
    /// The apps the user has told Uttrflow to treat as somewhere other than the table says.
    private var destinationOverrides: DestinationOverrides
    /// The tidier, overrides and languages this dictation began with, so a change made while speaking lands on the next one.
    private var inUse:
        (cleaner: any TranscriptCleaning, overrides: DestinationOverrides, profile: UserProfile)?
    private var dictationContext: DictationContext?
    private let recordings: any RecordingKeeper
    /// Where a retried dictation's words go, since the field they were meant for is gone.
    private let clipboard: any TextInserting
    let clock: any Clock<Duration>
    private var profile: UserProfile
    /// How a recording is cut into pieces the recogniser and tidier take one at a time.
    private let windowing: SpeechWindowing
    /// How often the recording is looked at for a piece to work on while the key is held.
    private let earlyPoll: Duration
    /// Paces that look on its own clock, so a test driving the stage clock wakes only stages.
    private let pollClock: any Clock<Duration>

    private var state: DictationState = .idle
    nonisolated let observers = RevisionedStateObservers()
    /// The finished pieces' words while the key is held, shown in the panel and never typed into the field.
    private var heardSoFar: String?
    private let heardObservers = StateObservers<String?>()

    /// Counts dictations, so a cancel can name the one it abandoned.
    private(set) var generation = 0
    private var cancelledGeneration: Int?

    /// Held across every await before the state shows a dictation's next step, so no second entry slips in.
    private var hasTurn = false

    /// How long `prepare()` waits for the speech model before calling the load failed.
    private let speechLoadLimit: Duration
    /// How many loads are running, since a switch can begin one before the last has ended.
    private var loadsUnderWay = 0

    /// Reads how long the microphone has been open, closing over the injected clock.
    private var stopwatch: (() -> Duration)?
    private var spokenFor: Duration?
    /// Reads how long ago the key came up, so the wait it costs the user is timed; `nil` for a retry.
    private var sinceRelease: (() -> Duration)?
    /// The screen-read time spent before key-up, which the wait after it does not include.
    private var readsBeforeRelease: Duration = .zero
    /// The last dictations' waits, which name the cause of each slow one.
    private var waits = DictationWaits()

    /// The application named by the context read during tidying, before the user moved on.
    private var insertedInto: String?
    private var insertedIntoIdentifier: String?
    /// Whether the screen read found a field that hides what is typed, so nothing of this dictation is kept.
    private var destinationIsSecure = false

    /// The kept audio of the dictation under way, deleted or left for a retry as it ends.
    private var openRecording: UUID?
    /// A cancelled recording offered for Restore, and the wait that deletes it when the window closes.
    private var restorable: (id: UUID, expiry: Task<Void, Never>)?

    /// A recording cancelled at least this long is said to be discarded and kept for Restore. See Docs/recordings.md.
    public static let restoreThreshold: Duration = .seconds(5)
    /// How long a cancelled recording can be restored before it is deleted.
    public static let restoreWindow: Duration = .seconds(60)
    /// Destination facts read for audio kept for a retry.
    private var recordingDestination: AppContext?
    /// The formatter destination read for that recording, retained even if app rules later change.
    private var recordingFieldKind: Destination?

    /// What the early loop holds while the key is down, handed to the release pass in one step.
    private var early = EarlyWork()
    /// What reading the screen has cost the dictation under way, and its latest reading.
    private var screenReads = DictationScreenReads()
    /// How many early screen reads have come back and been kept or dropped, so a test can wait for the last one.
    var earlyReadsSettled: Int { early.readsSettled }
    /// Ranked once per dictation, against the screen it began on, and given to every piece.
    private(set) var dictationWords: [String]?
    /// Pieces of this dictation that held speech and decoded to no words twice, left out of what is inserted.
    private var missedPieces = 0

    /// The settings and screen resolved at the start of a dictation and shared by every piece.
    private struct DictationContext: Sendable {
        let app: AppContext
        let situation: Situation
        var listening: ListeningLanguages
        let vocabulary: [String]
        let profile: UserProfile
        let corrector: any WordCorrecting
    }

    /// What the clean-up steps did to each piece of the dictation under way, reported as one when it ends.
    private var cleaningRecords: [KeptRecord] = []
    /// Early spans the release join dropped, whose records are not part of the dictation's account.
    private var droppedSpans: Set<UUID> = []
    /// The early span the running task tidies, so its record can be withdrawn if the span is dropped.
    @TaskLocal static var tidiedSpan: UUID?

    /// One piece's cleaning record and the early span it came from, if any.
    private struct KeptRecord {
        let span: UUID?
        let record: CleaningRecord
    }
    /// Runs what is said while the command key is held, in place of inserting it.
    private let commands: EditCommandRegistry
    /// Where the next recording goes, set by the key that opens it and spent when it opens.
    private var nextRoute: UtteranceRoute = .dictation
    /// Where the recording under way goes.
    private var recordingRoute: UtteranceRoute = .dictation

    public init(
        capture: any AudioCaptureEngine,
        speech: any SpeechEngine,
        cleaner: any TranscriptCleaning,
        context: any ContextEngine,
        inserter: any TextInserting,
        speechWords: @escaping @Sendable (AppContext) async -> [String] = { _ in [] },
        corrector: any WordCorrecting = NoTextChanges(),
        snippets: any SnippetExpanding = NoTextChanges(),
        learner: any DictationLearning = NoTextChanges(),
        vocabulary: any VocabularyLearning = NoTextChanges(),
        spellings: @escaping @Sendable () async -> [String: String] = { [:] },
        consent: any LearningConsent = NothingAskedYet(),
        metrics: any MetricsRecording = NoOpMetricsRecorder(),
        cleaningRecorder: any CleaningRecording = NoOpCleaningRecorder(),
        destinationOverrides: DestinationOverrides = .none,
        recordings: any RecordingKeeper = RecordingsNotKept(),
        clipboard: (any TextInserting)? = nil,
        clock: any Clock<Duration> = ContinuousClock(),
        profile: UserProfile = .default,
        windowing: SpeechWindowing = .standard,
        earlyPoll: Duration = .seconds(1),
        pollClock: any Clock<Duration> = ContinuousClock(),
        speechLoadLimit: Duration = StageTimeout.speechModelLoad,
        commands: EditCommandRegistry = EditCommandRegistry(),
        layers: QualityLayers = QualityLayers()
    ) {
        self.capture = capture
        self.speech = speech
        self.cleaner = cleaner
        self.context = context
        self.inserter = inserter
        self.speechWords = layers.isOn(.recogniserBias) ? speechWords : { @Sendable _ in [] }
        self.layers = layers
        self.corrector = corrector
        self.snippets = snippets
        self.learner = learner
        self.vocabulary = vocabulary
        self.spellings = spellings
        self.consent = consent
        self.metrics = metrics
        self.cleaningRecorder = cleaningRecorder
        self.destinationOverrides = destinationOverrides
        self.recordings = recordings
        self.clipboard = clipboard ?? inserter
        self.clock = clock
        self.profile = profile
        self.windowing = windowing
        self.earlyPoll = earlyPoll
        self.pollClock = pollClock
        self.speechLoadLimit = speechLoadLimit
        self.commands = commands
    }

    /// Sends the next recording to `route`; every recording after it goes back to dictation.
    public func route(next route: UtteranceRoute) {
        nextRoute = route
    }

    /// Takes the user's clean-up choices as they stand now, for every dictation after this one.
    public func adopt(
        cleaner: any TranscriptCleaning, destinationOverrides: DestinationOverrides
    ) {
        self.cleaner = cleaner
        self.destinationOverrides = destinationOverrides
        // Nothing is being spoken, so nothing is owed the choices the last dictation ran under.
        if !isBusy { inUse = nil }
    }

    /// Takes the languages the user speaks as they stand now, for every dictation after this one.
    public func adopt(profile: UserProfile) {
        self.profile = profile
        if !isBusy { inUse = nil }
    }

    /// The tidier this dictation is being run with, which a mid-dictation change does not replace.
    var runningCleaner: any TranscriptCleaning { inUse?.cleaner ?? cleaner }

    /// The overrides this dictation is being run with, for the same reason.
    var runningOverrides: DestinationOverrides { inUse?.overrides ?? destinationOverrides }

    /// The languages this dictation is being listened for and tidied in, for the same reason.
    var runningProfile: UserProfile { inUse?.profile ?? profile }

    /// Where this dictation's pieces are cut, for how long the person it is running for pauses.
    var runningWindowing: SpeechWindowing { windowing.adjusted(for: runningProfile.pauses) }

    /// The dictionary held at the start of this dictation; a word added meanwhile waits for the next.
    var runningCorrector: any WordCorrecting { dictationContext?.corrector ?? corrector }

    /// Which recogniser the next dictation is transcribed by.
    public var speechKind: SpeechEngineKind { speech.kind }

    /// Fixes all three for the dictation about to begin.
    private func takeSettings() {
        inUse = (cleaner, destinationOverrides, profile)
    }

    public var currentState: DictationState { state }

    /// Whether the recogniser has loaded and the next dictation will not wait for it.
    public private(set) var isReady = false
    /// Why the last load ended without a model; cleared by a load that works.
    public private(set) var lastLoadFailure: SpeechLoadFailureClass?

    /// Whether `prepare` is loading the recogniser right now, which is when a new dictation is refused.
    public var isLoading: Bool { loadsUnderWay > 0 }

    /// Keeps readiness truthful when the speech engine unloads itself.
    public func speechWasReleased() {
        isReady = false
    }

    /// Marks readiness when a lazy reload completes during transcription.
    public func speechWasLoaded() {
        isReady = true
    }

    /// Every state the pipeline passes through, from now on.
    public func states() -> AsyncStream<DictationState> {
        observers.states(startingWith: state)
    }

    /// The finished pieces' words while the key is held; absent at rest, after a cancel and for a secure field.
    public func wordsHeardSoFar() -> AsyncStream<String?> {
        heardObservers.makeStream(startingWith: heardSoFar)
    }

    /// Loads the speech model so the first dictation is not the slow one. See `Docs/startup.md`.
    public func prepare() async {
        loadsUnderWay += 1
        defer { loadsUnderWay -= 1 }
        let engine = speech
        var timedOut = false
        do {
            // Stops waiting at the limit rather than awaiting a cancel, since a blocked load ignores one. See `Docs/startup.md`.
            let loaded = try await withStageTimeout(speechLoadLimit, clock: clock) {
                try await engine.prepare()
                return true
            }
            guard loaded == true else {
                timedOut = true
                throw SpeechEngineError.modelLoadFailed(
                    description: "the load did not finish within \(speechLoadLimit)")
            }
            isReady = true
            lastLoadFailure = nil
            // A retry that works clears the notice the failed attempt left behind.
            if case .failed = state, !isBusy { transition(to: .idle) }
        } catch {
            isReady = false
            lastLoadFailure = timedOut ? .timedOut : SpeechLoadFailureClass(error)
            // Never over a dictation in progress: loading can run while the user speaks.
            if !isBusy {
                transition(to: .failed(DictationFailure(error, speechEngineKind: engine.kind)))
            }
        }
    }

    // MARK: The sequence

    /// Whether a new dictation can begin, counting one that holds the turn before its state has moved.
    private var isBusy: Bool { hasTurn || state.isBusy || early.decodesInFlight > 0 }

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
        takeSettings()
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

    /// Clears what one attempt learnt about its words, so the next asks afresh.
    private func forgetTheLastAttempt() {
        dictationWords = nil
        dictationContext = nil
        missedPieces = 0
        screenReads = DictationScreenReads()
        sinceRelease = nil
    }

    /// Abandons the dictation at any stage, inserting nothing; audio already claimed is kept so the speech can be retried.
    public func cancel() async {
        early.pendingCapture?.cancel()
        early.pendingCapture = nil
        early.pendingCaptureElapsed = nil
        nextRoute = .dictation
        cancelledGeneration = generation
        // Read before the early loop is dropped, since a kept recording is labelled with this screen.
        let seen = early.context ?? dictationContext?.app
        let listenedFor = state == .recording && !hasTurn ? stopwatch?() : nil
        early.cancel()
        show(heard: nil)
        guard let listenedFor, listenedFor >= Self.restoreThreshold else {
            // A slip or a short take is cancelled silently, as a restart rather than a loss.
            await capture.cancel()
            await settleRecording(wordsLost: true)
            return transition(to: .idle)
        }
        stopwatch = nil
        await capture.cancelKeepingRecording()
        let kept = await offerRestore(seen: seen)
        transition(to: .discarded(DictationDiscard(spokenFor: listenedFor, keptRecording: kept)))
    }

    /// Keeps the cancelled recording for the restore window, or deletes it at once for a secure field.
    private func offerRestore(seen: AppContext?) async -> UUID? {
        guard let kept = await recordings.current() else { return nil }
        guard !destinationIsSecure else {
            await recordings.discard(kept.id)
            return nil
        }
        if let seen {
            let fieldKind = SituationResolver.resolve(from: seen, overrides: runningOverrides).destination
            await recordings.setDestination(seen, fieldKind: fieldKind, for: kept.id)
        }
        restorable?.expiry.cancel()
        let expiry = Task { [clock] in
            do { try await clock.sleep(for: Self.restoreWindow) } catch { return }
            await self.closeRestoreWindow(kept.id)
        }
        restorable = (kept.id, expiry)
        return kept.id
    }

    /// Deletes a cancelled recording nobody restored, and takes its notice down if it is still up.
    private func closeRestoreWindow(_ id: UUID) async {
        guard restorable?.id == id else { return }
        restorable = nil
        await recordings.discard(id)
        if case .discarded(let discard) = state, discard.keptRecording == id { transition(to: .idle) }
    }

    /// Whether the dictation that started at `mine` is abandoned, by itself or by a later cancel.
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

    /// Resolves the screen, vocabulary, language policy and initial warm session once for this dictation.
    private func beginWorkingAhead(_ mine: Int) {
        recordingFieldKind = nil
        forgetTheLastAttempt()
        show(heard: nil)
        early.begin()
        early.task = Task { [cleaner = runningCleaner, overrides = runningOverrides] in
            let seeing = await self.earlyContextRead(mine)
            guard self.isStillRunning(mine) else { return }
            await self.resolveDictationContext(seeing, cleaner: cleaner, overrides: overrides)
            await self.workAhead(mine)
        }
    }

    /// Resolves the values every piece shares, after the single screen read has settled.
    private func resolveDictationContext(
        _ app: AppContext, cleaner: any TranscriptCleaning, overrides: DestinationOverrides
    ) async {
        recordingDestination = app
        let situation =
            recordingFieldKind.map {
                Situation(app: app, insertion: app.insertionPoint, destination: $0)
            } ?? SituationResolver.resolve(from: app, overrides: overrides)
        let words = await speechWords(app)
        let fixedCorrector = await corrector.fixed()
        dictationWords = words
        dictationContext = DictationContext(
            app: app, situation: situation, listening: ListeningLanguages(profile: runningProfile),
            vocabulary: words, profile: runningProfile, corrector: fixedCorrector)
        await cleaner.warm(for: situation)
    }

    /// Transcribes each piece the moment a pause ends it and tidies it beside the next one, until the key is released.
    private func workAhead(_ mine: Int) async {
        while state == .recording, generation == mine, !wasCancelled(mine), !Task.isCancelled {
            try? await pollClock.sleep(for: earlyPoll)
            guard state == .recording, generation == mine, !wasCancelled(mine), !Task.isCancelled
            else { return }

            // One sample before the cut is kept, so a later piece is never taken for the whole recording.
            let lead = early.cut > 0 ? 1 : 0
            let audio = await capture.capturedSoFar(from: early.cut - lead)
            guard
                let cut = runningWindowing.nextCut(
                    in: audio.samples, sampleRate: audio.sampleRate, from: lead,
                    boundaries: audio.discontinuities)
            else { continue }
            let start = early.cut
            let end = early.cut - lead + cut

            // A leftover tidy is folded in only once there is a next piece to recognise.
            if let earlyTidyTask = early.tidyTask?.task {
                let piece = await earlyTidyTask.value
                guard state == .recording, generation == mine, !wasCancelled(mine), !Task.isCancelled
                else { return }
                early.spans.append(.done(piece, span: early.tidyTask?.span))
                early.tidyTask = nil
            }

            let seeing = await earlyContextRead(mine)
            if dictationContext == nil {
                await resolveDictationContext(seeing, cleaner: runningCleaner, overrides: runningOverrides)
            }
            // Recognition only; a key released mid-tidy is not held to this, since the tidy runs on past it.
            early.pieceInFlight = true
            early.decodesInFlight += 1
            early.recognising = true
            defer { early.recognising = false }
            let heard: Transcription?
            do {
                heard = try await transcribe(
                    audio, lead..<cut, biasedTowards: await vocabulary(mine, seeing: seeing),
                    recording: NoOpMetricsRecorder(), skippingAMiss: false, for: mine)
            } catch {
                early.decodesInFlight -= 1
                guard generation == mine, !wasCancelled(mine) else { return }
                // A failed piece is left for the end, where it is reported; the rest still work ahead.
                early.spans.append(.pending(early.cut..<end))
                early.cut = end
                early.lastWindowStart = start
                early.pieceInFlight = false
                continue
            }
            early.decodesInFlight -= 1
            guard generation == mine, !wasCancelled(mine) else { return }
            // Cut here, before the tidy, so a key-up mid-tidy still knows what audio is left to recognise.
            early.cut = end
            early.lastWindowStart = heard == nil ? nil : start
            if let heard {
                // The piece before is read as heard, which every path has once it is recognised.
                let preceding = early.spans.last?.heard
                let span = UUID()
                let tidy = Task {
                    await Self.$tidiedSpan.withValue(span) {
                        await self.finish(
                            heard, seeing: seeing, correctionSeeing: seeing, after: preceding,
                            recording: NoOpMetricsRecorder(), for: mine)
                    }
                }
                early.tidyTask = Span.Tidying(task: tidy, heard: heard, span: span)
                // Warm for the next piece after this one finishes, without making key-up wait for warm-up.
                Task {
                    let piece = await tidy.value
                    guard self.state == .recording, self.generation == mine,
                        !self.wasCancelled(mine)
                    else { return }
                    self.showFinished(piece)
                    await self.runningCleaner.warm(
                        for: SituationResolver.resolve(
                            from: seeing, overrides: self.runningOverrides))
                }
            }
            early.pieceInFlight = early.tidyTask != nil
        }
    }

    /// The words every piece of this dictation is biased towards, ranked once and then remembered.
    private func vocabulary(_ mine: Int, seeing context: AppContext) async -> [String] {
        if let dictationContext { return dictationContext.vocabulary }
        if let dictationWords { return dictationWords }
        let words = await speechWords(context)
        // A cancelled dictation's words are not kept for the one now under way.
        guard isStillRunning(mine) else { return words }
        dictationWords = words
        return words
    }

    /// The screen as it was while the key was held, read once for every early piece.
    private func earlyContextRead(_ mine: Int) async -> AppContext {
        if let seen = early.context { return seen }
        let read: AppContext
        if let pending = early.pendingInsertion {
            read = await contextAfterPendingInsertion(pending, for: mine)
        } else {
            read = await readContext()
        }
        // Counted before the decision below, which runs without a suspension, so a waiter sees it made.
        early.readsSettled += 1
        // A read the user cancelled belongs to no dictation: the one now under way read its own screen.
        guard isStillRunning(mine) else { return read }
        early.context = read
        insertedInto = read.applicationName
        insertedIntoIdentifier = read.bundleIdentifier
        destinationIsSecure = read.isSecure
        return read
    }

    /// Waits for a previous paste to reach the caret before the new dictation captures its context.
    private func contextAfterPendingInsertion(_ text: String, for mine: Int) async -> AppContext {
        let wanted = PendingInsertionConfirmation.collapsed(text)
        var waited = Duration.zero
        while waited < PendingInsertionConfirmation.budget, isStillRunning(mine), !Task.isCancelled {
            let latest = await readContext()
            let preceding = latest.precedingText.map(PendingInsertionConfirmation.collapsed) ?? ""
            if preceding.hasSuffix(wanted) {
                early.pendingInsertion = nil
                return latest
            }
            do { try await clock.sleep(for: PendingInsertionConfirmation.interval) } catch { break }
            waited = min(PendingInsertionConfirmation.budget, waited + PendingInsertionConfirmation.interval)
        }
        guard isStillRunning(mine), !Task.isCancelled else { return AppContext() }
        return await readContext()
    }

    /// The situation and languages a piece is tidied in: the dictation's own, or what this screen implies.
    func tidyingFrame(seeing appContext: AppContext) -> (situation: Situation, profile: UserProfile) {
        (
            dictationContext?.situation
                ?? SituationResolver.resolve(from: appContext, overrides: runningOverrides),
            dictationContext?.profile ?? runningProfile
        )
    }

    /// Hands the dictation's account to its page when anything was tidied or skipped; never a secure field.
    private func reportCleaning(for delivery: Delivery) async {
        if !cleaningRecords.isEmpty, !destinationIsSecure, delivery != .command {
            var record = CleaningRecord.merging(cleaningRecords.map(\.record))
            record.dictionaryRevision = dictationContext?.corrector.revision
            await cleaningRecorder.record(record)
        }
    }

    /// Stops a span the release join re-decodes, and takes its record out of the dictation's account.
    private func withdraw(_ span: Span) async {
        let id: UUID?
        switch span {
        case .done(_, let span): id = span
        case .tidying(let running):
            id = running.span
            running.task.cancel()
            _ = await running.task.value
        case .pending: id = nil
        }
        guard let id else { return }
        droppedSpans.insert(id)
        cleaningRecords.removeAll { $0.span == id }
    }

    /// Keeps a piece's cleaning record for the dictation's account, unless that dictation has ended.
    func keep(_ cleaning: CleaningRecord, for mine: Int) {
        let span = Self.tidiedSpan
        guard isStillRunning(mine), !(span.map(droppedSpans.contains) ?? false) else { return }
        cleaningRecords.append(KeptRecord(span: span, record: cleaning))
    }

    /// Whether the dictation that started at `mine` is still the one under way.
    func isStillRunning(_ mine: Int) -> Bool {
        generation == mine && !wasCancelled(mine)
    }

    /// Asks what is on screen within what the dictation's screen-read limit has left, so one stuck app is waited on once.
    private func readContext() async -> AppContext {
        let left = StageTimeout.screenRead - screenReads.cost.duration
        guard left > .zero else { return AppContext(unavailable: .timedOut) }
        // Counted before the read begins, so input that lands while it runs outdates it.
        let inputsBefore = await context.inputsSeen()
        let (read, elapsed) = await Self.timed(on: clock) { [context, clock] in
            ((try? await withStageTimeout(left, clock: clock) {
                await context.currentContext()
            }) ?? nil) ?? AppContext(unavailable: .timedOut)
        }
        screenReads.record(read, took: elapsed, inputsBefore: inputsBefore)
        return read
    }

    /// Runs `operation` and says how long it took on `clock`.
    private static func timed<Value>(
        on clock: some Clock<Duration>, isolation: isolated (any Actor)? = #isolation,
        _ operation: () async -> Value
    ) async -> (Value, Duration) {
        let start = clock.now
        let value = await operation()
        return (value, start.duration(to: clock.now))
    }

    /// Uses caret text read just before insertion, refusing it when the destination app changed.
    private func insertionContextForWrite(matching destination: AppContext?) async -> AppContext {
        // With no key, click or switch since the last read, and no earlier paste still landing, it is the caret now.
        let unchanged =
            early.pendingInsertion == nil ? screenReads.unchanged(inputsNow: await context.inputsSeen()) : nil
        let current = if let unchanged { unchanged } else { await readContext() }
        guard let destination else { return current }
        if let expected = destination.bundleIdentifier, let actual = current.bundleIdentifier {
            return expected == actual ? current : .unknown
        }
        if let expected = destination.applicationName, let actual = current.applicationName {
            return expected == actual ? current : .unknown
        }
        return current
    }

    // MARK: Stages

    /// One span of a recording: the words a pass finished it with, or audio a later pass still has to do.
    private enum Span {
        case done(Piece, span: UUID?)
        case pending(Range<Int>)
        /// Still being tidied when the key came up; joined by the release pass instead of waited on at the hand-off.
        case tidying(Tidying)

        /// A tidy under way and the words it tidies, which the next piece reads before the tidy ends.
        struct Tidying {
            let task: Task<Piece, Never>
            let heard: Transcription
            let span: UUID
        }

        /// The words recognised for this span, or `nil` for audio not yet recognised.
        var heard: Transcription? {
            switch self {
            case .done(let piece, _): piece.heard
            case .pending: nil
            case .tidying(let tidying): tidying.heard
            }
        }
    }

    /// The early loop's state, beside the main sequence rather than in it. See `Docs/early-transcription.md`.
    private struct EarlyWork {
        /// Spans the early loop reached while the key was held, and where the audio it consumed ends.
        var spans: [Span] = []
        var cut = 0
        var lastWindowStart: Int?
        var task: Task<Void, Never>?
        /// A tidy the early loop started but has not yet folded into `spans`, picked up by the release pass at key-up.
        var tidyTask: Span.Tidying?
        /// Whether a piece is being recognised or tidied right now, which is what makes the drain a wait worth timing.
        var pieceInFlight = false
        /// Early recogniser calls still running after their cancelled task has returned.
        var decodesInFlight = 0
        /// Whether the loop is inside a recognition, which key-up lets finish rather than cancel.
        var recognising = false
        var context: AppContext?
        /// A microphone opened while a modifier press settles, before it belongs to a dictation.
        var pendingCapture: Task<Void, Never>?
        var pendingCaptureElapsed: (@Sendable () -> Duration)?
        /// Text from an unconfirmed paste, checked at the caret before another dictation starts.
        var pendingInsertion: String?
        var readsSettled = 0

        /// Clears what a previous dictation left, before the loop for this one starts.
        mutating func begin() {
            spans = []
            cut = 0
            lastWindowStart = nil
            tidyTask = nil
            context = nil
        }

        /// Stops the loop and drops everything it reached.
        mutating func cancel() {
            task?.cancel()
            task = nil
            begin()
            pieceInFlight = false
        }

        /// Returns what the drained loop reached and clears it, a tidy still running joining as its last span.
        mutating func handOff() -> (
            spans: [Span], cut: Int, lastWindowStart: Int?, context: AppContext?
        ) {
            var handed = spans
            if let tidyTask { handed.append(.tidying(tidyTask)) }
            let result = (handed, cut, lastWindowStart, context)
            task = nil
            begin()
            pieceInFlight = false
            return result
        }
    }

    /// Where the finished words go.
    private enum Delivery {
        case insert
        case copy
        /// Run by the edit commands against the selection; never inserted.
        case command
    }

    private func process(_ audio: AudioSamples, _ mine: Int, delivery: Delivery) async {
        // Checked before the state moves, so an abandoned run never overwrites the rest a cancel sets.
        guard !wasCancelled(mine) else { return }
        if state != .transcribing { transition(to: .transcribing) }
        if let quality = CaptureQuality.measure(
            samples: audio.samples, sampleRate: audio.sampleRate, gaps: audio.gaps)
        {
            await metrics.recordCaptureQuality(quality)
        }
        show(heard: nil)

        let handed = await takeOver(for: audio, delivery: delivery, generation: mine)
        let tally = StageTally()
        var appContext = handed.context
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
        let pieces: [Piece]
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
            pieces = heard
            appContext = seen
        }
        guard !wasCancelled(mine) else { return }
        await tally.report(to: metrics)
        await deliver(pieces, from: audio, read: appContext, recording: tally, delivery: delivery, for: mine)
    }

    /// What the early loop hands over: the spans it cut, the windows still to recognise, and the screen it read.
    private struct Takeover {
        let spans: [Span]
        let remainder: [Range<Int>]
        let context: AppContext?
    }

    /// How recognising the rest of a dictation ended; an exit that is not one of these does not compile.
    private enum Recognition {
        case heard([Piece], seeing: AppContext?)
        case failed(DictationFailure)
        case abandoned
    }

    /// Finishes the early loop's work and takes it over, dropping pieces cut from other audio than this.
    private func takeOver(
        for audio: AudioSamples, delivery: Delivery, generation mine: Int
    ) async -> Takeover {
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
        if delivery == .copy || cut > audio.samples.count {
            for span in spans { await withdraw(span) }
            spans = []
            cut = 0
            cleaningRecords = []
        }

        var remainder = runningWindowing.windows(
            in: audio.samples, sampleRate: audio.sampleRate, from: cut,
            joiningPreviousWindowFrom: delivery != .copy ? previousWindowStart : nil,
            boundaries: audio.discontinuities)
        if let first = remainder.first, first.lowerBound < cut, let dropped = spans.popLast() {
            await withdraw(dropped)
        }
        // Nothing at all still goes to the recogniser, whose refusal names the reason.
        if spans.isEmpty, remainder.isEmpty { remainder = [cut..<audio.samples.count] }
        return Takeover(spans: spans, remainder: remainder, context: handed.context)
    }

    /// Recognises every pending span in order, with one tidy running beside the next recognition.
    private func recognise(
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

    /// Joins the pieces, re-cases them for where the caret is now, inserts or copies them, then counts and learns.
    private func deliver(
        _ pieces: [Piece], from audio: AudioSamples, read appContext: AppContext?,
        recording tally: StageTally, delivery: Delivery, for mine: Int
    ) async {
        // Silence is not a fault, but returning quietly to idle would look like a broken app.
        guard !pieces.isEmpty else {
            await reportCleaning(for: delivery)
            await fail(Self.silence(missedPieces > 0 ? .speechWithoutWords : .nothingHeard, in: audio))
            return
        }
        let seen = appContext ?? AppContext()
        // Every piece is done while recording, and the screen it is read against still applies.
        if state == .transcribing { transition(to: .tidying) }
        let joining =
            dictationContext?.situation
            ?? SituationResolver.resolve(from: seen, overrides: runningOverrides)
        // Inserting a blank would delete the user's selection, so it is refused like silence.
        let joinedPieces = await join(
            pieces, going: joining, seeing: seen, recording: tally, for: mine)
        guard !wasCancelled(mine) else { return }
        // After the join, so a seam correction or snippet expansion that gave up is in the account.
        await reportCleaning(for: delivery)
        guard let joined = joinedPieces else {
            await fail(DictationFailure(SpeechEngineError.nothingHeard))
            return
        }
        let (whole, joiningFormatter, expanded) = (joined.whole, joined.formatter, joined.expanded)
        let finalEnforcement = LatinScript.enforcement(of: expanded.text)
        var output = finalEnforcement.text
        guard output.hasRecognisableContent else {
            await fail(DictationFailure(SpeechEngineError.nothingHeard))
            return
        }

        if delivery == .command {
            await runCommand(whole.heard, seeing: appContext, generation: mine)
            return
        }

        let insertionContext: AppContext
        if delivery == .insert {
            insertionContext = await insertionContextForWrite(matching: appContext)
            guard !wasCancelled(mine) else { return }
            let situation = SituationResolver.resolve(from: insertionContext, overrides: runningOverrides)
            let formatter = DestinationFormatter.standard(for: situation)
            // Re-casing is owed only for tidied words whose caret or destination moved since they were cased.
            let caretMoved =
                insertionContext.insertionPoint.sentenceState != seen.insertionPoint.sentenceState
                || formatter.firstWord != joiningFormatter.firstWord
                || formatter.destination != joiningFormatter.destination
            if whole.cleaned.producedBy != .untidied, caretMoved {
                output =
                    FirstWordPass(
                        policy: formatter.firstWord, state: insertionContext.insertionPoint.sentenceState,
                        onScreen: [
                            insertionContext.documentName, insertionContext.selectedText,
                            insertionContext.precedingText, insertionContext.followingText,
                        ].compactMap { $0 }, heard: whole.heard.text,
                        capitaliseCalendarWords: formatter.firstWord == .fromInsertionPoint
                            && formatter.destination != .codeEditor,
                        vocabulary: dictationContext?.vocabulary ?? dictationWords ?? [],
                        keepsCommandCase: formatter.keepsCommandCase
                    )
                    .apply(Draft(keepingLineBreaks: output)).text
            }
        } else {
            insertionContext = seen
        }

        // Pads the words with a space where the field's surrounding text would otherwise join them.
        let destination = SituationResolver.resolve(from: insertionContext, overrides: runningOverrides)
            .destination
        let toWrite = insertionContext.insertionPoint.paddedBoundary(
            for: OutputSafety.checked(output).text, in: destination)

        let changes = AppliedChanges(
            corrections: DictationCorrection.locating(
                whole.corrected.corrections, from: whole.corrected.text, in: toWrite),
            snippets: expanded.snippets,
            entriesTaken: whole.cleaned.entriesTaken,
            // The unrewritten sentence, which is the space the corrections' word ranges index.
            spokenWords: whole.heard.text.spokenWords.count,
            // A snippet changes the word count, so the ledger's positions hold only when none fired.
            changeLedger: expanded.snippets.isEmpty ? whole.cleaned.changeLedger : nil,
            scriptConversions: joined.scriptConversions + ScriptConversions(finalEnforcement),
            heard: whole.heard.text)
        guard
            let attempt = await insert(
                toWrite, cleanedBy: whole.cleaned.producedBy, changes: changes,
                doubtful: DoubtfulWordsOutcome.locating(whole.heard.saying(whole.corrected), in: toWrite),
                delivery: delivery, generation: mine, recording: tally,
                unavailableEngines: whole.cleaned.cleaning?.unavailableEngines ?? [],
                destination: InsertionDestination(
                    applicationName: appContext?.applicationName,
                    bundleIdentifier: appContext?.bundleIdentifier,
                    processIdentifier: appContext?.processIdentifier, field: appContext?.field))
        else { return }
        // Read before the next await, since the next dictation may start once these words are on screen.
        let wasSecure = destinationIsSecure
        // A snippet's caret moves only in the field that took the words, verified there; otherwise it stays at the end.
        if delivery == .insert, let back = expanded.caretBack(inWritten: toWrite), back > 0 {
            _ = await inserter.placeCaret(back: back)
        }

        // An unconfirmed paste is not proof the words reached the user, so nothing is learnt from it yet.
        guard attempt.arrival != .unconfirmed else {
            early.pendingInsertion = toWrite
            return
        }
        // An application the user declined is learned nothing from, by counting or by the dictionary.
        let learnedFrom = landedIn(attempt)?.bundleIdentifier ?? appContext?.bundleIdentifier
        guard await consent.mayLearn(from: learnedFrom) else { return }
        // A secret is not a word to learn or count, by the same gate that keeps it out of History.
        guard let kept = KeptWords.of(toWrite, intoSecureField: wasSecure) else { return }
        // Both run after the words are on screen, and neither can fail the dictation. §19.
        await count(changes, writtenIn: kept)
        // A destination reported by the inserter wins over a screen read made before the switch.
        if let landedID = landedIn(attempt)?.bundleIdentifier,
            let readID = appContext?.bundleIdentifier, landedID != readID
        {
            return
        }
        await learnWords(heard: whole.heard.text, wrote: toWrite, seeing: seen)
    }

    /// The screen to tidy against, which for a retry is Uttrflow's own window and says nothing.
    private func contextFor(_ delivery: Delivery) async -> AppContext {
        switch delivery {
        case .insert, .command:
            let read = await readContext()
            // Kept from this read: by insertion time the user has often switched away.
            insertedInto = read.applicationName
            insertedIntoIdentifier = read.bundleIdentifier
            destinationIsSecure = read.isSecure
            let recordedDestination = early.context ?? dictationContext?.app ?? read
            recordingDestination = recordedDestination
            let fieldKind =
                dictationContext?.situation.destination
                ?? SituationResolver.resolve(from: recordedDestination, overrides: runningOverrides)
                .destination
            if let openRecording {
                await recordings.setDestination(
                    recordedDestination, fieldKind: fieldKind, for: openRecording)
            }
            return read
        case .copy:
            return recordingDestination ?? AppContext()
        }
    }

    /// Recognises one window of the audio, answering `nil` when nothing was said in it; speech with no words is decoded twice.
    private func transcribe(
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
            heard = try await decode(
                slice, whole: whole, biasedTowards: [], after: nil, recording: metrics, generation: mine)
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
    private static func silence(_ heard: SpeechEngineError, in audio: AudioSamples) -> DictationFailure {
        DictationFailure(heard == .nothingHeard && audio.carriesNoSignal ? SpeechEngineError.noSignal : heard)
    }

    /// What the recogniser made of one window.
    private enum Heard: Sendable {
        case words(Transcription)
        case nothing
        case missed
    }

    /// Puts the finished text where the user was typing, answering how it arrived, or nil on failure.
    private func insert(
        _ text: String, cleanedBy: TransformerKind, changes: AppliedChanges,
        doubtful: DoubtfulWordsOutcome = .notAvailable, delivery: Delivery, generation mine: Int,
        recording tally: StageTally, unavailableEngines: [CleaningRecord.UnavailableEngine],
        destination: InsertionDestination
    ) async -> InsertionAttempt? {
        let inserter = delivery == .copy ? clipboard : self.inserter
        // Said before the words are handed over, because the app takes its own time to show them.
        transition(to: .inserting(into: insertedInto))
        do {
            let inserted = try await MetricsFanOut([metrics, tally]).measuringInTime(
                .insertion, clock: clock, generation: mine
            ) {
                try await withStageTimeout(StageTimeout.insertion, clock: clock) {
                    if delivery == .copy {
                        return try await inserter.insert(text)
                    }
                    return try await inserter.insert(text, targeting: destination)
                }
            }
            // A cancel during the write already ended the dictation, so nothing more is shown or learnt.
            guard !wasCancelled(mine) else { return nil }
            // Either way the dictation has to end, so the next one can begin.
            guard let attempt = inserted else {
                throw delivery == .copy
                    ? TextInsertionError.clipboardUnavailable
                    : TextInsertionError.insertionTimedOut
            }
            // A field found secure at the write counts from here on, before anything is learnt from it.
            if attempt.intoSecureField { destinationIsSecure = true }
            let slowCause = await timeWait(recorded: tally)
            await settleRecording(wordsLost: MissedSpeech.isMissing(missedPieces))
            transition(
                to: .inserted(
                    DictationOutcome(
                        text: text, method: attempt.method, cleanedBy: cleanedBy,
                        insertedInto: landedIn(attempt)?.applicationName ?? insertedInto,
                        insertedIntoIdentifier: landedIn(attempt)?.bundleIdentifier
                            ?? insertedIntoIdentifier,
                        spokenFor: spokenFor, changes: changes,
                        fromRecording: delivery == .copy, arrival: attempt.arrival,
                        intoSecureField: destinationIsSecure, missedPieces: missedPieces,
                        unavailableEngines: unavailableEngines, doubtful: doubtful,
                        slowCause: slowCause)))
            return attempt
        } catch {
            guard !wasCancelled(mine) else { return nil }
            // The words survive the failure: the interface can still offer them.
            await fail(DictationFailure(error, transcript: text))
            return nil
        }
    }

    /// Times the wait since key-up, names its cause against the last dictations, and records both.
    private func timeWait(recorded tally: StageTally) async -> SlowDictationCause? {
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

    /// Runs a command-key utterance on the selection as it stands now; the words are never typed.
    private func runCommand(
        _ transcription: Transcription, seeing appContext: AppContext?, generation mine: Int
    ) async {
        let target = await insertionContextForWrite(matching: appContext)
        guard !wasCancelled(mine) else { return }
        // Dictionary spellings apply to command words as to dictation, so "with Y" writes a term as the user filed it.
        let proposals = (try? await runningCorrector.corrections(for: transcription, seeing: target)) ?? []
        let corrected = DictationCorrection.applying(proposals, to: transcription.text).text
        // The words a replace writes are dictation, so they are tidied as a phrase; the command words are not.
        let heard = await ReplaceCommand.tidyingReplacement(in: corrected) { words in
            LatinScript.enforced(await tidiedPhrase(Transcription(text: words), seeing: target) ?? words)
        }
        guard !wasCancelled(mine) else { return }
        do {
            let outcome = try await commands.run(heard, on: target)
            guard !wasCancelled(mine) else { return }
            guard case .ran(let said) = outcome else { return await fail(.commandNotUnderstood(heard)) }
            await settleRecording(wordsLost: false)
            transition(to: .executed(said))
        } catch {
            guard !wasCancelled(mine) else { return }
            await fail(DictationFailure(error, transcript: heard))
        }
    }

    /// Where the words actually went, which is the insertion's to say; the recording's read is the fallback.
    private func landedIn(_ attempt: InsertionAttempt) -> InsertionDestination? {
        guard let destination = attempt.destination, destination.isKnown else { return nil }
        return destination
    }

    /// Ends the dictation in failure, keeping the audio exactly when the words were lost. See `Docs/recordings.md`.
    private func fail(_ failure: DictationFailure) async {
        var failure = failure.markingSecure(destinationIsSecure)
        let wordsLost = failure.transcript == nil && failure.severity != .informational
        let recording = openRecording
        let kept = await settleRecording(wordsLost: wordsLost)
        if kept, let recording, failure.recovery == nil || failure.recovery == .retry {
            failure = failure.offeringRetry(of: recording)
        }
        transition(to: .failed(failure))
    }

    /// Keeps the open recording exactly when words were lost and the field is not secure, else deletes it.
    @discardableResult
    private func settleRecording(wordsLost: Bool) async -> Bool {
        if screenReads.cost.reads > 0 {
            await metrics.recordScreenReads(screenReads.cost)
            await metrics.recordScreenText(screenReads.lastUnavailable)
        }
        screenReads = DictationScreenReads()
        guard let openRecording else { return false }
        self.openRecording = nil
        // A secure field's audio is not kept for a retry, since its words are a secret.
        guard wordsLost, !destinationIsSecure else {
            await recordings.discard(openRecording)
            return false
        }
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

    /// Tells the stores what this dictation used, once the words are safely on screen.
    private func count(_ changes: AppliedChanges, writtenIn text: String) async {
        // Once per entry and in one batch: the store counts dictations an entry appeared in, not words, by any path.
        var counted: Set<UUID> = []
        let entries = (changes.corrections.map(\.entryID) + changes.entriesTaken)
            .filter { counted.insert($0).inserted }
        if !entries.isEmpty || !text.isEmpty {
            try? await learner.recordUse(ofEntries: entries, writtenIn: text)
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

    /// Adds a finished piece to what the panel shows, unless the field hides what is typed.
    private func showFinished(_ piece: Piece) {
        let words = TextTidy.collapseWhitespace(piece.cleaned.text)
        guard !destinationIsSecure, !words.isEmpty else { return }
        show(heard: heardSoFar.map { "\($0) \(words)" } ?? words)
    }

    private func show(heard words: String?) {
        guard words != heardSoFar else { return }
        heardSoFar = words
        heardObservers.send(words)
    }

    private func transition(to next: DictationState) {
        state = next
        observers.send(next, generation: generation)
    }
}

/// Bounds how long a new dictation waits for a previous insertion to reach the caret.
private enum PendingInsertionConfirmation {
    static let budget = Duration.milliseconds(1600)
    static let interval = Duration.milliseconds(40)

    static func collapsed(_ text: String) -> String {
        TextTidy.collapseWhitespace(text)
    }
}
