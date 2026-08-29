public import Foundation

/// One passage as it was actually read, on the day it was read.
///
/// Carries the whole ``TranscriptionCase`` rather than only its id, deliberately. The
/// recording is the expensive half of this harness and will outlive several edits to the
/// corpus; if a passage were later reworded, an id alone would silently score old audio
/// against new words. Holding the text that was in front of the operator keeps every
/// recording interpretable, and lets ``TranscriptionCorpusStore/drifted(from:)`` say
/// which ones have fallen behind instead of quietly mis-scoring them.
public struct RecordedPassage: Sendable, Equatable, Codable, Identifiable {
    public var id: String { passage.id }
    public let passage: TranscriptionCase
    public let recordedAt: Date
    /// Length of the recording. Kept so the harness can report how much speech a score
    /// rests on without opening every file.
    public let durationSeconds: Double
    public let sampleRate: Int
    /// Who read it and in what conditions.
    ///
    /// Optional so that recordings made before the corpus grew past one speaker in one
    /// room still decode — they are reported as unattributed, which is what they are.
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

/// The recorded corpus on disk: three files per passage, sharing one id.
///
/// `<id>.json` is what the harness reads, `<id>.wav` is the audio, and `<id>.txt` is the
/// passage as the operator saw it — written for the person who opens the folder in six
/// months and wants to know what they were listening to, without running anything.
public struct TranscriptionCorpusStore: Sendable {
    /// Where a corpus lives unless the operator says otherwise. Beside the results, and
    /// hidden, because it is a build artefact of a reading session rather than source.
    public static let defaultDirectoryName = ".uttrflow-corpus"

    private let store: JSONRecordStore<RecordedPassage>

    public init(directory: URL) {
        store = JSONRecordStore(directory: directory)
    }

    public var directory: URL { store.directory }

    public func audioURL(for id: String) -> URL { store.url(for: id, extension: "wav") }

    /// Writes one finished take. Audio first, so a crash between the two leaves a
    /// recording with no record of itself — which the next run treats as not yet
    /// recorded — rather than a record pointing at a file that is not there.
    public func save(_ recorded: RecordedPassage, audio: Data) throws(EvaluationStoreError) {
        try store.write(audio, for: recorded.id, extension: "wav")
        try store.write(Data(recorded.passage.prompt.utf8), for: recorded.id, extension: "txt")
        try store.save(recorded)
    }

    /// Everything recorded, in corpus order so a report reads down the page the way the
    /// session ran. Anything no longer in the corpus sorts to the end rather than being
    /// dropped: it was still read aloud by a person, and the harness should say so.
    public func all(
        ordering corpus: [TranscriptionCase] = TranscriptionCorpus.all
    ) throws(EvaluationStoreError) -> [RecordedPassage] {
        let position = Dictionary(uniqueKeysWithValues: corpus.enumerated().map { ($1.id, $0) })
        return try store.all().sorted {
            (position[$0.id] ?? corpus.count, $0.id) < (position[$1.id] ?? corpus.count, $1.id)
        }
    }

    public func isRecorded(_ id: String) -> Bool { store.contains(id) }

    /// What the operator still has to read. The whole reason the session is resumable:
    /// somebody who stops after five passages comes back to thirteen, not to eighteen.
    public func remaining(
        from corpus: [TranscriptionCase] = TranscriptionCorpus.all
    )
        -> [TranscriptionCase]
    {
        corpus.filter { !isRecorded($0.id) }
    }

    /// Recordings whose passage has been edited since it was read aloud.
    ///
    /// Not an error and not repaired automatically — the audio is still the truth about
    /// what was said, and the stored text still matches it. It is a prompt to re-record
    /// that passage when convenient, and a warning that its score answers a slightly
    /// older question than the rest.
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
