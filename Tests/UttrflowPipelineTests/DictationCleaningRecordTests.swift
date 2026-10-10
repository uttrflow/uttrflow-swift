import Foundation
import Synchronization
import Testing

@testable import UttrflowCore
import UttrflowDictionary
@testable import UttrflowPipeline
@testable import UttrflowTestSupport

/// A recogniser that hears the same words every time, so the tidier's account is the variable.
private struct FixedSpeechEngine: SpeechEngine {
    let kind = SpeechEngineKind.whisperKit
    let heard: String

    func prepare() async throws(SpeechEngineError) {}

    func transcribe(
        _ audio: AudioSamples, options: TranscriptionOptions
    ) async throws(SpeechEngineError) -> Transcription {
        Transcription(text: heard, audioDuration: audio.duration)
    }
}

/// A tidier that reports whatever account it is told to, so the seam can be tested without a model.
private struct AccountingCleaner: TranscriptCleaning {
    let record: CleaningRecord?

    func clean(
        _ request: TransformationRequest
    ) async throws(TransformationError)
        -> TransformationResult
    {
        TransformationResult(
            text: request.transcription.text, producedBy: .rules, cleaning: record)
    }
}

/// A tidier that refuses, so the words survive but no account is made.
private struct RefusingCleaner: TranscriptCleaning {
    func clean(
        _ request: TransformationRequest
    ) async throws(TransformationError)
        -> TransformationResult
    {
        throw .outputRejected(reason: "scripted", kind: .lostWord)
    }
}

/// Keeps what the pipeline reported, in the order it reported it.
actor CollectingCleaningRecorder: CleaningRecording {
    private(set) var records: [CleaningRecord] = []

    func record(_ record: CleaningRecord) async {
        records.append(record)
    }
}

/// The situation each request was resolved against, so an override can be seen to have landed.
private final class WatchingCleaner: TranscriptCleaning, Sendable {
    private let seen = Mutex<[UttrflowCore.Destination]>([])

    func clean(
        _ request: TransformationRequest
    ) async throws(TransformationError)
        -> TransformationResult
    {
        seen.withLock { $0.append(request.situation.destination) }
        return TransformationResult(text: request.transcription.text, producedBy: .rules)
    }

    var destinations: [UttrflowCore.Destination] { seen.withLock { $0 } }
}

@Suite("The pipeline hands on what the clean-up steps did")
struct DictationCleaningRecordTests {
    private static let audio = AudioSamples.canonical(
        (0..<24_000).map { 0.3 * Float(sin(Double($0) * 0.07)) })

    private func pipeline(
        cleaner: any TranscriptCleaning,
        recorder: any CleaningRecording = NoOpCleaningRecorder(),
        overrides: DestinationOverrides = .none,
        context: AppContext = .fixture()
    ) -> DictationPipeline {
        DictationPipeline(
            capture: FakeAudioCaptureEngine(stopOutcome: .success(Self.audio)),
            speech: FixedSpeechEngine(heard: "um we ship"),
            cleaner: cleaner,
            context: FakeContextEngine(context: context),
            inserter: FakeTextInserter(),
            cleaningRecorder: recorder,
            destinationOverrides: overrides)
    }

    private let account = CleaningRecord(
        changes: [CleaningRecord.Change(step: .fillers, removed: ["um"])], switchedOff: [.spacing])

    @Test("a finished dictation reports what each step did, once")
    func reportsOnce() async {
        let recorder = CollectingCleaningRecorder()
        let pipeline = pipeline(
            cleaner: AccountingCleaner(record: account), recorder: recorder)

        await pipeline.startRecording()
        await pipeline.finishRecording()

        let records = await recorder.records
        #expect(records.count == 1)
        #expect(records.first?.changes.first?.removed == ["um"])
        #expect(records.first?.switchedOff == [.spacing])
    }

    @Test("the report names the dictionary revision every piece was corrected against")
    func carriesTheDictionaryRevision() async {
        let index = PhoneticIndex(entries: [
            DictionaryEntry(
                word: "Zorvex", pronunciation: "sore vex", origin: .added, firstSeen: .distantPast)
        ])
        let recorder = CollectingCleaningRecorder()
        let pipeline = DictationPipeline(
            capture: FakeAudioCaptureEngine(stopOutcome: .success(Self.audio)),
            speech: FixedSpeechEngine(heard: "um we ship"),
            cleaner: AccountingCleaner(record: account),
            context: FakeContextEngine(context: .fixture()),
            inserter: FakeTextInserter(),
            corrector: DictionaryCorrections { _ in index },
            cleaningRecorder: recorder)

        await pipeline.startRecording()
        await pipeline.finishRecording()

        #expect(await recorder.records.first?.dictionaryRevision == index.revision)
    }

    @Test("cleanup is reported as cleaning, not an undoable correction")
    func cleanupDoesNotBecomeCorrection() async throws {
        let recorder = CollectingCleaningRecorder()
        let pipeline = pipeline(
            cleaner: AccountingCleaner(record: account), recorder: recorder)

        await pipeline.startRecording()
        await pipeline.finishRecording()

        guard case .inserted(let outcome) = await pipeline.currentState else {
            Issue.record("dictation did not finish inserted")
            return
        }
        #expect(outcome.changes.corrections.isEmpty)
        #expect(outcome.changes.snippets.isEmpty)
        #expect(outcome.changes.entriesTaken.isEmpty)
        #expect(await recorder.records.first?.changes.first?.step == .fillers)
    }

    @Test("a tidier that keeps no account leaves the page with nothing to redraw")
    func noAccount() async {
        let recorder = CollectingCleaningRecorder()
        let pipeline = pipeline(cleaner: AccountingCleaner(record: nil), recorder: recorder)

        await pipeline.startRecording()
        await pipeline.finishRecording()

        #expect(await recorder.records.isEmpty)
    }

    /// The words pass through untidied, and the account says the tidying gave up rather than standing empty.
    @Test("a tidier that refuses reports the tidying skipped rather than an empty account")
    func refusedTidying() async {
        let recorder = CollectingCleaningRecorder()
        let pipeline = pipeline(cleaner: RefusingCleaner(), recorder: recorder)

        await pipeline.startRecording()
        await pipeline.finishRecording()

        #expect(await recorder.records == [.skipped(.tidy, .error)])
    }

    @Test("the app the user overrode is tidied for the place they said it was")
    func overrideReachesTheTidier() async {
        let cleaner = WatchingCleaner()
        let slack = AppContext(
            applicationName: "Slack", bundleIdentifier: "com.tinyspeck.slackmacgap")
        let overrides = DestinationOverrides.none.setting(
            .document, for: "com.tinyspeck.slackmacgap", named: "Slack")
        let pipeline = pipeline(cleaner: cleaner, overrides: overrides, context: slack)

        await pipeline.startRecording()
        await pipeline.finishRecording()

        #expect(cleaner.destinations.allSatisfy { $0 == .document })
        #expect(!cleaner.destinations.isEmpty)
    }

    /// A control that appears to change nothing is the one kind this product refuses to draw.
    @Test("a choice made in Settings reaches the next dictation, not the next launch")
    func adoptsNewChoices() async {
        let cleaner = WatchingCleaner()
        let slack = AppContext(
            applicationName: "Slack", bundleIdentifier: "com.tinyspeck.slackmacgap")
        let pipeline = pipeline(cleaner: AccountingCleaner(record: nil), context: slack)

        await pipeline.adopt(
            cleaner: cleaner,
            destinationOverrides: DestinationOverrides.none.setting(
                .document, for: "com.tinyspeck.slackmacgap", named: "Slack"))
        await pipeline.startRecording()
        await pipeline.finishRecording()

        #expect(cleaner.destinations == [.document])
    }

    @Test("with no override the table still decides")
    func tableStillDecides() async {
        let cleaner = WatchingCleaner()
        let slack = AppContext(
            applicationName: "Slack", bundleIdentifier: "com.tinyspeck.slackmacgap")
        let pipeline = pipeline(cleaner: cleaner, context: slack)

        await pipeline.startRecording()
        await pipeline.finishRecording()

        #expect(cleaner.destinations.allSatisfy { $0 == .messaging })
    }
}
