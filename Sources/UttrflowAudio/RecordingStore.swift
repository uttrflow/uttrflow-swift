// Keeps recordings on disk for retry and prunes the old ones.
public import Foundation
public import UttrflowCore

/// The private facts carried beside a recording, with support for the earlier app-only sidecar.
private struct RecordedDestination: Sendable, Codable {
    let app: AppIdentity
    let fieldKind: Destination?

    init(app: AppIdentity, fieldKind: Destination?) {
        self.app = app
        self.fieldKind = fieldKind
    }

    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        if let app = try container.decodeIfPresent(AppIdentity.self, forKey: .app) {
            self.init(
                app: app, fieldKind: try container.decodeIfPresent(Destination.self, forKey: .fieldKind))
        } else {
            // Before field kinds were saved, the sidecar itself was the app's name and bundle.
            self.init(app: try AppIdentity(from: decoder), fieldKind: nil)
        }
    }

    private enum CodingKeys: String, CodingKey {
        case app, fieldKind
    }
}

/// The recordings kept on this Mac, one WAV each, deleted as their words land or go stale.
public actor RecordingStore: RecordingKeeper {
    /// How long a recording that could not become text waits for a retry.
    public static let defaultRetention: Duration = .seconds(24 * 60 * 60)
    /// The most bytes waiting recordings may hold on disk together, so retries bound the folder as well as age does.
    public static let defaultByteLimit = 256 * 1_048_576

    private let directory: URL
    private let retention: Duration
    private let byteLimit: Int
    private let encryptedStore: EncryptedStore?
    /// The writer of the recording under way, whose file is not yet a recording to list.
    private var open: RecordingWriter?
    /// The recording written for the dictation that most recently stopped.
    private var last: KeptRecording?
    /// Destination facts for recordings awaiting retry, keyed by their audio file identifier.
    private var destinations: [UUID: RecordedDestination] = [:]
    /// Writers whose bookkeeping is done and whose last bytes are still on their way to the disk.
    private var settling: [UUID: RecordingWriter] = [:]

    public init(
        directory: URL = RecordingStore.defaultDirectory(),
        retention: Duration = RecordingStore.defaultRetention,
        byteLimit: Int = RecordingStore.defaultByteLimit,
        encryptedStore: EncryptedStore? = nil
    ) {
        self.directory = directory
        self.retention = retention
        self.byteLimit = byteLimit
        self.encryptedStore = encryptedStore
    }

    /// Where this build's recordings live, beside the other stores so a development build never prunes the shipped app's.
    public static func defaultDirectory(
        in container: URL = .applicationSupportDirectory,
        for identifier: String? = Bundle.main.bundleIdentifier
    ) -> URL {
        LocalStoreEntry.recordings.location(in: container, for: identifier)
    }

    // MARK: - Writing

    /// Starts a writer for the recording that is starting, leaving every file-system call to the writer's own task.
    public func begin(at when: Date = Date()) -> RecordingWriter? {
        last = nil
        if let previous = open {
            previous.abandon()
            settling[previous.id] = previous
        }
        let id = UUID()
        let writer = RecordingWriter(
            url: url(of: id), id: id, when: when, directory: directory,
            encryptedStore: encryptedStore)
        open = writer
        return writer
    }

    /// Ends the recording and makes it the one ``current()`` answers with, ahead of its last bytes.
    public func finish(_ writer: RecordingWriter) -> KeptRecording {
        let recording = writer.finish()
        if open?.id == writer.id { open = nil }
        last = recording
        settling[recording.id] = writer
        return recording
    }

    /// Waits for a finished recording's bytes, which a reader of its file needs and a live dictation does not.
    public func settle(_ id: UUID) async {
        guard let writer = settling[id] else { return }
        await writer.drained()
        settling[id] = nil
        if writer.failed, last?.id == id { last = nil }
    }

    /// Deletes the file of a recording that was cancelled.
    public func abandon(_ writer: RecordingWriter) async {
        writer.abandon()
        if open?.id == writer.id { open = nil }
        await writer.drained()
        settling[writer.id] = nil
    }

    // MARK: - RecordingKeeper

    public func current() -> KeptRecording? {
        guard let last, settling[last.id]?.failed != true else { return nil }
        return last
    }

    public func discard(_ id: UUID) async {
        await settle(id)
        try? FileManager.default.removeItem(at: url(of: id))
        try? FileManager.default.removeItem(at: destinationURL(of: id))
        try? FileManager.default.removeItem(at: finishedURL(of: id))
        if last?.id == id { last = nil }
        destinations[id] = nil
    }

    public func setDestination(_ destination: AppContext, fieldKind: Destination, for id: UUID) {
        guard last?.id == id || FileManager.default.fileExists(atPath: url(of: id).path) else { return }
        let recorded = RecordedDestination(app: destination.identity, fieldKind: fieldKind)
        destinations[id] = recorded
        if let data = try? PropertyListEncoder().encode(recorded) {
            try? PrivateFile.write(data, to: destinationURL(of: id))
        }
        if last?.id == id, let last {
            self.last = KeptRecording(
                id: last.id, when: last.when, duration: last.duration,
                destination: recorded.app, fieldKind: fieldKind)
        }
    }

    /// Deletes every recording kept for a retry, leaving only the one still being written.
    public func discardEverything() async throws {
        for id in settling.keys { await settle(id) }
        let files = try LocalStore.contents(of: directory)
            .map { directory.appending(path: $0, directoryHint: .notDirectory) }
            .filter { file in
                file.standardizedFileURL != open?.url.standardizedFileURL
            }
        last = nil
        try LocalStore.removeEach(files)
    }

    /// Keeps a recording whose words landed, for a fix to be retried, under the same window and byte limit, never listed as waiting.
    package func keepFinished(_ id: UUID) async {
        await settle(id)
        guard FileManager.default.fileExists(atPath: url(of: id).path) else { return }
        try? PrivateFile.write(Data(), to: finishedURL(of: id))
        if last?.id == id { last = nil }
    }

    /// Keeps a landed dictation's audio for a fix when History kept its record, and deletes it otherwise.
    package func settleFinished(_ id: UUID?, recorded: Bool) async {
        guard let id else { return }
        if recorded { await keepFinished(id) } else { await discard(id) }
    }

    /// Whether a finished dictation's audio is still kept at `now`, deleting whatever has gone stale.
    package func keepsFinished(_ id: UUID, now: Date) async -> Bool {
        _ = await listed(now: now)
        return FileManager.default.fileExists(atPath: finishedURL(of: id).path)
            && FileManager.default.fileExists(atPath: url(of: id).path)
    }

    public func waiting(now: Date) async -> [KeptRecording] {
        await listed(now: now).filter { !$0.finished }.map(\.recording)
    }

    /// Every recording inside the window and the byte limit, newest first, with anything stale deleted.
    private func listed(now: Date) async -> [(recording: KeptRecording, finished: Bool)] {
        // The list is read from the files themselves, so anything still on its way to the disk has to land first.
        for id in settling.keys { await settle(id) }
        let files =
            (try? FileManager.default.contentsOfDirectory(
                at: directory, includingPropertiesForKeys: [.creationDateKey, .fileSizeKey]))
            ?? []
        // The promise as the rule the three stores share states it; the clock is the caller's.
        let window = RetentionWindow(span: retention.inSeconds, now: now)
        var kept: [(recording: KeptRecording, finished: Bool, bytes: Int)] = []
        for file in files {
            if file.standardizedFileURL == open?.url.standardizedFileURL { continue }
            guard file.pathExtension == "wav",
                let id = UUID(uuidString: file.deletingPathExtension().lastPathComponent)
            else {
                discardIfExpiredOrphan(file, window: window, now: now)
                continue
            }
            RecordingWriter.repair(file)
            let values = try? file.resourceValues(forKeys: [.creationDateKey, .fileSizeKey])
            let when = values?.creationDate ?? now
            guard window.keeps(when) else {
                // Unlisted either way; a clock too far ahead to be believed only stops the deleting.
                if window.mayDelete(when) { await discard(id) }
                continue
            }
            let frames: Int
            if let encryptedStore {
                guard let audio = try? readAudio(at: file, encryptedStore: encryptedStore) else { continue }
                frames = audio.samples.count
            } else {
                guard let size = values?.fileSize else { continue }
                frames = WAVEncoder.frames(inFileOf: size)
            }
            guard frames > 0 else {
                await discard(id)
                continue
            }
            kept.append(
                (
                    KeptRecording(
                        id: id, when: when, duration: RecordingWriter.duration(ofFrames: frames),
                        destination: destination(for: id)?.app,
                        fieldKind: destination(for: id)?.fieldKind),
                    FileManager.default.fileExists(atPath: finishedURL(of: id).path),
                    values?.fileSize ?? 0
                ))
        }
        return await withinByteLimit(kept.sorted { $0.recording.when > $1.recording.when })
    }

    /// Keeps the newest recordings whose stored sizes fit the byte limit, always the newest one, and deletes the rest.
    private func withinByteLimit(
        _ newestFirst: [(recording: KeptRecording, finished: Bool, bytes: Int)]
    ) async -> [(recording: KeptRecording, finished: Bool)] {
        var total = 0
        var kept: [(recording: KeptRecording, finished: Bool)] = []
        for (recording, finished, bytes) in newestFirst {
            total += bytes
            if kept.isEmpty || total <= byteLimit {
                kept.append((recording, finished))
            } else {
                await discard(recording.id)
            }
        }
        return kept
    }

    /// Removes an unrecognized regular file once its age is outside this store's retention window.
    private func discardIfExpiredOrphan(_ file: URL, window: RetentionWindow, now: Date) {
        guard
            let values = try? file.resourceValues(forKeys: [
                .creationDateKey, .contentModificationDateKey, .isRegularFileKey,
            ]),
            values.isRegularFile == true
        else { return }
        let when = values.creationDate ?? values.contentModificationDate ?? now
        guard !window.keeps(when), window.mayDelete(when) else { return }
        try? FileManager.default.removeItem(at: file)
    }

    public func audio(of id: UUID) async throws(AudioCaptureError) -> AudioSamples {
        await settle(id)
        return try readAudio(at: url(of: id), encryptedStore: encryptedStore)
    }

    /// Opens an encrypted stream or migrates a legacy WAV before returning plaintext samples.
    private func readAudio(
        at url: URL, encryptedStore: EncryptedStore?
    ) throws(AudioCaptureError) -> AudioSamples {
        guard let encryptedStore else { return try AudioFileReader.read(contentsOf: url) }
        if EncryptedRecordingFile.isEncrypted(url) {
            do { return try EncryptedRecordingFile.read(from: url, encryptedStore: encryptedStore) } catch {
                throw .engineFailed(description: error.localizedDescription)
            }
        }
        RecordingWriter.repair(url)
        let audio = try AudioFileReader.read(contentsOf: url)
        do { try EncryptedRecordingFile.encode(audio, to: url, encryptedStore: encryptedStore) } catch {
            throw .engineFailed(description: error.localizedDescription)
        }
        return audio
    }

    private func url(of id: UUID) -> URL {
        directory.appending(path: "\(id.uuidString).wav", directoryHint: .notDirectory)
    }

    /// The empty marker that says a recording's words landed, so it is kept for a fix rather than waiting.
    private func finishedURL(of id: UUID) -> URL {
        directory.appending(path: "\(id.uuidString).finished", directoryHint: .notDirectory)
    }

    private func destinationURL(of id: UUID) -> URL {
        directory.appending(path: "\(id.uuidString).context", directoryHint: .notDirectory)
    }

    private func destination(for id: UUID) -> RecordedDestination? {
        if let cached = destinations[id] { return cached }
        guard let data = try? Data(contentsOf: destinationURL(of: id)),
            let decoded = try? PropertyListDecoder().decode(RecordedDestination.self, from: data)
        else { return nil }
        destinations[id] = decoded
        return decoded
    }
}
