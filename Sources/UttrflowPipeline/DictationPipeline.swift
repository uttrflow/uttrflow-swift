public import UttrflowCore
private import struct Foundation.UUID

/// Speak, and the words appear where you were typing.
///
/// The whole product, expressed once, over protocols only — so every rule below is
/// tested without a microphone, a model or another app on screen.
///
/// Two rules outrank the others and shape the code:
///
/// - **The user's words are never lost.** If tidying fails, what they actually said is
///   inserted instead. If insertion fails, the transcript comes back with the failure
///   so the interface can offer it. Only a failure before there are any words can end
///   with nothing to show.
/// - **Cancelling leaves no trace.** Nothing is transcribed, nothing is inserted, and
///   the audio is discarded.
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
    private let clock: any Clock<Duration>
    private let profile: UserProfile

    private var state: DictationState = .idle
    private let observers = StateObservers()

    /// Counts dictations, so a cancel can name the one it abandoned. A plain flag would
    /// be cleared by the next dictation starting and let a stale stage through.
    private var generation = 0
    private var cancelledGeneration: Int?

    /// Whether a start is in flight but has not opened the microphone yet.
    ///
    /// ``startRecording()`` has to await the capture engine, and the state was only set
    /// afterwards — so two presses arriving together both passed the guard. The second
    /// `start()` threw `alreadyRecording`, the pipeline settled in `failed`, and `failed`
    /// is not busy, so ``finishRecording()``'s `guard state == .recording` never ran
    /// again while the microphone genuinely was live. Claiming the turn before the await
    /// is what closes that window; an actor only lets another caller in at a suspension,
    /// and by then this flag is already set.
    private var isStarting = false

    /// Reads how long the microphone has been open.
    ///
    /// A closure rather than a stored instant because the clock is existential and an
    /// `any Clock<Duration>` cannot hand out an `Instant` that survives across calls.
    /// Opening it once, when recording starts, keeps the injected clock authoritative —
    /// so a test with a `ManualClock` gets a spoken duration it decides, not a real one.
    private var stopwatch: (() -> Duration)?
    private var spokenFor: Duration?

    /// The application named by the context read during tidying.
    ///
    /// Kept from that one read rather than asked again at insertion time: the interface
    /// wants to label the dictation with where it went, and by then the user has often
    /// switched away, so a second read would confidently name the wrong app.
    private var insertedInto: String?
    private var insertedIntoIdentifier: String?

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
        self.clock = clock
        self.profile = profile
    }

    public var currentState: DictationState { state }

    /// Every state the pipeline passes through, from now on.
    public func states() -> AsyncStream<DictationState> {
        observers.makeStream(startingWith: state)
    }

    /// Loads the speech model so the first dictation is not the slow one.
    ///
    /// Non-throwing, so that launch code does not have to decide what to do about a
    /// recogniser that will not start — but the failure is no longer dropped. It becomes
    /// the pipeline's state, which is how the menu bar learns to say what is wrong
    /// instead of saying Ready and letting the user find out one wasted dictation later.
    public func prepare() async {
        guard !isBusy else { return }
        do {
            try await speech.prepare()
            // A retry that works clears the notice the failed attempt left behind.
            if case .failed = state { transition(to: .idle) }
        } catch {
            transition(to: .failed(DictationFailure(error)))
        }
    }

    /// Opens the existential clock so an instant can be held on to.
    ///
    /// Generic on purpose: `some Clock` is what lets Swift open `any Clock<Duration>` at
    /// the call site, which is the whole reason this is a function and not two lines.
    private static func stopwatch(from clock: some Clock<Duration>) -> () -> Duration {
        let start = clock.now
        return { start.duration(to: clock.now) }
    }

    // MARK: The sequence

    /// Whether a new dictation can begin.
    ///
    /// Wider than ``DictationState/isBusy`` alone, which cannot see a start that has
    /// claimed the turn but not yet opened the microphone.
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
                // Cancelled while the microphone was still opening. Close it again
                // rather than settling into `recording` for a dictation the user has
                // already abandoned, which would leave the microphone live with nothing
                // watching it.
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

        // The run this call belongs to, carried through every stage below. Reading
        // `generation` again inside those stages is what let a new dictation revive an
        // abandoned one.
        let mine = generation

        let audio: AudioSamples
        do {
            // Measured as the capture stage because this is the part Uttrflow costs the
            // user: draining the buffer and converting it. The wait before it is the
            // user talking, which is measured separately and never called latency.
            audio = try await metrics.measuring(.capture, clock: clock) {
                try await capture.stop()
            }
            spokenFor = stopwatch?()
            stopwatch = nil
        } catch {
            transition(to: .failed(DictationFailure(error)))
            return
        }

        await process(audio, mine)
    }

    /// Abandons the dictation. Nothing is transcribed and nothing is inserted.
    ///
    /// Cancelling after the recording has stopped is honoured too: the stages check
    /// this before moving on, so a cancel arriving during transcription discards the
    /// result rather than inserting it. Without that, "cancelling leaves no trace" was
    /// true only while the microphone was still open.
    public func cancel() async {
        cancelledGeneration = generation
        await capture.cancel()
        transition(to: .idle)
    }

    /// Whether the dictation that started at `mine` has since been abandoned.
    ///
    /// Takes the generation it is asking about rather than reading the pipeline's current
    /// one. `startRecording` increments `generation`, so a run suspended in a stage — a
    /// transcription that takes a second or two — used to be compared against a number
    /// that had moved on the moment the user began their next dictation. Its cancel
    /// stopped matching, every later guard passed, and the abandoned text was inserted
    /// into whatever the user had since focused, while the new recording was left with no
    /// one watching it.
    ///
    /// `<=` rather than `==`: a cancel at any generation up to and including this one
    /// abandons this run. Later cancels belong to later runs.
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

    private func process(_ audio: AudioSamples, _ mine: Int) async {
        transition(to: .transcribing)
        let transcription: Transcription
        do {
            transcription = try await metrics.measuring(.transcription, clock: clock) {
                try await speech.transcribe(audio, options: .automatic)
            }
        } catch {
            transition(to: .failed(DictationFailure(error)))
            return
        }

        guard !wasCancelled(mine) else { return }

        // Silence is not a fault, but it must not be silent either. Returning quietly to
        // idle is indistinguishable from the app being broken — the user holds the key,
        // speaks, lets go, and nothing whatever happens, with no way to tell a microphone
        // that heard nothing from a dictation that fell down a hole. It is reported as an
        // informational notice, which the interface draws softly and dismisses itself.
        guard !transcription.isBlank else {
            transition(to: .failed(DictationFailure(SpeechEngineError.nothingHeard)))
            return
        }

        transition(to: .tidying)

        // Read once, here, and handed to everything that needs it. The dictionary wants
        // it to judge a word against what is on screen and the tidier wants it to know
        // what the sentence is for; asking twice would pay for the same Accessibility
        // round trip twice and could describe two different screens if the user
        // switched app in between.
        let appContext = await context.currentContext()
        // Kept from this one read rather than asked again at insertion time: the
        // interface wants to label the dictation with where it went, and by then the
        // user has often switched away, so a second read would name the wrong app.
        insertedInto = appContext.applicationName
        insertedIntoIdentifier = appContext.bundleIdentifier

        // The dictionary before the tidier, because a correction is argued from the
        // sentence as it was *heard*. Word ranges into what the recogniser said stop
        // meaning anything the moment the tidier drops a filler, and the evidence the
        // engine weighs — this word said clearly elsewhere in the same breath — is
        // evidence about the utterance, not about the prose it is about to become.
        let corrected = await correct(transcription, seeing: appContext)
        guard !wasCancelled(mine) else { return }

        let cleaned = await tidy(transcription, saying: corrected.text, seeing: appContext)
        guard !wasCancelled(mine) else { return }

        // Tidying can reduce an utterance to nothing: "um" is entirely filler, and the
        // rule-based transformer strips it. That is the same "nothing to do" as a blank
        // transcript, and inserting it would be worse than useless — the Accessibility
        // route writes to the selected text, so an empty string DELETES whatever the
        // user had selected, and the interface would then report it as a dictation that
        // worked. Someone who selects a paragraph to replace, hesitates, and says "um"
        // must get their paragraph back, not a success message over an empty document.
        guard !cleaned.text.isBlank else {
            transition(to: .failed(DictationFailure(SpeechEngineError.nothingHeard)))
            return
        }

        // Snippets after the tidier and not before it. The matcher is built to tolerate
        // the punctuation the tidier adds — a comma inside a trigger is a speaker
        // pausing mid-phrase — and it refuses a trigger assembled across a full stop.
        // Run first, it would be matching against a transcript with no sentence
        // boundaries in it at all, and could not tell "Please sign. Off we go" from
        // somebody saying "sign off".
        let expanded = await expand(cleaned.text)
        guard !wasCancelled(mine) else { return }

        let changes = AppliedChanges(
            corrections: corrected.corrections, snippets: expanded.snippets,
            // `transcription.text`, not `expanded.text`: this is the one sentence in the
            // whole run that nothing has rewritten yet, and it is the space the
            // corrections' word ranges are positions within.
            spokenWords: transcription.text.split(whereSeparator: \.isWhitespace).count)
        guard await insert(expanded.text, cleanedBy: cleaned.producedBy, changes: changes) else {
            return
        }

        // Both of these run after the words are on screen, and neither can fail the
        // dictation. The first counts what this dictation used; the second asks what it
        // showed. §19.
        await count(changes)
        await learnWords(heard: transcription.text, wrote: expanded.text, seeing: appContext)
    }

    /// Puts the user's own spellings in, and leaves the transcript alone if it cannot.
    ///
    /// A dictionary that will not answer costs a correction, never a dictation, so the
    /// failure is swallowed here in exactly the way tidying's is. §19.
    ///
    /// Timed even on the answer it almost always gives — nothing to change. A dictation
    /// pays for the consultation whether or not a word comes back from it, and a stage
    /// measured only when it did something would make the ordinary dictation, which is
    /// the one worth knowing about, look free.
    private func correct(
        _ transcription: Transcription, seeing appContext: AppContext
    ) async -> CorrectedTranscript {
        do {
            return try await metrics.measuring(.correction, clock: clock) {
                let proposed = try await corrector.corrections(
                    for: transcription, seeing: appContext)
                // The commonest answer by a wide margin, and worth its own exit: a
                // transcript nothing wanted to change must not be rebuilt character by
                // character to arrive at itself.
                guard !proposed.isEmpty else {
                    return CorrectedTranscript.unchanged(transcription.text)
                }
                return DictationCorrection.applying(proposed, to: transcription.text)
            }
        } catch {
            return .unchanged(transcription.text)
        }
    }

    /// Tidies the transcript, falling back to exactly what was said.
    ///
    /// Tidying is the only optional stage. Losing it costs quality; treating its
    /// failure as the dictation's failure would cost the user their words.
    ///
    /// - Parameters:
    ///   - transcription: What the recogniser produced, for its language and its length.
    ///   - text: The words to tidy, which the dictionary may already have changed.
    ///   - appContext: What the user is looking at, read once for this dictation.
    /// - Returns: The tidied text, or exactly what was said when tidying would not run.
    private func tidy(
        _ transcription: Transcription, saying text: String, seeing appContext: AppContext
    ) async -> TransformationResult {
        let request = TransformationRequest(
            transcription: transcription.saying(text), context: appContext, profile: profile)

        do {
            return try await metrics.measuring(.transformation, clock: clock) {
                try await cleaner.clean(request)
            }
        } catch {
            return TransformationResult(text: text, producedBy: .rules)
        }
    }

    /// Expands the user's snippets, and leaves the text alone if it cannot.
    ///
    /// Blank is treated as a failure rather than as an expansion, and that is not
    /// pedantry: the Accessibility route writes to the *selected* text, so inserting an
    /// empty string deletes whatever the user had highlighted. A hand-edited snippets
    /// file is the one way this stage can produce one, and it must cost the snippet
    /// rather than the paragraph the user selected to replace.
    ///
    /// Timed for the same reason correction is: a snippet file no trigger matched was
    /// still read, and the dictation waited for it.
    ///
    /// The blank answer is measured as a success, because the stage did run and did
    /// produce text — it is the pipeline, not the store, that then declines to use it.
    /// Only a store that could not answer at all is a failure of this stage, and that is
    /// what the reliability figures are counting.
    private func expand(_ text: String) async -> ExpandedTranscript {
        do {
            return try await metrics.measuring(.expansion, clock: clock) {
                let expanded = try await snippets.expand(text)
                guard !expanded.text.isBlank else { return ExpandedTranscript.unchanged(text) }
                return expanded
            }
        } catch {
            return .unchanged(text)
        }
    }

    /// Puts the finished text where the user was typing.
    ///
    /// - Returns: Whether the words reached the screen. Everything the dictation is
    ///   allowed to remember hangs on that answer, and reading it from the state
    ///   afterwards would be inferring what this method already knows.
    private func insert(
        _ text: String, cleanedBy: TransformerKind, changes: AppliedChanges
    ) async -> Bool {
        do {
            let method = try await metrics.measuring(.insertion, clock: clock) {
                try await inserter.insert(text)
            }
            transition(
                to: .inserted(
                    DictationOutcome(
                        text: text, method: method, cleanedBy: cleanedBy,
                        insertedInto: insertedInto,
                        insertedIntoIdentifier: insertedIntoIdentifier,
                        spokenFor: spokenFor, changes: changes)))
            return true
        } catch {
            // The words survive the failure: the interface can still offer them.
            transition(to: .failed(DictationFailure(error, transcript: text)))
            return false
        }
    }

    /// Tells the stores what this dictation used, once the words are safely on screen.
    ///
    /// After the transition and not before it, in both senses. A word earns its place
    /// by *surviving* a dictation, so nothing may be learnt from one that never landed
    /// — and the user has their text before any of this is attempted, so a slow disk
    /// cannot show up as a slow dictation.
    ///
    /// Skipped outright when there is nothing to count, which is every dictation by a
    /// user with no dictionary and no snippets. That guard is why the feature costs
    /// them nothing rather than costing them an actor hop and a write per dictation.
    ///
    /// A store that refuses is dropped silently. There is nothing for the user to do
    /// about it and nothing left at risk: this runs after ``DictationState/inserted``
    /// has already been announced, so reporting a failure here would replace a
    /// dictation that worked with a notice about bookkeeping that did not.
    private func count(_ changes: AppliedChanges) async {
        guard !changes.isEmpty else { return }

        // Once per entry, however many words it corrected: the dictionary counts the
        // dictations an entry was applied to, and a sentence that said the same
        // mis-heard name twice is still one dictation.
        var counted: Set<UUID> = []
        for correction in changes.corrections where counted.insert(correction.entryID).inserted {
            // Each one on its own, so a store that refuses the first still counts the
            // second. `try?` and not a catch: there is nothing to do with the error,
            // and nothing left at risk.
            try? await learner.recordUse(ofEntry: correction.entryID)
        }

        guard !changes.snippets.isEmpty else { return }
        // In one batch, and with the duplicates left in, because the store counts
        // firings rather than dictations and says so.
        try? await learner.recordUse(ofSnippets: changes.snippets.map(\.snippetID))
    }

    /// Offers the dictionary what this dictation showed, once its words have landed.
    ///
    /// Which of it is worth keeping is entirely the dictionary's decision. What is
    /// decided here is *when* — after the same transition the counters wait for, because
    /// a word earns its place by surviving a dictation and a dictation that never
    /// reached the screen showed nobody anything.
    ///
    /// Skipped when macOS told us nothing about what was on screen, which is the whole
    /// of the raw material: with no window title and no selection there is nothing to
    /// have noticed and nothing to have corrected, so the seam is not worth crossing.
    /// The check is ``AppContext/isEmpty`` rather than a list of the fields the
    /// dictionary happens to read, so this cannot go stale when that changes.
    ///
    /// A store that refuses is dropped silently, for the reason the counters are: the
    /// user already has their text, and there is nothing for them to do about it.
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
    /// Nothing but whitespace — the same emptiness ``Transcription/isBlank`` means, said
    /// of a string that is no longer wrapped in one.
    fileprivate var isBlank: Bool { allSatisfy(\.isWhitespace) }
}

extension Transcription {
    /// The same recognised speech, with different words in it.
    ///
    /// The tidier is given a whole ``Transcription`` because it routes on the language
    /// and reads the length, and both of those are still true of a transcript the
    /// dictionary has corrected. The segments come across untouched: they say when each
    /// span was spoken, which no correction changes, and re-cutting them around a
    /// replacement would be inventing timings nothing asked for.
    fileprivate func saying(_ text: String) -> Transcription {
        guard text != self.text else { return self }
        return Transcription(
            text: text, detectedLanguage: detectedLanguage, segments: segments,
            audioDuration: audioDuration)
    }
}
