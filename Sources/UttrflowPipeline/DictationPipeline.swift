// The whole product in one actor: from the key going down to the text landing.
import UttrflowAI
public import UttrflowCore
import struct Foundation.UUID

/// Speak, and the words appear where you were typing. See `Docs/pipeline.md`.
public actor DictationPipeline {
    let capture: any AudioCaptureEngine
    let speech: any SpeechEngine
    /// The engine a retry asked for in place of `speech`, for that one retry only.
    var retrySpeech: (any SpeechEngine)?
    /// A `var` so a clean-up step switched off takes effect on the next dictation rather than the next launch.
    private var cleaner: any TranscriptCleaning
    let context: any ContextEngine
    /// The dictation's words, ranked against its initial screen; a closure so speech stays out of here.
    let speechWords: @Sendable (AppContext) async -> [String]
    let inserter: any TextInserting
    let corrector: any WordCorrecting
    let snippets: any SnippetExpanding
    let learner: any DictationLearning
    let consent: any LearningConsent
    let vocabulary: any VocabularyLearning
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
    var dictationContext: DictationContext?
    private var nextFormat: AdapterMode?
    let recordings: any RecordingKeeper
    /// Where a retried dictation's words go, since the field they were meant for is gone.
    let clipboard: any TextInserting
    let clock: any Clock<Duration>
    private var profile: UserProfile
    /// How a recording is cut into pieces the recogniser and tidier take one at a time.
    private let windowing: SpeechWindowing
    /// How often the recording is looked at for a piece to work on while the key is held.
    let earlyPoll: Duration
    /// Paces that look on its own clock, so a test driving the stage clock wakes only stages.
    let pollClock: any Clock<Duration>

    var state: DictationState = .idle
    nonisolated let observers = RevisionedStateObservers()
    /// The finished pieces' words while the key is held, shown in the panel and never typed into the field.
    private var heardSoFar: String?
    private let heardObservers = StateObservers<String?>()

    /// Counts dictations, so a cancel can name the one it abandoned.
    var generation = 0
    private var cancelledGeneration: Int?

    /// Held across every await before the state shows a dictation's next step, so no second entry slips in.
    var hasTurn = false

    /// How long `prepare()` waits for the speech model before calling the load failed.
    private let speechLoadLimit: Duration
    /// How many loads are running, since a switch can begin one before the last has ended.
    private var loadsUnderWay = 0

    /// Reads how long the microphone has been open, closing over the injected clock.
    var stopwatch: (() -> Duration)?
    var spokenFor: Duration?
    /// Reads how long ago the key came up, so the wait it costs the user is timed; `nil` for a retry.
    var sinceRelease: (() -> Duration)?
    /// The screen-read time spent before key-up, which the wait after it does not include.
    var readsBeforeRelease: Duration = .zero
    /// The last dictations' waits, which name the cause of each slow one.
    var waits = DictationWaits()

    /// The application named by the context read during tidying, before the user moved on.
    var insertedInto: String?
    var insertedIntoIdentifier: String?
    /// Whether the screen read found a field that hides what is typed, so nothing of this dictation is kept.
    var destinationIsSecure = false

    /// The kept audio of the dictation under way, deleted or left for a retry as it ends.
    var openRecording: UUID?
    /// A cancelled recording offered for Restore, and the wait that deletes it when the window closes.
    var restorable: (id: UUID, expiry: Task<Void, Never>)?

    /// A recording cancelled at least this long is said to be discarded and kept for Restore. See Docs/recordings.md.
    public static let restoreThreshold: Duration = .seconds(5)
    /// How long a cancelled recording can be restored before it is deleted.
    public static let restoreWindow: Duration = .seconds(60)
    /// Destination facts read for audio kept for a retry.
    var recordingDestination: AppContext?
    /// The formatter destination read for that recording, retained even if app rules later change.
    var recordingFieldKind: Destination?

    /// What the early loop holds while the key is down, handed to the release pass in one step.
    var early = EarlyWork()
    /// What reading the screen has cost the dictation under way, and its latest reading.
    var screenReads = DictationScreenReads()
    /// How many early screen reads have come back and been kept or dropped, so a test can wait for the last one.
    var earlyReadsSettled: Int { early.readsSettled }
    /// Ranked once per dictation, against the screen it began on, and given to every piece.
    var dictationWords: [String]?
    /// Pieces of this dictation that held speech and decoded to no words twice, left out of what is inserted.
    var missedPieces = 0
    /// Whether the recording clipped past the point where accuracy falls.
    var inputTooLoud = false

    /// The settings and screen resolved at the start of a dictation and shared by every piece.
    struct DictationContext: Sendable {
        let app: AppContext
        let situation: Situation
        var listening: ListeningLanguages
        let vocabulary: [String]
        let profile: UserProfile
        let corrector: any WordCorrecting
    }

    /// What the clean-up steps did to each piece of the dictation under way, reported as one when it ends.
    var cleaningRecords: [KeptRecord] = []
    /// Early spans the release join dropped, whose records are not part of the dictation's account.
    var droppedSpans: Set<UUID> = []
    /// The early span the running task tidies, so its record can be withdrawn if the span is dropped.
    @TaskLocal static var tidiedSpan: UUID?

    /// One piece's cleaning record and the early span it came from, if any.
    struct KeptRecord {
        let span: UUID?
        let record: CleaningRecord
    }
    /// Runs what is said while the command key is held, in place of inserting it.
    let commands: EditCommandRegistry
    /// Where the next recording goes, set by the key that opens it and spent when it opens.
    var nextRoute: UtteranceRoute = .dictation
    /// Where the recording under way goes.
    var recordingRoute: UtteranceRoute = .dictation

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

    /// Sends the next dictation, and only that one, out as typed (`prose`) or as formatted (`auto`); nil takes the choice back.
    func format(next mode: AdapterMode?) {
        nextFormat = mode
    }

    /// The choice waiting for the next dictation, or nil when none is, for the panel to show.
    var pendingFormat: AdapterMode? { nextFormat }

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

    /// Fixes all three for the dictation about to begin, spending the one-shot format choice when it is a new recording.
    func takeSettings(spendingFormat: Bool = true) {
        let held = spendingFormat ? nextFormat : nil
        if spendingFormat { nextFormat = nil }
        inUse = (cleaner, destinationOverrides.holding(oneShot: held), profile)
    }

    public var currentState: DictationState { state }

    /// Whether the recogniser has loaded and the next dictation will not wait for it.
    public internal(set) var isReady = false
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
    var isBusy: Bool { hasTurn || state.isBusy || early.decodesInFlight > 0 }

    /// Clears what one attempt learnt about its words, so the next asks afresh.
    func forgetTheLastAttempt() {
        dictationWords = nil
        dictationContext = nil
        missedPieces = 0
        inputTooLoud = false
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
    func wasCancelled(_ mine: Int) -> Bool {
        guard let cancelledGeneration else { return false }
        return mine <= cancelledGeneration
    }

    /// Returns to rest after the interface has shown the result.
    public func acknowledge() {
        guard !isBusy else { return }
        transition(to: .idle)
    }

    /// The situation and languages a piece is tidied in: the dictation's own, or what this screen implies.
    func tidyingFrame(seeing appContext: AppContext) -> (situation: Situation, profile: UserProfile) {
        (
            dictationContext?.situation
                ?? SituationResolver.resolve(from: appContext, overrides: runningOverrides),
            dictationContext?.profile ?? runningProfile
        )
    }

    /// Everything the pieces and the whole message account for so far, whether or not a page is told.
    func cleaningAccount(including whole: CleaningRecord?) -> CleaningRecord {
        CleaningRecord.merging(cleaningRecords.map(\.record) + [whole].compactMap(\.self))
    }

    /// Hands the dictation's account to its page when anything was tidied or skipped; never a secure field.
    func reportCleaning(for delivery: Delivery) async {
        if !cleaningRecords.isEmpty, !destinationIsSecure, delivery != .command {
            var record = CleaningRecord.merging(cleaningRecords.map(\.record))
            record.dictionaryRevision = dictationContext?.corrector.revision
            await cleaningRecorder.record(record)
        }
    }

    /// Stops a span the release join re-decodes, and takes its record out of the dictation's account.
    func withdraw(_ span: Span) async {
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

    // MARK: Stages

    /// Where the finished words go.
    enum Delivery {
        case insert
        case copy
        /// Run by the edit commands against the selection; never inserted.
        case command
    }

    /// What the recogniser made of one window.
    enum Heard: Sendable {
        case words(Transcription)
        case nothing
        case missed
    }

    /// Ends the dictation in failure, keeping the audio exactly when the words were lost. See `Docs/recordings.md`.
    func fail(_ failure: DictationFailure) async {
        var failure = failure.markingSecure(destinationIsSecure)
        let wordsLost = failure.transcript == nil && failure.severity != .informational
        let recording = openRecording
        let kept = await settleRecording(wordsLost: wordsLost)
        if kept, let recording, failure.recovery == nil || failure.recovery == .retry {
            failure = failure.offeringRetry(of: recording)
        }
        transition(to: .failed(failure))
    }

    /// Keeps the open recording when words were lost, or when they landed and a fix may retry it, unless the field is secure.
    @discardableResult
    func settleRecording(wordsLost: Bool, keepingFinished: Bool = false) async -> Bool {
        if screenReads.cost.reads > 0 {
            await metrics.recordScreenReads(screenReads.cost)
            await metrics.recordScreenText(screenReads.lastUnavailable)
        }
        screenReads = DictationScreenReads()
        guard let openRecording else { return false }
        self.openRecording = nil
        // A secure field's audio is not kept for a retry, since its words are a secret.
        guard wordsLost || keepingFinished, !destinationIsSecure else {
            await recordings.discard(openRecording)
            return false
        }
        return true
    }

    /// Adds a finished piece to what the panel shows, unless the field hides what is typed.
    func showFinished(_ piece: Piece) {
        let words = TextTidy.collapseWhitespace(piece.cleaned.text)
        guard !destinationIsSecure, !words.isEmpty else { return }
        show(heard: heardSoFar.map { "\($0) \(words)" } ?? words)
    }

    func show(heard words: String?) {
        guard words != heardSoFar else { return }
        heardSoFar = words
        heardObservers.send(words)
    }

    func transition(to next: DictationState) {
        state = next
        observers.send(next, generation: generation)
    }
}
