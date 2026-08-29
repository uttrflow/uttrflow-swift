import Foundation
import Synchronization
import Testing

@testable import UttrflowEval

@Suite("Sending recordings to the corpus")
struct CorpusUploadOutboxTests {
    private let cohort = RecordingCohort(id: "naveen-quiet", speaker: "naveen", setting: "quiet room")

    private func passage(_ id: String) -> TranscriptionCase {
        TranscriptionCase(
            id: id, language: .hinglish, stressor: .digits, romanised: "meeting bees minute late",
            devanagari: "meeting बीस minute late", mustKeep: ["meeting"])
    }

    private func recorded(_ id: String, cohort: RecordingCohort? = nil) -> RecordedPassage {
        RecordedPassage(
            passage: passage(id), recordedAt: Date(timeIntervalSince1970: 1_700_000_000),
            durationSeconds: 4.25, sampleRate: 16_000, cohort: cohort)
    }

    private func store(
        _ directory: URL, _ ids: [String], cohort: RecordingCohort? = nil
    ) throws
        -> TranscriptionCorpusStore
    {
        let store = TranscriptionCorpusStore(directory: directory)
        for id in ids { try store.save(recorded(id, cohort: cohort), audio: Data([1, 2, 3])) }
        return store
    }

    private func outbox(
        _ store: TranscriptionCorpusStore, _ uploader: any CorpusUploading,
        cohort: RecordingCohort? = nil
    ) -> CorpusUploadOutbox {
        CorpusUploadOutbox(
            recordings: store, uploader: uploader, cohort: cohort,
            now: { Date(timeIntervalSince1970: 1_700_000_100) })
    }

    // MARK: What goes up

    @Test("describes a recording to the catalogue in the shape the backend takes")
    func describesASample() async throws {
        let directory = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let uploader = FakeUploader()
        let recordings = try store(directory, ["hinglish-numbers"], cohort: cohort)

        let receipt = await outbox(recordings, uploader).send(recorded("hinglish-numbers", cohort: cohort))

        #expect(receipt.outcome == .uploaded)
        #expect(receipt.slug == "naveen-quiet-hinglish-numbers")
        #expect(uploader.uploads.first?.audio == Data([1, 2, 3]))
    }

    /// Hinglish has no BCP-47 tag, and the catalogue's `language_tag` domain would refuse
    /// an invented one. It files under Hindi and is marked by the code-switching stress.
    @Test("a Hinglish passage files under hi-IN and keeps its own stresses")
    func languageTags() async throws {
        let directory = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let recordings = TranscriptionCorpusStore(directory: directory)
        let english = RecordedPassage(
            passage: TranscriptionCase(
                id: "en-one", language: .english, stressor: .everyday, romanised: "ship it"),
            recordedAt: Date(), durationSeconds: 1, sampleRate: 16_000)
        try recordings.save(english, audio: Data([1]))
        try recordings.save(recorded("hinglish-numbers"), audio: Data([1]))

        let uploader = FakeUploader()
        _ = try await outbox(recordings, uploader).flush()

        let byLanguage = Dictionary(
            uniqueKeysWithValues: uploader.uploads.map { ($0.sample.slug, $0.sample.s3Key) })
        #expect(byLanguage["en-one"]?.contains("en-IN") == true)
        #expect(byLanguage["hinglish-numbers"]?.contains("hi-IN") == true)
    }

    // MARK: Surviving failure

    /// The property the whole recording session rests on.
    @Test("a failed upload leaves the take on disk and in the queue")
    func aFailedUploadKeepsTheTake() async throws {
        let directory = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let recordings = try store(directory, ["one"])
        let failing = FakeUploader(registerResult: .failure(.unreachable("no wifi")))

        let receipt = await outbox(recordings, failing).send(recorded("one"))
        #expect(receipt.outcome == .heldBack("could not reach the corpus service: no wifi"))
        // Still on disk, and still outstanding.
        #expect(try recordings.all().map(\.id) == ["one"])
        #expect(try outbox(recordings, failing).pending().map(\.id) == ["one"])

        // And the next sitting, with a connection, sends it.
        let working = FakeUploader()
        #expect(await outbox(recordings, working).send(recorded("one")).outcome == .uploaded)
        #expect(try outbox(recordings, working).pending().isEmpty)
    }

    @Test("an upload that fails after registering is retried whole")
    func retriesAfterAFailedTransfer() async throws {
        let directory = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let recordings = try store(directory, ["one"])
        let broken = FakeUploader(uploadError: .unreachable("dropped"))

        #expect(await outbox(recordings, broken).send(recorded("one")).outcome != .uploaded)
        // Registration upserts by slug, so nothing is duplicated by trying again.
        let receipt = await outbox(recordings, FakeUploader()).send(recorded("one"))
        #expect(receipt.outcome == .uploaded)
        #expect(receipt.attempts == 2)
    }

    /// A rejection is not a reason to keep asking. It is a reason to tell somebody.
    @Test("a refusal the backend will repeat is recorded as needing a person")
    func rejectsWhatCannotSucceed() async throws {
        let directory = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let recordings = try store(directory, ["one"])
        let missing = FakeUploader(registerResult: .failure(.endpointMissing("POST /v1/corpus/samples")))

        let receipt = await outbox(recordings, missing).send(recorded("one"))
        #expect(
            receipt.outcome == .rejected("this backend has no POST /v1/corpus/samples — it needs updating"))
        // Still listed, because a corpus quietly smaller than the operator believes is
        // worse than a line in every summary.
        #expect(try outbox(recordings, missing).pending().map(\.id) == ["one"])
    }

    @Test("a name the catalogue would refuse is caught before anything is sent")
    func refusesABadSlug() async throws {
        let directory = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let long = RecordingCohort(id: String(repeating: "a", count: 64), speaker: "x", setting: "y")
        let recordings = try store(directory, ["one"], cohort: long)
        let uploader = FakeUploader()

        let receipt = await outbox(recordings, uploader).send(recorded("one", cohort: long))
        #expect(receipt.outcome.detail?.contains("not a name the catalogue accepts") == true)
        #expect(uploader.uploads.isEmpty)
    }

    @Test("a recording whose audio has gone is rejected rather than retried for ever")
    func rejectsAMissingRecording() async throws {
        let directory = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let recordings = try store(directory, ["one"])
        try FileManager.default.removeItem(at: recordings.audioURL(for: "one"))

        let receipt = await outbox(recordings, FakeUploader()).send(recorded("one"))
        #expect(receipt.outcome.detail?.contains("could not read one.wav") == true)
    }

    // MARK: A sitting's worth

    @Test("sends everything outstanding and says what is left")
    func flushes() async throws {
        let directory = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let recordings = try store(directory, ["one", "two", "three"])

        let summary = try await outbox(recordings, FakeUploader()).flush()
        #expect(summary.uploaded.sorted() == ["one", "three", "two"])
        #expect(summary.outstanding == 0)
        #expect(!summary.isEmpty)
        #expect(try outbox(recordings, FakeUploader()).pending().isEmpty)
    }

    /// A session that spends twenty minutes timing out against a backend that is plainly
    /// down is a session the operator learns to skip.
    @Test("stops at the first held-back upload and counts the rest as still to go")
    func stopsWhenTheBackendIsDown() async throws {
        let directory = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let recordings = try store(directory, ["one", "two", "three"])
        let offline = FakeUploader(registerResult: .failure(.unreachable("no wifi")))

        let summary = try await outbox(recordings, offline).flush()
        #expect(summary.uploaded.isEmpty)
        #expect(summary.heldBack.count == 3)
        #expect(summary.outstanding == 3)
        #expect(summary.heldBack.dropFirst().allSatisfy { $0.attempts == 0 })
        // Nothing was lost, and everything is still queued for the next attempt.
        #expect(try outbox(recordings, offline).pending().count == 3)
    }

    /// One bad sample is about that sample; the rest of the sitting may be perfectly fine.
    @Test("a rejection does not stop the others going up")
    func carriesOnPastARejection() async throws {
        let directory = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let recordings = try store(directory, ["one", "two"])
        try FileManager.default.removeItem(at: recordings.audioURL(for: "one"))

        let summary = try await outbox(recordings, FakeUploader()).flush()
        #expect(summary.uploaded == ["two"])
        #expect(summary.rejected.map(\.passageID) == ["one"])
    }

    @Test("reports each receipt as it happens")
    func reportsProgress() async throws {
        let directory = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let recordings = try store(directory, ["one", "two"])
        let seen = Mutex<[String]>([])
        _ = try await outbox(recordings, FakeUploader()).flush { receipt in
            seen.withLock { $0.append(receipt.passageID) }
        }
        #expect(seen.withLock { $0 }.sorted() == ["one", "two"])
    }

    @Test("an empty corpus has nothing outstanding")
    func nothingToSend() async throws {
        let directory = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let recordings = TranscriptionCorpusStore(directory: directory)
        let summary = try await outbox(recordings, FakeUploader()).flush()
        #expect(summary.isEmpty)
    }

    @Test("keeps a receipt per recording, readable without a backend")
    func receipts() async throws {
        let directory = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let recordings = try store(directory, ["one", "two"])
        _ = try await outbox(recordings, FakeUploader()).flush()

        let subject = outbox(recordings, FakeUploader())
        #expect(try subject.allReceipts().map(\.passageID) == ["one", "two"])
        #expect(try subject.receipt(for: "one")?.outcome == .uploaded)
        #expect(try subject.receipt(for: "nothing") == nil)
        #expect(UploadReceipt.Outcome.uploaded.detail == nil)
    }

    /// The cohort of the sitting stands in for recordings made before cohorts existed, so
    /// an old corpus can be attributed by uploading it under a name.
    @Test("the sitting's cohort names a recording that has none of its own")
    func fallsBackToTheSittingCohort() async throws {
        let directory = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let recordings = try store(directory, ["one"])
        let uploader = FakeUploader()
        let receipt = await outbox(recordings, uploader, cohort: cohort).send(recorded("one"))
        #expect(receipt.slug == "naveen-quiet-one")
    }
}
