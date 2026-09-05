import Foundation
import Testing

@testable import UttrflowEval

/// Tested against real temporary directories, since a fake would agree with whatever this code did.
@Suite("Recorded corpus store")
struct TranscriptionCorpusStoreTests {
    private func temporaryDirectory() -> URL {
        URL(fileURLWithPath: NSTemporaryDirectory())
            .appending(path: "uttrflow-eval-tests/\(UUID().uuidString)")
    }

    private func passage(_ id: String) -> TranscriptionCase {
        TranscriptionCase(
            id: id, language: .english, stressor: .everyday, romanised: "the build passed ship it")
    }

    private func recorded(_ passage: TranscriptionCase, seconds: Double = 4) -> RecordedPassage {
        RecordedPassage(
            passage: passage, recordedAt: Date(timeIntervalSince1970: 1_700_000_000),
            durationSeconds: seconds, sampleRate: 16_000)
    }

    @Test("writes the audio, the metadata and a readable copy of the passage")
    func savesThreeFiles() throws {
        let directory = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = TranscriptionCorpusStore(directory: directory)

        try store.save(recorded(passage("one")), audio: Data([1, 2, 3]))

        #expect(store.isRecorded("one"))
        #expect(try Data(contentsOf: store.audioURL(for: "one")) == Data([1, 2, 3]))
        let text = try String(contentsOf: directory.appending(path: "one.txt"), encoding: .utf8)
        #expect(text == "the build passed ship it")
        #expect(try store.all().map(\.id) == ["one"])
        #expect(try store.all().first?.durationSeconds == 4)
    }

    /// The whole reason the session is resumable.
    @Test("knows what is still to be read")
    func resumes() throws {
        let directory = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = TranscriptionCorpusStore(directory: directory)
        let corpus = ["one", "two", "three"].map(passage)

        #expect(store.remaining(from: corpus).map(\.id) == ["one", "two", "three"])
        try store.save(recorded(corpus[0]), audio: Data())
        #expect(store.remaining(from: corpus).map(\.id) == ["two", "three"])
        #expect(!store.isRecorded("two"))
    }

    @Test("reads back nothing from a directory that does not exist yet")
    func emptyStore() throws {
        let store = TranscriptionCorpusStore(directory: temporaryDirectory())
        #expect(try store.all().isEmpty)
        #expect(store.remaining(from: [passage("one")]).count == 1)
        #expect(try store.drifted(from: [passage("one")]).isEmpty)
    }

    /// Anything the corpus has dropped is kept and put last, because a person still read it aloud.
    @Test("returns recordings in corpus order, retired passages last")
    func ordering() throws {
        let directory = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = TranscriptionCorpusStore(directory: directory)
        let corpus = ["one", "two"].map(passage)
        for id in ["two", "one", "retired"] {
            try store.save(recorded(passage(id)), audio: Data())
        }
        #expect(try store.all(ordering: corpus).map(\.id) == ["one", "two", "retired"])
    }

    /// The recording is the truth about what was said; an edited passage is a prompt to re-record.
    @Test("notices a passage that was edited after it was read")
    func drift() throws {
        let directory = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = TranscriptionCorpusStore(directory: directory)
        try store.save(recorded(passage("one")), audio: Data())

        let edited = TranscriptionCase(
            id: "one", language: .english, stressor: .everyday, romanised: "something else entirely")
        #expect(try store.drifted(from: [edited]).map(\.id) == ["one"])
        #expect(try store.drifted(from: [passage("one")]).isEmpty)
        // A recording of a passage nobody has any more has not drifted; it has retired.
        #expect(try store.drifted(from: []).isEmpty)
    }

    @Test("keeps the passage as it was read, not just its id")
    func keepsTheText() throws {
        let directory = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = TranscriptionCorpusStore(directory: directory)
        try store.save(recorded(passage("one")), audio: Data())
        #expect(try store.all().first?.passage.romanised == "the build passed ship it")
    }

    @Test("puts the corpus somewhere obviously derived by default")
    func defaultLocation() {
        #expect(TranscriptionCorpusStore.defaultDirectoryName.hasPrefix("."))
    }
}

@Suite("JSON record store")
struct JSONRecordStoreTests {
    private func temporaryDirectory() -> URL {
        URL(fileURLWithPath: NSTemporaryDirectory())
            .appending(path: "uttrflow-eval-tests/\(UUID().uuidString)")
    }

    private func score(_ id: String) -> PassageScore {
        PassageScore(
            caseID: id, language: .english, stressor: .everyday,
            wordErrorRate: .measure(reference: ["a", "b"], hypothesis: ["a"]),
            answeredIn: .latin, scoredAgainst: .latin)
    }

    @Test("round-trips a record through disk")
    func roundTrip() throws {
        let directory = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = JSONRecordStore<PassageScore>(directory: directory)

        try store.save(score("one"))
        let read = try store.all()
        #expect(read.count == 1)
        #expect(read.first?.wordErrorRate?.deletions == 1)
        #expect(store.contains("one"))
        #expect(!store.contains("two"))
    }

    /// Records are written atomically, so a file that will not decode has been edited or truncated.
    @Test("raises a file it cannot decode instead of skipping it")
    func corruptRecord() throws {
        let directory = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = JSONRecordStore<PassageScore>(directory: directory)
        try store.save(score("one"))
        try Data("not json".utf8).write(to: store.url(for: "broken", extension: "json"))

        #expect(throws: EvaluationStoreError.self) { try store.all() }
    }

    @Test("ignores files that are not records")
    func ignoresOtherFiles() throws {
        let directory = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = JSONRecordStore<PassageScore>(directory: directory)
        try store.save(score("one"))
        try store.write(Data([0]), for: "one", extension: "wav")
        #expect(try store.all().count == 1)
    }

    @Test("says what it could not write, and where")
    func writeFailure() throws {
        // A directory cannot be created inside a file, so this is a write that must fail.
        let file = URL(fileURLWithPath: NSTemporaryDirectory()).appending(path: UUID().uuidString)
        try Data().write(to: file)
        defer { try? FileManager.default.removeItem(at: file) }
        let store = JSONRecordStore<PassageScore>(directory: file.appending(path: "inside"))

        #expect(throws: EvaluationStoreError.self) { try store.save(score("one")) }
        #expect(
            EvaluationStoreError.couldNotWrite(path: "one.json", reason: "full").description
                == "could not write one.json: full")
        #expect(
            EvaluationStoreError.couldNotRead(path: "one.json", reason: "gone").description
                == "could not read one.json: gone")
    }
}
