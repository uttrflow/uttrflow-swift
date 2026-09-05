public import Foundation

/// One passage as read, carrying the whole case so a reworded passage never scores old audio.
public struct RecordedPassage: Sendable, Equatable, Codable, Identifiable {
    public var id: String { passage.id }
    public let passage: TranscriptionCase
    public let recordedAt: Date
    /// Length of the recording, so a report can say how much speech a score rests on.
    public let durationSeconds: Double
    public let sampleRate: Int
    /// Who read it and in what conditions; optional so older single-speaker recordings still decode.
    public let cohort: RecordingCohort?

    public init(
        passage: TranscriptionCase,
        recordedAt: Date,
        durationSeconds: Double,
        sampleRate: Int,
        cohort: RecordingCohort? = nil
    ) {
        self.passage = passage
        self.recordedAt = recordedAt
        self.durationSeconds = durationSeconds
        self.sampleRate = sampleRate
        self.cohort = cohort
    }
}

/// The recorded corpus on disk: `<id>.json` for the harness, `<id>.wav`, and `<id>.txt` for people.
public struct TranscriptionCorpusStore: Sendable {
    /// Where a corpus lives by default: beside the results and hidden, as a build artefact.
    public static let defaultDirectoryName = ".uttrflow-corpus"

    private let store: JSONRecordStore<RecordedPassage>

    public init(directory: URL) {
        store = JSONRecordStore(directory: directory)
    }

    public var directory: URL { store.directory }

    public func audioURL(for id: String) -> URL { store.url(for: id, extension: "wav") }

    /// Writes one take, audio first, so a crash leaves an unrecorded passage rather than a dangling record.
    public func save(_ recorded: RecordedPassage, audio: Data) throws(EvaluationStoreError) {
        try store.write(audio, for: recorded.id, extension: "wav")
        try store.write(Data(recorded.passage.prompt.utf8), for: recorded.id, extension: "txt")
        try store.save(recorded)
    }

    /// Everything recorded in corpus order, with passages the corpus dropped sorted to the end, not lost.
    public func all(
        ordering corpus: [TranscriptionCase] = TranscriptionCorpus.all
    ) throws(EvaluationStoreError) -> [RecordedPassage] {
        TranscriptionCorpus.inCorpusOrder(try store.all(), corpus: corpus)
    }

    public func isRecorded(_ id: String) -> Bool { store.contains(id) }

    /// What the operator still has to read, which is what makes a session resumable.
    public func remaining(
        from corpus: [TranscriptionCase] = TranscriptionCorpus.all
    )
        -> [TranscriptionCase]
    {
        corpus.filter { !isRecorded($0.id) }
    }

    /// Recordings whose passage text has changed since the take; a prompt to re-record, not an error.
    public func drifted(
        from corpus: [TranscriptionCase] = TranscriptionCorpus.all
    ) throws(EvaluationStoreError) -> [RecordedPassage] {
        let current = Dictionary(uniqueKeysWithValues: corpus.map { ($0.id, $0) })
        return try all(ordering: corpus).filter { recorded in
            guard let live = current[recorded.id] else { return false }
            return live != recorded.passage
        }
    }
}
