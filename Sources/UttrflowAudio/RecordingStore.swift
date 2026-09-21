// Keeps recordings on disk for retry and prunes the old ones.
public import Foundation
public import UttrflowCore

/// The recordings kept on this Mac, one WAV each, deleted as their words land or go stale.
public actor RecordingStore: RecordingKeeper {
    /// How long a recording that could not become text waits for a retry.
    public static let defaultRetention: Duration = .seconds(24 * 60 * 60)

    private let directory: URL
    private let retention: Duration
    /// The writer of the recording under way, whose file is not yet a recording to list.
    private var open: RecordingWriter?
    /// The recording written for the dictation that most recently stopped.
    private var last: KeptRecording?
    /// Writers whose bookkeeping is done and whose last bytes are still on their way to the disk.
    private var settling: [UUID: RecordingWriter] = [:]

    public init(
        directory: URL = RecordingStore.defaultDirectory(),
        retention: Duration = RecordingStore.defaultRetention
    ) {
        self.directory = directory
        self.retention = retention
    }

    /// Where this build's recordings live, beside the other stores so a development build never prunes the shipped app's.
    public static func defaultDirectory(
        in container: URL = .applicationSupportDirectory,
        for identifier: String? = Bundle.main.bundleIdentifier
    ) -> URL {
        LocalStore.directory("recordings", in: container, for: identifier)
    }

    // MARK: - Writing

    /// Opens a file for the recording that is starting, or nothing if the disk refuses.
    public func begin(at when: Date = Date()) async -> RecordingWriter? {
        last = nil
        if let previous = open {
            previous.abandon()
            await previous.drained()
        }
        try? PrivateFile.makeDirectory(at: directory)
        let id = UUID()
        let writer = try? RecordingWriter(url: url(of: id), id: id, when: when)
        // The file remembers when it began, which is all a later launch has to go on.
        if let writer {
            try? FileManager.default.setAttributes([.creationDate: when], ofItemAtPath: writer.url.path)
        }
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
    }

    /// Deletes the file of a recording that was cancelled.
    public func abandon(_ writer: RecordingWriter) async {
        writer.abandon()
        if open?.id == writer.id { open = nil }
        await writer.drained()
        settling[writer.id] = nil
    }

    // MARK: - RecordingKeeper

    public func current() -> KeptRecording? { last }

    public func discard(_ id: UUID) async {
        await settle(id)
        try? FileManager.default.removeItem(at: url(of: id))
        if last?.id == id { last = nil }
    }

    /// Deletes every recording kept for a retry, leaving only the one still being written.
    public func discardEverything() async throws {
        for id in settling.keys { await settle(id) }
        let files = try LocalStore.contents(of: directory)
            .map { directory.appending(path: $0, directoryHint: .notDirectory) }
            .filter { file in
                guard file.pathExtension == "wav" else { return false }
                let id = UUID(uuidString: file.deletingPathExtension().lastPathComponent)
                return id == nil || id != open?.id
            }
        last = nil
        try LocalStore.removeEach(files)
    }

    public func waiting(now: Date) async -> [KeptRecording] {
        // The list is read from the files themselves, so anything still on its way to the disk has to land first.
        for id in settling.keys { await settle(id) }
        let files =
            (try? FileManager.default.contentsOfDirectory(
                at: directory, includingPropertiesForKeys: [.creationDateKey, .fileSizeKey]))
            ?? []
        var kept: [KeptRecording] = []
        for file in files where file.pathExtension == "wav" {
            guard let id = UUID(uuidString: file.deletingPathExtension().lastPathComponent),
                id != open?.id
            else { continue }
            RecordingWriter.repair(file)
            let values = try? file.resourceValues(forKeys: [.creationDateKey, .fileSizeKey])
            let when = values?.creationDate ?? now
            guard now.timeIntervalSince(when) < retention.inSeconds else {
                await discard(id)
                continue
            }
            let frames = WAVEncoder.frames(inFileOf: values?.fileSize ?? 0)
            kept.append(
                KeptRecording(id: id, when: when, duration: RecordingWriter.duration(ofFrames: frames)))
        }
        return kept.sorted { $0.when > $1.when }
    }

    public func audio(of id: UUID) async throws(AudioCaptureError) -> AudioSamples {
        await settle(id)
        return try AudioFileReader.read(contentsOf: url(of: id))
    }

    private func url(of id: UUID) -> URL {
        directory.appending(path: "\(id.uuidString).wav", directoryHint: .notDirectory)
    }
}
