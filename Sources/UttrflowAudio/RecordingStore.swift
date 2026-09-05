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

    public init(
        directory: URL = RecordingStore.defaultDirectory(),
        retention: Duration = RecordingStore.defaultRetention
    ) {
        self.directory = directory
        self.retention = retention
    }

    /// Where recordings live when the app has not been told otherwise.
    public static func defaultDirectory(in container: URL = .applicationSupportDirectory) -> URL {
        container.appending(path: "Uttrflow/recordings", directoryHint: .isDirectory)
    }

    // MARK: - Writing

    /// Opens a file for the recording that is starting, or nothing if the disk refuses.
    public func begin(at when: Date = Date()) -> RecordingWriter? {
        last = nil
        open?.abandon()
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let id = UUID()
        let writer = try? RecordingWriter(url: url(of: id), id: id, when: when)
        // The file remembers when it began, which is all a later launch has to go on.
        if let writer {
            try? FileManager.default.setAttributes([.creationDate: when], ofItemAtPath: writer.url.path)
        }
        open = writer
        return writer
    }

    /// Closes the file and makes it the recording ``current()`` answers with.
    public func finish(_ writer: RecordingWriter) -> KeptRecording {
        let recording = writer.finish()
        if open?.id == writer.id { open = nil }
        last = recording
        return recording
    }

    /// Deletes the file of a recording that was cancelled.
    public func abandon(_ writer: RecordingWriter) {
        writer.abandon()
        if open?.id == writer.id { open = nil }
    }

    // MARK: - RecordingKeeper

    public func current() -> KeptRecording? { last }

    public func discard(_ id: UUID) {
        try? FileManager.default.removeItem(at: url(of: id))
        if last?.id == id { last = nil }
    }

    public func waiting(now: Date) -> [KeptRecording] {
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
                discard(id)
                continue
            }
            let frames = WAVEncoder.frames(inFileOf: values?.fileSize ?? 0)
            kept.append(
                KeptRecording(id: id, when: when, duration: RecordingWriter.duration(ofFrames: frames)))
        }
        return kept.sorted { $0.when > $1.when }
    }

    public func audio(of id: UUID) throws(AudioCaptureError) -> AudioSamples {
        try AudioFileReader.read(contentsOf: url(of: id))
    }

    private func url(of id: UUID) -> URL {
        directory.appending(path: "\(id.uuidString).wav", directoryHint: .notDirectory)
    }
}
