// Sends recorded passages to the corpus service and keeps receipts for the ones it could not.
public import Foundation

/// What happened the last time this recording was offered to the corpus service.
public struct UploadReceipt: Sendable, Equatable, Codable, Identifiable {
    /// What happened, and — the part that matters — whether asking again could help.
    public enum Outcome: Sendable, Equatable, Codable {
        /// The bytes are in the bucket and the row is in the catalogue.
        case uploaded
        /// A connection, a timeout, a five-hundred: retried on the next sitting without anybody being asked.
        case heldBack(String)
        /// The backend refuses it, so retrying fails the same way for ever and a person is needed.
        case rejected(String)

        public var isSettled: Bool { self == .uploaded }

        public var detail: String? {
            switch self {
            case .uploaded: nil
            case .heldBack(let reason), .rejected(let reason): reason
            }
        }
    }

    public var id: String { passageID }
    public let passageID: String
    public let slug: String
    public let attempts: Int
    public let lastAttemptAt: Date
    public let outcome: Outcome

    public init(passageID: String, slug: String, attempts: Int, lastAttemptAt: Date, outcome: Outcome) {
        self.passageID = passageID
        self.slug = slug
        self.attempts = attempts
        self.lastAttemptAt = lastAttemptAt
        self.outcome = outcome
    }
}

/// Sends recorded passages to the corpus service; the outbox is "on disk with no settled receipt".
public struct CorpusUploadOutbox: Sendable {
    /// Receipts live under their own directory because `<id>.json` beside a recording is the recording.
    public static let receiptsDirectoryName = "uploads"

    private let recordings: TranscriptionCorpusStore
    private let receipts: JSONRecordStore<UploadReceipt>
    private let uploader: any CorpusUploading
    private let cohort: RecordingCohort?
    /// Injected so tests need no clock and a sitting's receipts can share one timestamp.
    private let now: @Sendable () -> Date

    public init(
        recordings: TranscriptionCorpusStore,
        uploader: any CorpusUploading,
        cohort: RecordingCohort? = nil,
        receiptsDirectory: URL? = nil,
        now: @escaping @Sendable () -> Date = Date.init
    ) {
        self.recordings = recordings
        self.uploader = uploader
        self.cohort = cohort
        self.now = now
        receipts = JSONRecordStore(
            directory: receiptsDirectory
                ?? recordings.directory.appending(path: Self.receiptsDirectoryName))
    }

    public func receipt(for passageID: String) throws(EvaluationStoreError) -> UploadReceipt? {
        try receipts.all().first { $0.passageID == passageID }
    }

    public func allReceipts() throws(EvaluationStoreError) -> [UploadReceipt] {
        try receipts.all().sorted { $0.passageID < $1.passageID }
    }

    /// Everything recorded that the corpus service has not accepted, rejected takes included.
    public func pending() throws(EvaluationStoreError) -> [RecordedPassage] {
        let settled = Set(try receipts.all().filter(\.outcome.isSettled).map(\.passageID))
        return try recordings.all().filter { !settled.contains($0.id) }
    }

    /// Offers one recording to the corpus service and writes a receipt; never throws.
    public func send(_ recording: RecordedPassage) async -> UploadReceipt {
        let previous = try? receipt(for: recording.id)
        let attempts = (previous?.attempts ?? 0) + 1
        let slug = CorpusSlug.make(passage: recording.id, cohort: recording.cohort?.id ?? cohort?.id)

        /// This attempt's receipt, written down as it is handed back.
        func record(_ outcome: UploadReceipt.Outcome) -> UploadReceipt {
            write(
                UploadReceipt(
                    passageID: recording.id, slug: slug, attempts: attempts, lastAttemptAt: now(),
                    outcome: outcome))
        }

        guard CorpusSlug.isValid(slug) else {
            return record(
                .rejected(
                    "'\(slug)' is not a name the catalogue accepts — two to sixty-four "
                        + "lowercase letters, digits and hyphens"))
        }

        let audio: Data
        do {
            audio = try Data(contentsOf: recordings.audioURL(for: recording.id))
        } catch {
            // The recording is missing from its own directory, so no retry will find it.
            return record(.rejected("could not read \(recording.id).wav: \(error)"))
        }

        do {
            let grant = try await uploader.register(sample(for: recording, slug: slug, bytes: audio.count))
            try await uploader.upload(audio, to: grant)
            return record(.uploaded)
        } catch {
            return record(error.isTransient ? .heldBack("\(error)") : .rejected("\(error)"))
        }
    }

    /// What one sitting's worth of uploads came to.
    public struct Summary: Sendable, Equatable {
        public let uploaded: [String]
        public let heldBack: [UploadReceipt]
        public let rejected: [UploadReceipt]

        public init(uploaded: [String], heldBack: [UploadReceipt], rejected: [UploadReceipt]) {
            self.uploaded = uploaded
            self.heldBack = heldBack
            self.rejected = rejected
        }

        public var isEmpty: Bool { uploaded.isEmpty && heldBack.isEmpty && rejected.isEmpty }
        /// How many recordings still need sending; the number `record --sync` prints.
        public var outstanding: Int { heldBack.count + rejected.count }
    }

    /// Sends everything outstanding, stopping at the first held-back upload since the backend is down.
    public func flush(
        onProgress: (@Sendable (UploadReceipt) -> Void)? = nil
    ) async throws(EvaluationStoreError) -> Summary {
        var uploaded: [String] = []
        var heldBack: [UploadReceipt] = []
        var rejected: [UploadReceipt] = []
        var outstanding = try pending()

        while !outstanding.isEmpty {
            let recording = outstanding.removeFirst()
            let receipt = await send(recording)
            onProgress?(receipt)
            switch receipt.outcome {
            case .uploaded: uploaded.append(receipt.passageID)
            case .rejected: rejected.append(receipt)
            case .heldBack:
                heldBack.append(receipt)
                // Everything left is still on disk and still pending, so this is a pause rather than a loss.
                heldBack.append(
                    contentsOf: outstanding.map {
                        UploadReceipt(
                            passageID: $0.id,
                            slug: CorpusSlug.make(passage: $0.id, cohort: $0.cohort?.id ?? cohort?.id),
                            attempts: 0, lastAttemptAt: receipt.lastAttemptAt,
                            outcome: .heldBack("not attempted — the previous upload was held back"))
                    })
                outstanding = []
            }
        }
        return Summary(uploaded: uploaded, heldBack: heldBack, rejected: rejected)
    }

    // MARK: Describing a recording to the catalogue

    /// The catalogue row for a recording; `expectedTidiedText` is the passage as read.
    private func sample(for recording: RecordedPassage, slug: String, bytes: Int) -> CorpusSample {
        let passage = recording.passage
        let language = tag(for: passage.language)
        return CorpusSample(
            id: "",
            slug: slug,
            s3Key: "corpus/\(language)/\(slug).wav",
            referenceText: passage.prompt,
            expectedTidiedText: passage.prompt,
            language: language,
            stresses: passage.stresses,
            durationMs: Int((recording.durationSeconds * 1000).rounded()),
            sampleRateHz: recording.sampleRate,
            byteSize: bytes,
            isHeldOut: false,
            cohort: recording.cohort?.id ?? cohort?.id
        )
    }

    /// A BCP-47 tag the catalogue accepts; Hinglish files under `hi-IN` and the stress marks it.
    private func tag(for language: TranscriptionCase.Language) -> String {
        switch language {
        case .english: "en-IN"
        case .hindi, .hinglish: "hi-IN"
        }
    }

    private func write(_ receipt: UploadReceipt) -> UploadReceipt {
        // A lost receipt only means one repeated transfer, because the backend upserts by slug.
        try? receipts.save(receipt)
        return receipt
    }
}
