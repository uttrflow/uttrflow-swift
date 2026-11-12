// A scripted dictation driven through the real DictationPipeline, from key-down to the write.
import Foundation

@testable import UttrflowAI
@testable import UttrflowCore
@testable import UttrflowPipeline
import UttrflowTestSupport

/// One piece of a scripted dictation: what the recogniser hears in it, how sure it is, and the pause before it.
struct ScriptedPiece: Sendable {
    let text: String
    /// The confidence every word of the piece is heard with.
    let wordConfidence: Double
    /// Silence ahead of this piece's speech; the first piece starts the recording, so its pause is ignored.
    let pauseBefore: Double
    /// The language the recogniser says it heard the piece in.
    let language: LanguageCode
    /// How long the piece's decode takes on the scenario's manual clock.
    let decodeTime: Duration
    /// The fallback decodes the recogniser reports for the piece.
    let effort: DecodeEffort

    init(
        _ text: String, wordConfidence: Double = 1, pauseBefore: Double = 0.5,
        language: LanguageCode = .english, decodeTime: Duration = .zero, effort: DecodeEffort = .none
    ) {
        self.text = text
        self.wordConfidence = wordConfidence
        self.pauseBefore = pauseBefore
        self.language = language
        self.decodeTime = decodeTime
        self.effort = effort
    }
}

/// What a dictation is, as the person gives it: the pieces said, the field and app, who they are, and the cleaners.
struct Scenario: Sendable {
    var pieces: [ScriptedPiece]
    /// The screen read, whose bundle identifier the real classifier turns into a destination.
    var context: AppContext
    var cleaner: any TranscriptCleaning = ScenarioCleaners.rules
    var profile: UserProfile = .default
    var corrector: any WordCorrecting = NoTextChanges()
    var snippets: any SnippetExpanding = NoTextChanges()
    /// The spellings the person prefers, as the dictionary hands them to the script pass.
    var spellings: @Sendable () async -> [String: String] = { [:] }
    /// The recording itself, when a test needs audio the pieces' pauses cannot describe.
    var take: AudioSamples?
    /// The piece whose decode waits until the test releases it, counted from the first decode the recogniser is asked for.
    var heldPiece: Int?
    var recordings: any RecordingKeeper = RecordingsNotKept()
    /// The words the recogniser is biased towards, read from the screen.
    var speechWords: @Sendable (AppContext) async -> [String] = { _ in [] }
    /// The person's per-app destination and formatting choices.
    var destinationOverrides: DestinationOverrides = .none
    var cleaningRecorder: any CleaningRecording = NoOpCleaningRecorder()
    var metrics: any MetricsRecording = NoOpMetricsRecorder()
    /// The clock the pipeline times its stages on; each decode moves it on by the piece's decode time.
    var clock: ManualClock?
    /// How often the pipeline looks for a finished piece while the key is held.
    var earlyPoll: Duration = .milliseconds(2)
}

/// The cleaner stacks a scenario runs under.
enum ScenarioCleaners {
    /// The shipping floor: the deterministic passes, with no model in front of them.
    static let rules = TransformerRouter(engines: [RuleBasedTransformer()], preference: [.rules])

    /// The shipping model engine over a model scripted to answer each piece, with the floor beneath it.
    static func model(_ answers: [String: String]) -> TransformerRouter {
        TransformerRouter(
            engines: [
                GenerativeTextTransformer(
                    kind: .foundationModels, model: ScriptedSentenceModel(answers: answers)),
                RuleBasedTransformer(),
            ],
            preference: [.foundationModels, .rules])
    }
}

/// What one scenario left behind: the final state, everything written, and what the recogniser answered.
struct ScenarioRun: Sendable {
    let state: DictationState
    /// Every string the inserter was handed, in order.
    let writes: [String]
    /// Every caret move the inserter was asked for after a write, in UTF-16 units back from the end.
    let placedCarets: [Int]
    /// What the recogniser answered, a transcription per piece asked for.
    let heard: [Transcription]
    let context: AppContext
    fileprivate let pipeline: DictationPipeline

    var outcome: DictationOutcome? {
        guard case .inserted(let outcome) = state else { return nil }
        return outcome
    }

    /// The text the dictation finished with, or nil when it inserted nothing.
    var text: String? { outcome?.text }

    /// The words after each stage, named, from each piece's dictionary pass to the write the field received.
    func stages() async -> [(stage: String, text: String)] {
        let trace = await pipeline.trace(heard, seeing: context)
        var stages: [(stage: String, text: String)] = [
            ("per-piece dictionary", trace.pieces.map(\.corrected.text).joined(separator: " ")),
            ("per-piece clean", trace.pieces.map(\.cleaned.text).joined(separator: " ")),
        ]
        if let joined = trace.joined {
            stages += [
                ("unit rejoin", joined.rejoined.map(\.cleaned.text).joined(separator: " ")),
                ("join", joined.laid.cleaned.text),
                ("seam correction", joined.acrossSeams.cleaned.text),
                ("message finish", joined.whole.cleaned.text),
                ("script and snippets", trace.text ?? ""),
            ]
        }
        stages.append(("write", writes.last ?? ""))
        return stages
    }
}

/// Runs a scripted dictation through the real pipeline: windowing, recognition order, cleaning, join and insertion.
enum ScenarioDriver {
    /// Windows short enough for a test recording to have several.
    static let windows = SpeechWindowing(
        minimumLength: 1, sentencePause: 0.3, comfortableLength: 2, anyPause: 0.2, maximumLength: 5,
        minimumSpeech: 0.2)

    /// Each piece as 1.2 s of speech, after its pause, so the real windowing cuts one window per piece.
    static func take(_ pieces: [ScriptedPiece]) -> AudioSamples {
        let rate = Double(AudioSamples.canonicalSampleRate)
        var samples: [Float] = []
        for (index, piece) in pieces.enumerated() {
            if index > 0 {
                samples += [Float](repeating: 0, count: Int(piece.pauseBefore * rate))
            }
            samples += (0..<Int(1.2 * rate)).map { 0.3 * Float(sin(Double($0) * 0.07)) }
        }
        return AudioSamples.canonical(samples)
    }

    /// One window of speech, for a scenario whose pieces are every decode of the same recording.
    static let oneWindow = take([ScriptedPiece("")])

    static func run(_ scenario: Scenario) async -> ScenarioRun {
        await session(scenario).run()
    }

    /// The form a spoken phrase reaches the snippet matcher in, under the scenario's dictionary and cleaners.
    static func arrival(ofSpoken phrase: String, in scenario: Scenario) async -> String {
        await session(scenario).pipeline.arrival(ofSpoken: phrase)
    }

    /// The scenario's pipeline before key-down, for a test that presses the keys itself.
    static func session(_ scenario: Scenario) async -> ScenarioSession {
        let take = scenario.take ?? take(scenario.pieces)
        let capture = FakeAudioCaptureEngine(stopOutcome: .success(take))
        await capture.setCaptured(take)
        let speech = ScriptedPieceRecogniser(
            scenario.pieces, holding: scenario.heldPiece, clock: scenario.clock)
        let inserter = FakeTextInserter()
        let pipeline = DictationPipeline(
            capture: capture, speech: speech, cleaner: scenario.cleaner,
            context: FakeContextEngine(context: scenario.context), inserter: inserter,
            speechWords: scenario.speechWords, corrector: scenario.corrector,
            snippets: scenario.snippets, spellings: scenario.spellings, metrics: scenario.metrics,
            cleaningRecorder: scenario.cleaningRecorder,
            destinationOverrides: scenario.destinationOverrides, recordings: scenario.recordings,
            clock: scenario.clock ?? ContinuousClock(), profile: scenario.profile,
            windowing: windows, earlyPoll: scenario.earlyPoll)
        return ScenarioSession(
            pipeline: pipeline, speech: speech, inserter: inserter, context: scenario.context)
    }
}

/// A scenario's pipeline, recogniser and inserter, wired and waiting for key-down.
struct ScenarioSession: Sendable {
    let pipeline: DictationPipeline
    let speech: ScriptedPieceRecogniser
    let inserter: FakeTextInserter
    let context: AppContext

    /// Holds the key for the whole take, lets go, and reports what the dictation left behind.
    func run() async -> ScenarioRun {
        await pipeline.startRecording()
        await pipeline.finishRecording()
        return ScenarioRun(
            state: await pipeline.currentState, writes: inserter.received,
            placedCarets: inserter.placedCarets, heard: await speech.answered, context: context,
            pipeline: pipeline)
    }
}

/// A recogniser that reads out the next scripted piece per call, so a dictation's pieces are known in advance.
actor ScriptedPieceRecogniser: SpeechEngine {
    let kind = SpeechEngineKind.whisperKit
    private let pieces: [ScriptedPiece]
    private let heldPiece: Int?
    private let clock: ManualClock?
    private var held: CheckedContinuation<Void, Never>?
    private var released = false
    /// The language hint of every decode asked for, in the order asked.
    private(set) var hints: [LanguageCode?] = []
    private(set) var answered: [Transcription] = []

    init(_ pieces: [ScriptedPiece], holding heldPiece: Int? = nil, clock: ManualClock? = nil) {
        self.pieces = pieces
        self.heldPiece = heldPiece
        self.clock = clock
    }

    /// Lets the held piece's decode answer.
    func release() {
        released = true
        held?.resume()
        held = nil
    }

    func prepare() async throws(SpeechEngineError) {}

    func transcribe(
        _ audio: AudioSamples, options: TranscriptionOptions
    ) async throws(SpeechEngineError) -> Transcription {
        let index = hints.count
        hints.append(options.languageHint)
        guard index < pieces.count else { throw .nothingHeard }
        if index == heldPiece, !released { await withCheckedContinuation { held = $0 } }
        let piece = pieces[index]
        clock?.advance(by: piece.decodeTime)
        let speech = TranscriptionSegment(
            text: piece.text, start: .zero, end: audio.duration,
            words: piece.text.spokenWords.map {
                TranscribedWord(text: String($0), confidence: piece.wordConfidence)
            })
        let heard = Transcription(
            text: piece.text, detectedLanguage: DetectedLanguage(code: piece.language, confidence: 1),
            segments: piece.text.isEmpty ? [] : [speech], audioDuration: audio.duration,
            effort: piece.effort)
        answered.append(heard)
        return heard
    }
}

/// A language model that answers each piece with the sentence it was scripted for, as a model that punctuates would.
struct ScriptedSentenceModel: CleanupModel {
    let answers: [String: String]

    func availability(for language: LanguageCode?) async -> TransformerAvailability { .available }

    func rewrite(
        _ text: String, instructions: String, kind: TransformerKind
    ) async throws(TransformationError) -> String {
        guard let answer = answers.first(where: { text.contains($0.key) })?.value else {
            throw .transformFailed(kind: kind, failure: .other)
        }
        return answer
    }
}

/// A dictionary holding one spelling for one heard word, wherever it is heard.
struct OneEntryDictionary: WordCorrecting {
    let heard: String
    let wrote: String

    func corrections(
        for transcription: Transcription, seeing context: AppContext
    ) async throws(DictationChangeError) -> [DictationCorrection] {
        transcription.text.split(whereSeparator: \.isWhitespace).enumerated().compactMap {
            $0.element.lowercased() == heard
                ? DictationCorrection(
                    heard: String($0.element), wrote: wrote, wordRange: $0.offset..<($0.offset + 1),
                    entryID: UUID(), reason: .unknown("test"), heardConfidence: 0.2)
                : nil
        }
    }
}

/// The snippets on file, matched by the shipping matcher.
struct FiledSnippets: SnippetExpanding {
    let snippets: [Snippet]

    func expand(_ text: String, in application: String?) async -> ExpandedTranscript {
        let expansion = SnippetExpander(snippets: snippets, in: application).expand(text)
        return ExpandedTranscript(
            text: expansion.text,
            snippets: expansion.applied.map {
                SnippetUse(snippetID: $0.snippetID, matched: $0.matched, expansion: $0.expansion)
            }, caret: expansion.caret)
    }
}
