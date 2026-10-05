// Tests transcription that starts while the key is still held.
import Foundation
import Synchronization
import Testing

@testable import UttrflowCore
@testable import UttrflowPipeline
@testable import UttrflowTestSupport

// MARK: - Doubles

/// A recogniser that names each call in order and can be told to hear nothing on some.
private actor NumberingSpeechEngine: SpeechEngine {
    let kind = SpeechEngineKind.whisperKit
    private(set) var sampleCounts: [Int] = []
    private(set) var biases: [[String]] = []
    private var silentCalls: Set<Int>
    private var blankCalls: Set<Int>
    private var failingCalls: Set<Int>

    init(silentCalls: Set<Int> = [], blankCalls: Set<Int> = [], failingCalls: Set<Int> = []) {
        self.silentCalls = silentCalls
        self.blankCalls = blankCalls
        self.failingCalls = failingCalls
    }

    func prepare() async throws(SpeechEngineError) {}

    func transcribe(
        _ audio: AudioSamples, options: TranscriptionOptions
    ) async throws(SpeechEngineError) -> Transcription {
        sampleCounts.append(audio.samples.count)
        biases.append(options.vocabulary)
        let call = sampleCounts.count
        if silentCalls.contains(call) { throw .nothingHeard }
        if failingCalls.contains(call) { throw .transcriptionFailed(description: "call \(call)") }
        return Transcription(
            text: blankCalls.contains(call) ? "" : "w\(call) x",
            detectedLanguage: DetectedLanguage(code: .english, confidence: 1),
            audioDuration: audio.duration)
    }

    var calls: Int { sampleCounts.count }
}

/// A recogniser that gives every pause-delimited piece the same doubtful word.
private actor RepeatedWordSpeechEngine: SpeechEngine {
    let kind = SpeechEngineKind.whisperKit

    func prepare() async throws(SpeechEngineError) {}

    func transcribe(
        _ audio: AudioSamples, options: TranscriptionOptions
    ) async throws(SpeechEngineError) -> Transcription {
        Transcription(
            text: "Maddox", detectedLanguage: DetectedLanguage(code: .english, confidence: 1),
            audioDuration: audio.duration)
    }
}

/// A recogniser that keeps every sample it is given, so a test can check none were lost or repeated.
private actor KeepingSpeechEngine: SpeechEngine {
    let kind = SpeechEngineKind.whisperKit
    private(set) var pieces: [[Float]] = []

    func prepare() async throws(SpeechEngineError) {}

    func transcribe(
        _ audio: AudioSamples, options: TranscriptionOptions
    ) async throws(SpeechEngineError) -> Transcription {
        pieces.append(audio.samples)
        return Transcription(
            text: "w\(pieces.count) x", detectedLanguage: DetectedLanguage(code: .english, confidence: 1),
            audioDuration: audio.duration)
    }
}

/// A recogniser whose first recognition does not finish until the test lets it, so the key can come up mid-recognition.
private actor HeldSpeechEngine: SpeechEngine {
    let kind = SpeechEngineKind.whisperKit
    private(set) var calls = 0
    private var held: CheckedContinuation<Void, Never>?
    private var released = false

    func prepare() async throws(SpeechEngineError) {}

    func transcribe(
        _ audio: AudioSamples, options: TranscriptionOptions
    ) async throws(SpeechEngineError) -> Transcription {
        calls += 1
        if calls == 1, !released { await withCheckedContinuation { held = $0 } }
        return Transcription(
            text: "w\(calls) x", detectedLanguage: DetectedLanguage(code: .english, confidence: 1),
            audioDuration: audio.duration)
    }

    /// Lets the first recognition finish, whether or not it has begun waiting yet.
    func release() {
        released = true
        held?.resume()
        held = nil
    }

    var isHolding: Bool { held != nil }
}

/// A tidier whose first tidy does not finish until the test lets it, so the key can come up mid-tidy.
private actor HeldCleaner: TranscriptCleaning {
    private var calls = 0
    private var held: CheckedContinuation<Void, Never>?
    private var released = false

    func clean(_ request: TransformationRequest) async throws(TransformationError) -> TransformationResult {
        calls += 1
        if calls == 1, !released { await withCheckedContinuation { held = $0 } }
        return TransformationResult(text: request.transcription.text, producedBy: .foundationModels)
    }

    nonisolated func warm(for situation: Situation?) async {}

    /// Lets the first tidy finish, whether or not it has begun waiting yet.
    func release() {
        released = true
        held?.resume()
        held = nil
    }

    var isHolding: Bool { held != nil }
}

/// A tidier that shouts, so its work on each piece can be seen, and remembers where it was warmed for.
private final class ShoutingCleaner: TranscriptCleaning, Sendable {
    private let state = Mutex((warmed: [Destination?](), seen: [String](), contexts: [AppContext]()))
    private let failOn: String?

    init(failOn: String? = nil) {
        self.failOn = failOn
    }

    func clean(_ request: TransformationRequest) async throws(TransformationError) -> TransformationResult {
        let text = request.transcription.text
        state.withLock {
            $0.seen.append(text)
            $0.contexts.append(request.context)
        }
        if let failOn, text.contains(failOn) { throw .outputRejected(reason: "scripted", kind: .lostWord) }
        return TransformationResult(text: text.uppercased(), producedBy: .foundationModels)
    }

    func warm(for situation: Situation?) async {
        state.withLock { $0.warmed.append(situation?.destination) }
    }

    var warmed: [Destination?] { state.withLock(\.warmed) }
    var seen: [String] { state.withLock(\.seen) }
    var contexts: [AppContext] { state.withLock(\.contexts) }
}

/// Whether a recognition ran beside a tidy, forced by each side waiting for the other rather than hoped for.
private final class StageRendezvous: Sendable {
    private struct State {
        var recognitionsInFlight = 0
        var recognitions = 0
        var besides = 0
        /// Set once the test gives up, so every wait ends rather than only the one that noticed.
        var gaveUp = false
    }

    private let state = Mutex(State())

    /// How many recognitions ran in all, which says the pipeline did the work rather than skipped it.
    var recognitions: Int { state.withLock(\.recognitions) }

    /// How many tidies had a recognition beside them, which is the property #186 asks for.
    var tidiesBesideARecognition: Int { state.withLock(\.besides) }

    /// Holds a recognition open until a tidy has noticed it, so a late-scheduled tidy is waited for.
    func recognition<T: Sendable>(waitsForATidy waits: Bool, doing work: () async -> T) async -> T {
        let noticed = state.withLock { state -> Int in
            state.recognitionsInFlight += 1
            state.recognitions += 1
            return state.besides
        }
        // Waits to be noticed rather than for a tidy to be in flight, which a prompt tidy is only briefly.
        if waits { await until { $0.besides > noticed } }
        let answer = await work()
        state.withLock { $0.recognitionsInFlight -= 1 }
        return answer
    }

    /// Holds a tidy open until a recognition is running beside it, which a serial pass can never provide.
    func tidy(waitsForARecognition waits: Bool) async {
        guard waits else { return }
        if await until({ $0.recognitionsInFlight > 0 }) {
            state.withLock { $0.besides += 1 }
        }
    }

    /// Ends every wait, which the test does when its time limit cancels it.
    func giveUp() { state.withLock { $0.gaveUp = true } }

    /// Yields until the condition holds or the test gives up, answering whether it held.
    @discardableResult
    private func until(_ holds: @Sendable (borrowing State) -> Bool) async -> Bool {
        while true {
            let (held, gaveUp) = state.withLock { (holds($0), $0.gaveUp) }
            if held { return true }
            if gaveUp { return false }
            await Task.yield()
        }
    }
}

/// A recogniser that will not finish until a tidy is running beside it, where the pipeline allows one.
private actor TimedSpeechEngine: SpeechEngine {
    let kind = SpeechEngineKind.whisperKit
    private let rendezvous: StageRendezvous
    private(set) var calls = 0

    init(rendezvous: StageRendezvous) {
        self.rendezvous = rendezvous
    }

    func prepare() async throws(SpeechEngineError) {}

    func transcribe(
        _ audio: AudioSamples, options: TranscriptionOptions
    ) async throws(SpeechEngineError) -> Transcription {
        calls += 1
        let call = calls
        // The first recognition has no tidy before it to run beside, so waiting for one would never end.
        return await rendezvous.recognition(waitsForATidy: call > 1) {
            Transcription(
                text: "w\(call) x", detectedLanguage: DetectedLanguage(code: .english, confidence: 1),
                audioDuration: audio.duration)
        }
    }
}

/// A tidier that will not finish until a recognition is running beside it, where the pipeline allows one.
private final class TimedCleaner: TranscriptCleaning, Sendable {
    private let rendezvous: StageRendezvous
    private let pieces: Int
    private let calls = Mutex(0)

    init(rendezvous: StageRendezvous, pieces: Int) {
        self.rendezvous = rendezvous
        self.pieces = pieces
    }

    func clean(_ request: TransformationRequest) async throws(TransformationError) -> TransformationResult {
        let call = calls.withLock { calls in
            calls += 1
            return calls
        }
        // The last piece has no recognition left to run beside, so waiting for one would never end.
        await rendezvous.tidy(waitsForARecognition: call < pieces)
        return TransformationResult(
            text: request.transcription.text.uppercased(), producedBy: .foundationModels)
    }

    func warm(for situation: Situation?) async {}
}

/// A dictionary that rewrites the first word of whatever it is shown.
private struct FirstWordCorrector: WordCorrecting {
    let entry = UUID()

    func corrections(
        for transcription: Transcription, seeing context: AppContext
    ) async throws(DictationChangeError) -> [DictationCorrection] {
        let first = transcription.text.split(whereSeparator: \.isWhitespace).first.map(String.init) ?? ""
        return [
            DictationCorrection(
                heard: first, wrote: first.uppercased(), wordRange: 0..<1, entryID: entry,
                reason: .unknown("test"), heardConfidence: 0.1)
        ]
    }
}

/// Corrects `Maddox` only while the current document shows the supporting spelling.
private actor ScreenWordCorrector: WordCorrecting {
    private(set) var documents: [String?] = []

    func corrections(
        for transcription: Transcription, seeing context: AppContext
    ) async throws(DictationChangeError) -> [DictationCorrection] {
        documents.append(context.documentName)
        guard context.documentName == "Madison marketing plan" else { return [] }
        return [
            DictationCorrection(
                heard: "Maddox", wrote: "Madison", wordRange: 0..<1, entryID: UUID(),
                reason: .seenOnScreen, heardConfidence: 0.2)
        ]
    }
}

/// Recordings with pauses where the windowing below expects them.
private enum Take {
    static let rate = AudioSamples.canonicalSampleRate

    static func tone(_ seconds: Double) -> [Float] {
        (0..<Int(seconds * Double(rate))).map { 0.3 * Float(sin(Double($0) * 0.07)) }
    }

    static func silence(_ seconds: Double) -> [Float] {
        [Float](repeating: 0, count: Int(seconds * Double(rate)))
    }

    /// One phrase with no pause in it, so nothing is ever worked ahead.
    static let onePiece = AudioSamples.canonical(tone(1.2))

    /// A first piece with its trailing pause, and nothing captured beyond it: `threePieces`' opening.
    static let firstPieceOnly = AudioSamples.canonical(tone(1.2) + silence(0.5))

    /// Three phrases with a clear pause after the first two.
    static let threePieces = AudioSamples.canonical(
        tone(1.2) + silence(0.5) + tone(1.2) + silence(0.5) + tone(0.4))

    static let fragmentTail = AudioSamples.canonical(
        tone(1.2) + silence(0.5) + tone(1.2) + silence(0.5) + tone(0.1))

    static let speechThenSilence = AudioSamples.canonical(tone(1.2) + silence(1.0))
}

/// Windows short enough for a test recording to have several.
private let quick = SpeechWindowing(
    minimumLength: 1, sentencePause: 0.3, comfortableLength: 2, anyPause: 0.2, maximumLength: 5,
    minimumSpeech: 0.2)

extension DictationState {
    fileprivate var outcome: DictationOutcome? {
        if case .inserted(let outcome) = self { outcome } else { nil }
    }

    fileprivate var failure: DictationFailure? {
        if case .failed(let failure) = self { failure } else { nil }
    }
}

// MARK: - Tests

@Suite("Dictation pipeline: working ahead while the key is held", .timeLimit(.minutes(1)))
struct DictationPipelineEarlyWorkTests {
    private func makePipeline(
        capture: FakeAudioCaptureEngine,
        speech: any SpeechEngine = NumberingSpeechEngine(),
        cleaner: any TranscriptCleaning = ShoutingCleaner(),
        inserter: FakeTextInserter = FakeTextInserter(),
        context: FakeContextEngine = FakeContextEngine(context: .fixture()),
        corrector: any WordCorrecting = NoTextChanges(),
        metrics: any MetricsRecording = NoOpMetricsRecorder(),
        recordings: any RecordingKeeper = RecordingsNotKept(),
        earlyPoll: Duration = .milliseconds(2),
        speechWords: @escaping @Sendable (AppContext) async -> [String] = { _ in [] }
    ) -> DictationPipeline {
        DictationPipeline(
            capture: capture, speech: speech, cleaner: cleaner, context: context,
            inserter: inserter, speechWords: speechWords, corrector: corrector, metrics: metrics,
            recordings: recordings, windowing: quick, earlyPoll: earlyPoll)
    }

    /// Waits for the recogniser to have been asked `count` times.
    private func waitForCalls(_ count: Int, on speech: NumberingSpeechEngine) async throws {
        try await eventually { await speech.calls >= count }
    }

    @Test("pieces ended by a pause are recognised and tidied before the key is released")
    func worksAheadWhileRecording() async throws {
        let capture = FakeAudioCaptureEngine(stopOutcome: .success(Take.threePieces))
        await capture.setCaptured(Take.threePieces)
        let speech = NumberingSpeechEngine()
        let cleaner = ShoutingCleaner()
        let inserter = FakeTextInserter()
        let pipeline = makePipeline(capture: capture, speech: speech, cleaner: cleaner, inserter: inserter)

        await pipeline.startRecording()
        try await waitForCalls(2, on: speech)
        #expect(await pipeline.currentState == .recording)
        #expect(cleaner.seen.count >= 1, "the first piece is tidied while recording")
        await pipeline.finishRecording()

        let state = await pipeline.currentState
        // Each seam ends a sentence; the final stop is the message stage's, which this cleaner leaves alone.
        #expect(state.outcome?.text == "W1 X. W2 X. W3 X")
        #expect(state.outcome?.cleanedBy == .foundationModels)
        #expect(await speech.calls == 3)
        let counts = await speech.sampleCounts
        #expect(
            counts.reduce(0, +) == Take.threePieces.samples.count,
            "every sample goes to the recogniser once")
        #expect(
            !cleaner.warmed.isEmpty && cleaner.warmed.allSatisfy { $0 == .messaging },
            "warmed only for the Slack window the fixture shows")
        #expect(cleaner.warmed.count <= 3, "at key-down, then at most once per piece tidied while recording")
    }

    @Test("a short final phrase after a long pause joins the previous real-time window")
    func shortFinalPhraseJoinsPreviousWindow() async throws {
        let take = AudioSamples.canonical(
            Take.tone(1.2) + Take.silence(4) + Take.tone(0.35) + Take.silence(10))
        let capture = FakeAudioCaptureEngine(stopOutcome: .success(take))
        await capture.setCaptured(take)
        let speech = NumberingSpeechEngine()
        let pipeline = makePipeline(capture: capture, speech: speech)

        await pipeline.startRecording()
        try await waitForCalls(1, on: speech)
        await pipeline.finishRecording()

        #expect(await pipeline.currentState.outcome?.text == "W1 X. W2 X")
        #expect(await speech.calls == 2)
        let counts = await speech.sampleCounts
        #expect(counts[1] > 4 * Take.rate, "the final phrase is decoded with the preceding window")
    }

    @Test("a dictation of one piece warms the tidier once, at key-down, and not again after its answer")
    func onePieceWarmsOnce() async throws {
        let take = AudioSamples.canonical(Take.tone(0.8))
        let capture = FakeAudioCaptureEngine(stopOutcome: .success(take))
        await capture.setCaptured(take)
        let cleaner = ShoutingCleaner()
        let inserter = FakeTextInserter()
        let pipeline = makePipeline(capture: capture, cleaner: cleaner, inserter: inserter)

        await pipeline.startRecording()
        try await eventually { !cleaner.warmed.isEmpty }
        await pipeline.finishRecording()

        #expect(await pipeline.currentState.outcome != nil)
        #expect(cleaner.warmed == [.messaging])
    }

    @Test("each piece tidied while the key is held warms the tidier again for the piece after it")
    func eachEarlyPieceWarmsForTheNext() async throws {
        let capture = FakeAudioCaptureEngine(stopOutcome: .success(Take.threePieces))
        await capture.setCaptured(Take.threePieces)
        let cleaner = ShoutingCleaner()
        let pipeline = makePipeline(capture: capture, cleaner: cleaner)

        await pipeline.startRecording()
        try await eventually { cleaner.warmed.count >= 3 }
        await pipeline.finishRecording()

        #expect(cleaner.warmed == [.messaging, .messaging, .messaging])
        #expect(cleaner.seen.count == 3, "two pieces while held, and the last after release")
    }

    @Test("the pieces worked ahead are the recording itself, every sample once and in order")
    func piecesLoseNoAudio() async throws {
        let capture = FakeAudioCaptureEngine(stopOutcome: .success(Take.threePieces))
        await capture.setCaptured(Take.threePieces)
        let speech = KeepingSpeechEngine()
        let pipeline = makePipeline(capture: capture, speech: speech)

        await pipeline.startRecording()
        try await eventually { await speech.pieces.count >= 2 }
        await pipeline.finishRecording()

        let pieces = await speech.pieces
        #expect(pieces.count == 3)
        #expect(pieces.joined().elementsEqual(Take.threePieces.samples))
    }

    /// The first screen read warms the tidier; each piece gets another read for correction evidence, and insertion one more.
    @Test(
        "the tidier is warmed for where the screen says the words are going, and for plain text when it says nothing"
    )
    func warmsForTheDestination() async throws {
        for (context, destination) in [
            (
                AppContext.fixture(applicationName: "Xcode", bundleIdentifier: "com.apple.dt.Xcode"),
                Destination.codeEditor
            ),
            (AppContext(), .plain),
        ] {
            let capture = FakeAudioCaptureEngine(stopOutcome: .success(Take.threePieces))
            await capture.setCaptured(Take.threePieces)
            let speech = NumberingSpeechEngine()
            let cleaner = ShoutingCleaner()
            let engine = FakeContextEngine(context: context)
            let pipeline = makePipeline(capture: capture, speech: speech, cleaner: cleaner, context: engine)

            await pipeline.startRecording()
            try await waitForCalls(1, on: speech)
            await pipeline.finishRecording()

            #expect(!cleaner.warmed.isEmpty && cleaner.warmed.allSatisfy { $0 == destination })
            #expect(
                await engine.calls.count == 5,
                "one warm-up read, one correction read per piece and one read at insertion")
        }
    }

    @Test("the screen read while recording names where the words went")
    func earlyContextNamesTheApp() async throws {
        let capture = FakeAudioCaptureEngine(stopOutcome: .success(Take.threePieces))
        await capture.setCaptured(Take.threePieces)
        let speech = NumberingSpeechEngine()
        let context = FakeContextEngine(context: .fixture(applicationName: "Notes"))
        let pipeline = makePipeline(capture: capture, speech: speech, context: context)

        await pipeline.startRecording()
        try await waitForCalls(1, on: speech)
        await pipeline.finishRecording()

        #expect(await pipeline.currentState.outcome?.insertedInto == "Notes")
        #expect(
            await context.calls.count == 5,
            "one initial read, one correction read per piece and one read at insertion")
    }

    @Test("later pieces use the screen they were spoken against for correction evidence")
    func refreshesCorrectionContextForEachPiece() async throws {
        let capture = FakeAudioCaptureEngine(stopOutcome: .success(Take.threePieces))
        await capture.setCaptured(Take.threePieces)
        let cleaner = HeldCleaner()
        let corrector = ScreenWordCorrector()
        let context = FakeContextEngine(context: AppContext(documentName: "Madison marketing plan"))
        let pipeline = makePipeline(
            capture: capture, speech: RepeatedWordSpeechEngine(), cleaner: cleaner,
            context: context, corrector: corrector)

        await pipeline.startRecording()
        try await eventually { await corrector.documents.count == 1 }
        try await eventually { await cleaner.isHolding }

        await context.setContext(AppContext(documentName: "Quarterly budget"))
        await cleaner.release()
        try await eventually { await corrector.documents.count >= 2 }
        await pipeline.finishRecording()

        #expect(await corrector.documents.prefix(2) == ["Madison marketing plan", "Quarterly budget"])
        #expect(await pipeline.currentState.outcome?.changes.corrections.count == 1)
    }

    @Test("insertion padding and first-word case follow the caret at insertion time")
    func refreshesCaretBeforeInsertion() async throws {
        let capture = FakeAudioCaptureEngine(stopOutcome: .success(Take.firstPieceOnly))
        await capture.setCaptured(Take.firstPieceOnly)
        let context = FakeContextEngine(
            context: .fixture(
                applicationName: "TextEdit", bundleIdentifier: "com.apple.TextEdit",
                precedingText: "Hello"))
        let cleaner = HeldCleaner()
        let inserter = FakeTextInserter()
        let pipeline = makePipeline(
            capture: capture, speech: KeepingSpeechEngine(), cleaner: cleaner,
            inserter: inserter, context: context)

        await pipeline.startRecording()
        try await eventually { await cleaner.isHolding }
        await context.setInsertionPoint(InsertionPoint(precedingText: "\n"))
        await cleaner.release()
        await pipeline.finishRecording()

        #expect(inserter.received == ["W1 x. w2 x"], "a text editor ends the first piece as a sentence")
    }

    @Test("a different frontmost app makes the insertion caret unknown")
    func ignoresCaretFromDifferentApp() async throws {
        let capture = FakeAudioCaptureEngine(stopOutcome: .success(Take.firstPieceOnly))
        await capture.setCaptured(Take.firstPieceOnly)
        let context = FakeContextEngine(
            context: .fixture(
                applicationName: "Terminal", bundleIdentifier: "com.apple.Terminal",
                precedingText: "Hello"))
        let cleaner = HeldCleaner()
        let inserter = FakeTextInserter()
        let pipeline = makePipeline(
            capture: capture, speech: KeepingSpeechEngine(), cleaner: cleaner,
            inserter: inserter, context: context)

        await pipeline.startRecording()
        try await eventually { await cleaner.isHolding }
        await context.setContext(
            .fixture(
                applicationName: "Notes", bundleIdentifier: "com.apple.Notes", precedingText: "Hello"))
        await cleaner.release()
        await pipeline.finishRecording()

        #expect(inserter.received == ["W1 x w2 x"], "joined for the terminal it began in, which adds no stop")
    }

    @Test("pieces cut from audio the stop did not return are thrown away, not joined")
    func mismatchedAudioStartsOver() async throws {
        let capture = FakeAudioCaptureEngine(stopOutcome: .success(.silence(seconds: 0.5)))
        await capture.setCaptured(Take.threePieces)
        let speech = NumberingSpeechEngine()
        let pipeline = makePipeline(capture: capture, speech: speech)

        await pipeline.startRecording()
        try await waitForCalls(2, on: speech)
        await pipeline.finishRecording()

        let state = await pipeline.currentState
        let calls = await speech.calls
        #expect(state.outcome?.text == "W\(calls) X", "the returned audio is recognised whole")
    }

    @Test("cancelling while a piece is under way inserts nothing")
    func cancelDropsEarlyPieces() async throws {
        let capture = FakeAudioCaptureEngine(stopOutcome: .success(Take.threePieces))
        await capture.setCaptured(Take.threePieces)
        let speech = NumberingSpeechEngine()
        let inserter = FakeTextInserter()
        let pipeline = makePipeline(capture: capture, speech: speech, inserter: inserter)

        await pipeline.startRecording()
        try await waitForCalls(1, on: speech)
        await pipeline.cancel()
        await pipeline.finishRecording()

        #expect(await pipeline.currentState == .idle)
        #expect(inserter.received.isEmpty)
    }

    @Test("a retry after canceling a dictation has no context from the cancelled screen")
    func retryAfterCancelDropsEarlyContext() async throws {
        let recording = KeptRecording(id: UUID(), when: Date(), duration: .seconds(3))
        let recordings = FakeRecordingKeeper(
            waiting: [recording], audioOutcome: .success(Take.threePieces))
        let cleaner = ShoutingCleaner()
        let context = FakeContextEngine(
            context: .fixture(applicationName: "Keychain Access", isSecure: true))
        let pipeline = makePipeline(
            capture: FakeAudioCaptureEngine(), cleaner: cleaner, context: context, recordings: recordings)

        await pipeline.startRecording()
        try await eventually { await pipeline.earlyReadsSettled == 1 }
        await pipeline.cancel()
        await pipeline.retry(recording.id)

        #expect(!cleaner.contexts.isEmpty)
        #expect(cleaner.contexts.allSatisfy { $0 == AppContext() })
        #expect(await pipeline.currentState.outcome?.intoSecureField == false)
    }

    @Test("a new start after cancel reads its own screen")
    func startAfterCancelReadsFreshContext() async throws {
        let capture = FakeAudioCaptureEngine(stopOutcome: .success(Take.onePiece))
        await capture.setCaptured(Take.onePiece)
        let context = FakeContextEngine(
            context: .fixture(applicationName: "Keychain Access", isSecure: true))
        let pipeline = makePipeline(capture: capture, context: context, earlyPoll: .seconds(60))

        await pipeline.startRecording()
        try await eventually { await pipeline.earlyReadsSettled == 1 }
        await pipeline.cancel()

        await context.setContext(.fixture(applicationName: "Notes"))
        await capture.setCaptured(Take.onePiece)
        await pipeline.startRecording()
        try await eventually { await pipeline.earlyReadsSettled == 2 }
        await pipeline.finishRecording()

        #expect(await pipeline.currentState.outcome?.insertedInto == "Notes")
        #expect(await pipeline.currentState.outcome?.intoSecureField == false)
    }

    @Test("a piece that fails while recording is left for the end, where its failure is reported")
    func earlyFailureIsReportedAtTheEnd() async throws {
        let capture = FakeAudioCaptureEngine(stopOutcome: .success(Take.threePieces))
        await capture.setCaptured(Take.threePieces)
        let speech = NumberingSpeechEngine(failingCalls: Set(1...12))
        let pipeline = makePipeline(capture: capture, speech: speech)

        await pipeline.startRecording()
        try await waitForCalls(1, on: speech)
        await pipeline.finishRecording()

        #expect(await pipeline.currentState.failure != nil)
        #expect(await speech.calls >= 2, "the failed piece is tried once more at the end, not skipped")
    }

    @Test("a piece that fails while recording does not stop the later pieces being worked ahead")
    func earlyFailureLeavesTheRestWorkingAhead() async throws {
        let capture = FakeAudioCaptureEngine(stopOutcome: .success(Take.threePieces))
        await capture.setCaptured(Take.threePieces)
        let speech = NumberingSpeechEngine(failingCalls: [1])
        let pipeline = makePipeline(capture: capture, speech: speech)

        await pipeline.startRecording()
        try await waitForCalls(2, on: speech)
        #expect(
            await pipeline.currentState == .recording,
            "the piece after the failed one is worked ahead, not left to the release")
        await pipeline.finishRecording()

        let state = await pipeline.currentState
        #expect(
            state.outcome?.text == "W3 X. W2 X. W4 X", "the failed piece is redone in its own place")
        #expect(await speech.calls == 4, "only the failed piece and the tail are left for the end")
    }

    @Test("a failed early window joins a fragment tail to its pending span")
    func failedEarlyWindowJoinsFragmentTail() async throws {
        let capture = FakeAudioCaptureEngine(stopOutcome: .success(Take.fragmentTail))
        await capture.setCaptured(Take.fragmentTail)
        let speech = NumberingSpeechEngine(failingCalls: [1])
        let pipeline = makePipeline(capture: capture, speech: speech)

        await pipeline.startRecording()
        try await waitForCalls(1, on: speech)
        await pipeline.finishRecording()

        #expect(await pipeline.currentState.outcome?.text == "W2 X")
        #expect(await speech.calls == 2)
    }

    @Test("a silent early window does not remove the preceding finished span")
    func silentEarlyWindowKeepsPriorSpanBeforeFragmentTail() async throws {
        let capture = FakeAudioCaptureEngine(stopOutcome: .success(Take.fragmentTail))
        await capture.setCaptured(Take.fragmentTail)
        let speech = NumberingSpeechEngine(silentCalls: [2])
        let pipeline = makePipeline(capture: capture, speech: speech)

        await pipeline.startRecording()
        try await waitForCalls(2, on: speech)
        await pipeline.finishRecording()

        #expect(await pipeline.currentState.outcome?.text == "W1 X. W3 X")
        #expect(await speech.calls == 3)
    }

    @Test("a retried recording is recognised in windows, so a long one is never one request")
    func retryUsesWindows() async {
        let recording = KeptRecording(id: UUID(), when: Date(), duration: .seconds(3))
        let recordings = FakeRecordingKeeper(
            waiting: [recording], audioOutcome: .success(Take.threePieces))
        let speech = NumberingSpeechEngine()
        let pipeline = makePipeline(
            capture: FakeAudioCaptureEngine(), speech: speech, recordings: recordings)

        await pipeline.retry(recording.id)

        let state = await pipeline.currentState
        #expect(state.outcome?.text == "W1 X. W2 X. W3 X")
        #expect(state.outcome?.isFromRecording == true)
        #expect(await speech.calls == 3)
    }

    @Test("a speech-bearing piece with no words is decoded again, without the vocabulary, in its own place")
    func speechBearingPieceIsDecodedAgain() async {
        for blank in [false, true] {
            let speech = NumberingSpeechEngine(
                silentCalls: blank ? [] : [2], blankCalls: blank ? [2] : [])
            let pipeline = makePipeline(
                capture: FakeAudioCaptureEngine(stopOutcome: .success(Take.threePieces)),
                speech: speech, earlyPoll: .seconds(60))

            await pipeline.startRecording()
            await pipeline.finishRecording()

            let outcome = await pipeline.currentState.outcome
            #expect(outcome?.text == "W1 X. W3 X. W4 X")
            #expect(outcome?.missedPieces == 0)
            #expect(await speech.calls == 4)
            #expect(await speech.biases[2].isEmpty, "the second decode goes without the vocabulary")
        }
    }

    /// A long dictation is many pieces, and one short blank one must not cost the rest. Issue #2099.
    @Test("a piece with speech that decodes to no words twice is left out and counted, and the rest go in")
    func speechBearingPieceIsSkippedAfterTwoDecodes() async {
        let speech = NumberingSpeechEngine(blankCalls: [2, 3])
        let inserter = FakeTextInserter()
        let pipeline = makePipeline(
            capture: FakeAudioCaptureEngine(stopOutcome: .success(Take.threePieces)),
            speech: speech, inserter: inserter, earlyPoll: .seconds(60))

        await pipeline.startRecording()
        await pipeline.finishRecording()

        let outcome = await pipeline.currentState.outcome
        #expect(outcome?.text == "W1 X. W4 X")
        #expect(outcome?.missedPieces == 1)
        #expect(inserter.received == ["W1 X. W4 X"])
    }

    @Test("a dictation that missed a piece keeps its recording, and one that missed none deletes it")
    func missedPieceKeepsTheRecording() async {
        for missed in [false, true] {
            let recording = KeptRecording(id: UUID(), when: Date(), duration: .seconds(3))
            let recordings = FakeRecordingKeeper(current: recording)
            let pipeline = makePipeline(
                capture: FakeAudioCaptureEngine(stopOutcome: .success(Take.threePieces)),
                speech: NumberingSpeechEngine(blankCalls: missed ? [2, 3] : []),
                recordings: recordings, earlyPoll: .seconds(60))

            await pipeline.startRecording()
            await pipeline.finishRecording()

            #expect(await pipeline.currentState.outcome?.missedPieces == (missed ? 1 : 0))
            #expect(await recordings.discarded == (missed ? [] : [recording.id]))
        }
    }

    @Test("a secure-field dictation that missed a piece keeps no audio")
    func secureMissedPieceKeepsNoAudio() async {
        let recording = KeptRecording(id: UUID(), when: Date(), duration: .seconds(3))
        let recordings = FakeRecordingKeeper(current: recording)
        let pipeline = makePipeline(
            capture: FakeAudioCaptureEngine(stopOutcome: .success(Take.threePieces)),
            speech: NumberingSpeechEngine(blankCalls: [2, 3]),
            inserter: FakeTextInserter(.success(InsertionAttempt(.pasteboard, intoSecureField: true))),
            recordings: recordings, earlyPoll: .seconds(60))

        await pipeline.startRecording()
        await pipeline.finishRecording()

        #expect(await pipeline.currentState.outcome?.missedPieces == 1)
        #expect(await recordings.discarded == [recording.id])
    }

    @Test("retrying the recording kept for a missed piece produces the missing words")
    func retryRecoversTheMissedPiece() async {
        let recording = KeptRecording(id: UUID(), when: Date(), duration: .seconds(3))
        let recordings = FakeRecordingKeeper(
            current: recording, audioOutcome: .success(Take.threePieces))
        let speech = NumberingSpeechEngine(blankCalls: [2, 3])
        let pipeline = makePipeline(
            capture: FakeAudioCaptureEngine(stopOutcome: .success(Take.threePieces)),
            speech: speech, recordings: recordings, earlyPoll: .seconds(60))
        await pipeline.startRecording()
        await pipeline.finishRecording()
        #expect(await recordings.discarded.isEmpty)

        await pipeline.retry(recording.id)

        let outcome = await pipeline.currentState.outcome
        #expect(outcome?.text == "W5 X. W6 X. W7 X")
        #expect(outcome?.missedPieces == 0)
        #expect(await recordings.discarded == [recording.id])
    }

    @Test(
        "a recording whose every speech-bearing piece decodes to no words fails as untranscribed, not silent")
    func everyPieceMissedFails() async {
        let speech = NumberingSpeechEngine(blankCalls: Set(1...6))
        let inserter = FakeTextInserter()
        let pipeline = makePipeline(
            capture: FakeAudioCaptureEngine(stopOutcome: .success(Take.threePieces)),
            speech: speech, inserter: inserter, earlyPoll: .seconds(60))

        await pipeline.startRecording()
        await pipeline.finishRecording()

        #expect(
            await pipeline.currentState
                == .failed(
                    DictationFailure(
                        SpeechEngineError.speechWithoutWords)))
        #expect(inserter.received.isEmpty)
    }

    @Test("a genuinely silent trailing window is skipped after speech")
    func silentWindowIsSkipped() async {
        let speech = NumberingSpeechEngine(silentCalls: [2])
        let pipeline = makePipeline(
            capture: FakeAudioCaptureEngine(stopOutcome: .success(Take.speechThenSilence)),
            speech: speech, earlyPoll: .seconds(60))

        await pipeline.startRecording()
        await pipeline.finishRecording()

        #expect(await pipeline.currentState.outcome?.text.hasPrefix("W1 X") == true)
        #expect(await speech.calls == 2)
    }

    @Test("a genuinely silent recording is refused as silence")
    func allSilentIsRefused() async {
        let speech = NumberingSpeechEngine(silentCalls: [1])
        let pipeline = makePipeline(
            capture: FakeAudioCaptureEngine(stopOutcome: .success(.roomTone(seconds: 3))),
            speech: speech)

        await pipeline.startRecording()
        await pipeline.finishRecording()

        #expect(await pipeline.currentState == .failed(DictationFailure(SpeechEngineError.nothingHeard)))
    }

    @Test("a blank transcript of non-speech remains nothing heard")
    func blankNonSpeechDecodeIsNothing() async {
        let speech = NumberingSpeechEngine(blankCalls: [1])
        let pipeline = makePipeline(
            capture: FakeAudioCaptureEngine(
                stopOutcome: .success(.roomTone(seconds: 3))),
            speech: speech)

        await pipeline.startRecording()
        await pipeline.finishRecording()

        #expect(await pipeline.currentState == .failed(DictationFailure(SpeechEngineError.nothingHeard)))
    }

    @Test("speech that decodes to blank text remains a recognition miss")
    func blankSpeechDecodeIsMissed() async {
        let speech = NumberingSpeechEngine(blankCalls: [1, 2])
        let pipeline = makePipeline(
            capture: FakeAudioCaptureEngine(stopOutcome: .success(Take.onePiece)), speech: speech)

        await pipeline.startRecording()
        await pipeline.finishRecording()

        #expect(
            await pipeline.currentState
                == .failed(
                    DictationFailure(
                        SpeechEngineError.speechWithoutWords)))
    }

    @Test("corrections keep pointing at their words after the pieces are joined")
    func correctionsAreShifted() async {
        let pipeline = makePipeline(
            capture: FakeAudioCaptureEngine(stopOutcome: .success(Take.threePieces)),
            corrector: FirstWordCorrector())

        await pipeline.startRecording()
        await pipeline.finishRecording()

        let outcome = await pipeline.currentState.outcome
        #expect(outcome?.text == "W1 X. W2 X. W3 X")
        #expect(outcome?.changes.corrections.map(\.wordRange) == [0..<1, 2..<3, 4..<5])
        #expect(outcome?.changes.spokenWords == 6)
    }

    @Test("one piece the model left to the rules makes the whole a rules result")
    func mixedTidyingReportsRules() async {
        let pipeline = makePipeline(
            capture: FakeAudioCaptureEngine(stopOutcome: .success(Take.threePieces)),
            cleaner: ShoutingCleaner(failOn: "w2"))

        await pipeline.startRecording()
        await pipeline.finishRecording()

        let outcome = await pipeline.currentState.outcome
        #expect(outcome?.text == "W1 X. w2 x. W3 X")
        #expect(outcome?.cleanedBy == .rules)
    }

    @Test("what a piece cost the recogniser beyond one decode reaches the recorder")
    func decodeEffortIsRecorded() async {
        let metrics = RecordingMetricsRecorder()
        let effort = DecodeEffort(
            fallbacks: 3, fallbackSeconds: 1.5, encoderRuns: 2, retriedWithoutPrompt: true)
        let speech = FakeSpeechEngine(
            transcribeOutcome: .success(
                Transcription(text: "hello there", audioDuration: .seconds(1), effort: effort)))
        let pipeline = makePipeline(
            capture: FakeAudioCaptureEngine(stopOutcome: .success(Take.threePieces)),
            speech: speech, metrics: metrics)

        await pipeline.startRecording()
        await pipeline.finishRecording()

        #expect(await metrics.decoding == [effort, effort, effort], "one per recognised piece")
    }

    @Test("a dictation done in pieces still reports one figure per stage")
    func metricsAreOnePerStage() async {
        let metrics = RecordingMetricsRecorder()
        let pipeline = makePipeline(
            capture: FakeAudioCaptureEngine(stopOutcome: .success(Take.threePieces)), metrics: metrics)

        await pipeline.startRecording()
        await pipeline.finishRecording()

        #expect(await metrics.measurements(for: .transcription).count == 1)
        #expect(await metrics.measurements(for: .transformation).count == 1)
        #expect(await metrics.measurements(for: .insertion).count == 1)
    }

    @Test("nothing recorded at all still reaches the recogniser, whose refusal names the reason")
    func emptyRecordingIsRefusedByTheRecogniser() async {
        let speech = NumberingSpeechEngine(silentCalls: [1])
        let pipeline = makePipeline(
            capture: FakeAudioCaptureEngine(stopOutcome: .success(.empty)), speech: speech)

        await pipeline.startRecording()
        await pipeline.finishRecording()

        #expect(await speech.calls == 1)
        #expect(await pipeline.currentState == .failed(DictationFailure(SpeechEngineError.nothingHeard)))
    }

    /// The contract VocabularySource's own doc comment claims, which the engine used to break. See #180.
    @Test("ranks the dictation's words once, however many pieces it is cut into")
    func ranksTheWordsOncePerDictation() async throws {
        let capture = FakeAudioCaptureEngine(stopOutcome: .success(Take.threePieces))
        await capture.setCaptured(Take.threePieces)
        let speech = NumberingSpeechEngine()
        let rankings = Mutex<[AppContext]>([])
        let pipeline = makePipeline(capture: capture, speech: speech) { seeing in
            rankings.withLock { $0.append(seeing) }
            return ["Uttrflow"]
        }

        await pipeline.startRecording()
        try await waitForCalls(2, on: speech)
        await pipeline.finishRecording()

        #expect(await speech.calls == 3)
        #expect(rankings.withLock(\.count) == 1, "one ranking, not one per piece")
        #expect(
            await speech.biases == [["Uttrflow"], ["Uttrflow"], ["Uttrflow"]],
            "every piece is biased towards the same words")
        // Ranked against the screen the dictation began on, which is the one the tidier resolves from.
        #expect(rankings.withLock { $0.first?.applicationName } == AppContext.fixture().applicationName)
    }

    /// The release pass overlaps the two stages, which a retry is the plainest case of. See #186.
    @Test("the tidy of one piece runs beside the recognition of the next, and the pieces stay in order")
    func tidyingRunsBesideTheNextRecognition() async {
        let rendezvous = StageRendezvous()
        let recording = KeptRecording(id: UUID(), when: Date(), duration: .seconds(3))
        let recordings = FakeRecordingKeeper(
            waiting: [recording], audioOutcome: .success(Take.threePieces))
        let pipeline = makePipeline(
            capture: FakeAudioCaptureEngine(),
            speech: TimedSpeechEngine(rendezvous: rendezvous),
            cleaner: TimedCleaner(rendezvous: rendezvous, pieces: 3),
            recordings: recordings)

        // The time limit cancels a serial pipeline's wait, which then ends every stage's wait with it.
        let retrying = Task { await pipeline.retry(recording.id) }
        await withTaskCancellationHandler {
            _ = await retrying.value
        } onCancel: {
            rendezvous.giveUp()
        }

        #expect(
            await pipeline.currentState.outcome?.text == "W1 X. W2 X. W3 X",
            "the pieces are joined in the order they were spoken")
        #expect(rendezvous.recognitions == 3)
        // Each stage waits for the other, so a late-scheduled tidy is waited for rather than missed.
        #expect(
            rendezvous.tidiesBesideARecognition == 2,
            "every tidy but the last runs beside the next recognition")
    }

    /// Releases the key while `holding` is true of the first piece, then lets that piece finish once the release is waiting on it.
    private func releaseMidPiece(
        _ pipeline: DictationPipeline, holding: @Sendable () async -> Bool, letGo: @Sendable () async -> Void
    ) async throws {
        await pipeline.startRecording()
        try await eventually { await holding() }
        let finishing = Task { await pipeline.finishRecording() }
        try await eventually { await pipeline.currentState == .transcribing }
        await letGo()
        await finishing.value
    }

    /// The drain begins when the key comes up, so the user waits through it and Diagnostics must say so.
    @Test("charges the wait to the drain when the key comes up while the piece is being tidied")
    func measuresTheDrain() async throws {
        let capture = FakeAudioCaptureEngine(stopOutcome: .success(Take.threePieces))
        await capture.setCaptured(Take.threePieces)
        let cleaner = HeldCleaner()
        let metrics = RecordingMetricsRecorder()
        let pipeline = makePipeline(capture: capture, cleaner: cleaner, metrics: metrics)

        try await releaseMidPiece(
            pipeline, holding: { await cleaner.isHolding }, letGo: { await cleaner.release() })

        #expect(await metrics.measurements.contains { $0.stage == .drain })
    }

    /// Issue 853: the hand-off used to wait for the whole tidy before recognising anything after it.
    @Test("recognises the audio after an early piece while that piece is still being tidied")
    func tailRecognitionDoesNotWaitForAHeldTidy() async throws {
        let capture = FakeAudioCaptureEngine(stopOutcome: .success(Take.threePieces))
        // While recording, only the first piece's audio has arrived; the rest comes back from `stop()`.
        await capture.setCaptured(Take.firstPieceOnly)
        let cleaner = HeldCleaner()
        let speech = NumberingSpeechEngine()
        let pipeline = makePipeline(capture: capture, speech: speech, cleaner: cleaner)

        await pipeline.startRecording()
        try await eventually { await cleaner.isHolding }
        let finishing = Task { await pipeline.finishRecording() }
        try await waitForCalls(2, on: speech)
        #expect(await cleaner.isHolding, "the first piece's tidy is still held")

        await cleaner.release()
        await finishing.value

        #expect(await pipeline.currentState.outcome?.text == "w1 x. w2 x. w3 x")
    }

    /// Issue 344: recognition is usually the longer half of the in-flight piece, and was the half the drain missed.
    @Test("charges the wait to the drain when the key comes up while the piece is still being recognised")
    func measuresTheDrainDuringRecognition() async throws {
        let capture = FakeAudioCaptureEngine(stopOutcome: .success(Take.threePieces))
        await capture.setCaptured(Take.threePieces)
        let speech = HeldSpeechEngine()
        let metrics = RecordingMetricsRecorder()
        let pipeline = makePipeline(capture: capture, speech: speech, metrics: metrics)

        try await releaseMidPiece(
            pipeline, holding: { await speech.isHolding }, letGo: { await speech.release() })

        #expect(await metrics.measurements.contains { $0.stage == .drain })
    }

    /// A dictation with no piece in flight waits for nothing, and a row of zero would only mislead.
    @Test("charges nothing when there was no piece in flight")
    func measuresNoDrainWithoutEarlyWork() async {
        let capture = FakeAudioCaptureEngine(stopOutcome: .success(Take.onePiece))
        await capture.setCaptured(Take.onePiece)
        let metrics = RecordingMetricsRecorder()
        // No early poll ever fires, so nothing is ever in flight to wait for.
        let pipeline = DictationPipeline(
            capture: capture, speech: NumberingSpeechEngine(), cleaner: ShoutingCleaner(),
            context: FakeContextEngine(context: .fixture()), inserter: FakeTextInserter(),
            metrics: metrics, windowing: quick, earlyPoll: .seconds(60))

        await pipeline.startRecording()
        await pipeline.finishRecording()

        #expect(await metrics.measurements.contains { $0.stage == .drain } == false)
    }
}
