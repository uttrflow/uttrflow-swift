import Foundation
import Testing

@testable import UttrflowCore
@testable import UttrflowPipeline
@testable import UttrflowTestSupport

/// Three pieces of speech with a pause after each of the first two, the recording every dictation here gives.
private let threePieces = ScenarioDriver.take(["one", "two", "three"].map { ScriptedPiece($0) })

/// Pieces the recogniser reports in `detected`, decode by decode.
private func pieces(detecting detected: [LanguageCode]) -> [ScriptedPiece] {
    detected.enumerated().map { ScriptedPiece("piece \($0.offset + 1)", language: $0.element) }
}

@Suite("Dictation pipeline: one language per dictation")
struct DictationPipelineLanguageTests {
    /// A pipeline over a three-piece recording and a recogniser that reports `detected`, call by call.
    private func pipeline(
        detecting detected: [LanguageCode], profile: UserProfile = .default,
        earlyPoll: Duration = .milliseconds(2),
        recordings: any RecordingKeeper = RecordingsNotKept()
    ) async -> (DictationPipeline, ScriptedPieceRecogniser) {
        let session = await ScenarioDriver.session(
            Scenario(
                pieces: pieces(detecting: detected), context: .fixture(),
                cleaner: FakeTranscriptCleaner(producedBy: .foundationModels), profile: profile,
                take: threePieces, recordings: recordings, earlyPoll: earlyPoll))
        return (session.pipeline, session.speech)
    }

    /// A default profile detects each pause-delimited piece without a language hint.
    @Test("detects each piece independently for the default profile")
    func detectsEveryPieceForDefaultProfile() async {
        let (pipeline, speech) = await pipeline(detecting: [.english, .hindi, .hindi])

        await pipeline.startRecording()
        await pipeline.finishRecording()
        let hints = await speech.hints

        #expect(hints.count > 1)
        #expect(hints.allSatisfy { $0 == nil })
    }

    /// Each dictation resolves its own language settings and detects every piece again.
    @Test("detects every piece again for the next dictation")
    func forgetsBetweenDictations() async {
        let (pipeline, speech) = await pipeline(
            detecting: [.english, .english, .english, .hindi, .hindi, .hindi])

        await pipeline.startRecording()
        await pipeline.finishRecording()
        let first = await speech.hints.count
        await pipeline.startRecording()
        await pipeline.finishRecording()
        let hints = await speech.hints

        #expect(hints.count > first)
        #expect(hints.dropFirst(first).allSatisfy { $0 == nil })
    }

    /// A retry is its own attempt, so it detects its own language rather than the last dictation's.
    @Test("detects again for a retry rather than keeping the last dictation's language")
    func forgetsBeforeARetry() async {
        let kept = KeptRecording(id: UUID(), when: Date(), duration: .seconds(4))
        let (pipeline, speech) = await pipeline(
            detecting: [.english, .english, .english, .hindi, .hindi, .hindi],
            recordings: FakeRecordingKeeper(waiting: [kept], audioOutcome: .success(threePieces)))

        await pipeline.startRecording()
        await pipeline.finishRecording()
        let first = await speech.hints.count
        await pipeline.retry(kept.id)
        let hints = await speech.hints

        #expect(hints.count > first)
        #expect(hints[first] == nil)
    }

    /// A bilingual profile can change languages between pause-delimited pieces.
    @Test("detects a Hindi-to-English switch for a bilingual profile")
    func detectsEachPieceForBothLanguages() async {
        let (pipeline, speech) = await pipeline(
            detecting: [.hindi, .english, .english],
            profile: UserProfile(preferredLanguages: [.english, .hindi]))

        await pipeline.startRecording()
        await pipeline.finishRecording()
        let hints = await speech.hints

        #expect(hints.count > 1)
        #expect(hints.allSatisfy { $0 == nil })
    }

    /// Issue 699: a short Hindi reply was detected as English words.
    @Test("decodes every piece as Hindi for a speaker of Hindi alone")
    func pinsHindiAlone() async {
        let (pipeline, speech) = await pipeline(
            detecting: [.english, .english, .english], profile: UserProfile(preferredLanguages: [.hindi]))

        await pipeline.startRecording()
        await pipeline.finishRecording()
        let hints = await speech.hints

        #expect(hints.count > 1)
        #expect(hints.allSatisfy { $0 == .hindi })
    }

    @Test("listens by the languages adopted since it was built, from the next dictation on")
    func adoptsTheProfile() async {
        let (pipeline, speech) = await pipeline(detecting: [.english, .hindi, .hindi, .hindi, .hindi, .hindi])

        await pipeline.adopt(profile: UserProfile(preferredLanguages: [.hindi]))
        await pipeline.startRecording()
        await pipeline.finishRecording()
        let hints = await speech.hints

        #expect(!hints.isEmpty)
        #expect(hints.allSatisfy { $0 == .hindi })
    }

    /// Issue 786: a change made while speaking re-hinted the pieces still to come under the new languages.
    @Test("keeps a recording on the languages it began with, and adopts a change from the next")
    func profileChangedMidRecordingWaits() async {
        // No early pieces, so every piece is recognised after the change and none could escape it.
        let (pipeline, speech) = await pipeline(
            detecting: [.english, .english, .english, .english, .english, .english],
            earlyPoll: .seconds(60))

        await pipeline.startRecording()
        await pipeline.adopt(profile: UserProfile(preferredLanguages: [.hindi]))
        await pipeline.finishRecording()
        let first = await speech.hints

        #expect(first.count > 1, "a recording of several pieces")
        #expect(first.first == .some(nil), "the English profile detects the first piece")
        #expect(first.dropFirst().allSatisfy { $0 == nil }, "the original profile detects every piece")

        await pipeline.startRecording()
        await pipeline.finishRecording()
        let next = await speech.hints.dropFirst(first.count)

        #expect(!next.isEmpty)
        #expect(next.allSatisfy { $0 == .hindi }, "the next dictation listens by the new languages")
    }

    /// Issue 1519: a cancelled piece still in the recogniser set the next dictation's language when it returned.
    @Test("a cancelled dictation's piece in flight does not set the next dictation's language")
    func cancelledPieceDoesNotHintTheNext() async throws {
        // The first decode is held and answers Hindi; every later one answers English.
        let session = await ScenarioDriver.session(
            Scenario(
                pieces: pieces(detecting: [.hindi] + Array(repeating: .english, count: 8)),
                context: .fixture(),
                cleaner: FakeTranscriptCleaner(producedBy: .foundationModels),
                profile: UserProfile(preferredLanguages: [.english]), take: threePieces, heldPiece: 0))
        let (pipeline, speech) = (session.pipeline, session.speech)

        await pipeline.startRecording()
        try await eventually { await speech.hints.count == 1 }
        await pipeline.cancel()
        // A start is refused while the abandoned decode is still in the recogniser, so the next one waits for it.
        await speech.release()
        try await eventually { await !speech.answered.isEmpty }
        for _ in 0..<50 { await Task.yield() }
        await pipeline.startRecording()
        await pipeline.finishRecording()
        let later = await speech.hints.dropFirst(2)

        #expect(!later.isEmpty)
        #expect(later.allSatisfy { $0 != .hindi }, "the abandoned piece's language is not hinted")
    }
}
