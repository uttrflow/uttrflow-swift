public import Foundation

/// What happened the last time this recording was offered to the corpus service.
public struct UploadReceipt: Sendable, Equatable, Codable, Identifiable {
    /// What happened, and — the part that matters — whether asking again could help.
    public enum Outcome: Sendable, Equatable, Codable {
        /// The bytes are in the bucket and the row is in the catalogue.
        case uploaded
        /// A connection, a timeout, a five-hundred. Retried on the next sitting without
        /// anybody being asked to do anything.
        case heldBack(String)
        /// The backend refused it, or it was never valid. Retrying would fail the same
        /// way for ever, so this one needs a person and says so.
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

/// Sends recorded passages to the corpus service, and keeps the ones it could not send.
///
/// The property the whole recording session rests on: **the local write is the commit.**
/// `record` saves the audio to disk the moment the operator accepts a take, and only
/// then offers it here. Nothing in this type can lose a recording, because nothing in
/// this type is where the recording lives — the outbox is derived state, computed as
/// "everything on disk that has no settled receipt". A crash, a dead Wi-Fi, a backend
/// that has not shipped the upload endpoint yet: all of them leave the take on disk and
/// the outbox non-empty, and the next `record --sync` picks up exactly where this one
/// stopped.
///
/// That is also why there is no queue file. A queue is a second copy of the truth, and
/// the interesting failure — the process dying between writing the audio and writing the
/// queue entry — is precisely the one it would introduce.
public struct CorpusUploadOutbox: Sendable {
    /// Receipts live under the corpus directory rather than beside the recordings,
    /// because ``JSONRecordStore`` names files by id and `<id>.json` is already taken by
    /// the recording itself.
    public static let receiptsDirectoryName = "uploads"

    private let recordings: TranscriptionCorpusStore
    private let receipts: JSONRecordStore<UploadReceipt>
    private let uploader: any CorpusUploading
    private let cohort: RecordingCohort?
    /// Injected so a test does not have to wait for a clock, and so every receipt from
    /// one sitting can share a timestamp when that is what the caller wants.
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

    /// Everything recorded that the corpus service has not accepted.
    ///
    /// Rejected takes are included. They will fail again, and they should: an upload the
    /// backend refuses is a corpus that is quietly smaller than the operator believes,
    /// and the only thing worse than seeing it in the list every session is not seeing it.
    public func pending() throws(EvaluationStoreError) -> [RecordedPassage] {
        let settled = Set(try receipts.all().filter(\.outcome.isSettled).map(\.passageID))
        return try recordings.all().filter { !settled.contains($0.id) }
    }

    /// Offers one recording to the corpus service and writes down what happened.
    ///
    /// Never throws. A recording session must not end because an upload did, and the
    /// caller has a receipt to print either way.
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
            // The recording is missing from the very directory that is supposed to hold
            // it, so no number of retries will find it. Rejected, and named.
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
        /// Whether anything still needs sending. The number `record --sync` prints, and
        /// the reason an operator can walk away from a sitting without checking.
        public var outstanding: Int { heldBack.count + rejected.count }
    }

    /// Sends everything outstanding, in one go.
    ///
    /// Stops early on the first held-back upload rather than grinding through nine
    /// hundred more against a backend that is plainly down: the recordings are safe on
    /// disk, and a session that spends twenty minutes timing out is a session the
    /// operator learns to skip. A rejection is not a reason to stop — it is about one
    /// sample, and the rest may be perfectly fine.
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
                // Everything left is still on disk and still pending, so this is a pause
                // rather than a loss.
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

    /// The catalogue row for a recording.
    ///
    /// `expectedTidiedText` is the passage as read. The column is what a correct clean-up
    /// should produce and this harness does not know that — measuring it is the
    /// transformation half's job, over a corpus written for it — so the honest value is
    /// the reference itself, which scores clean-up as "changed nothing" rather than
    /// inventing a target nobody agreed.
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

    /// A BCP-47 tag the catalogue's `language_tag` domain accepts.
    ///
    /// Hinglish files under `hi-IN`, because BCP-47 has no tag for it and inventing one
    /// would be refused by the CHECK constraint. Nothing is lost: the `code-switching`
    /// stress is what marks it, and ``CorpusSample/spokenLanguage`` reads it back out.
    private func tag(for language: TranscriptionCase.Language) -> String {
        switch language {
        case .english: "en-IN"
        case .hindi, .hinglish: "hi-IN"
        }
    }

    private func write(_ receipt: UploadReceipt) -> UploadReceipt {
        // A receipt that cannot be written is not worth failing an upload over: the
        // consequence is that the next run offers this recording again, and the backend
        // upserts by slug, so the worst case is one repeated transfer.
        try? receipts.save(receipt)
        return receipt
    }
}
