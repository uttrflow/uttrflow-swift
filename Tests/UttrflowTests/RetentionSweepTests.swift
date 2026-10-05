// Tests that expired recordings and transcripts leave the disk with no window open.

import Foundation
import UttrflowAudio
import UttrflowClipboard
import UttrflowCore
import UttrflowHistory
import UttrflowPipeline
import UttrflowSettings
import Testing

@testable import Uttrflow

@MainActor
@Suite("Recordings, transcripts and clipboard past retention are deleted without a window")
struct RetentionSweepTests {
    private struct Refused: Error {}

    /// Writes a recording file whose creation date says it began at `when`.
    private func recording(in root: URL, began when: Date) throws -> URL {
        let folder = RecordingStore.defaultDirectory(in: root)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let file = folder.appending(path: "\(UUID().uuidString).wav")
        try Data(count: 44).write(to: file)
        try FileManager.default.setAttributes([.creationDate: when], ofItemAtPath: file.path)
        return file
    }

    @Test("a dictation ending deletes a recording older than a day")
    func dictationEndingSweepsRecordings() async throws {
        let sandbox = Sandbox()
        let app = AppDelegate(container: sandbox.root)
        let stale = try recording(in: sandbox.root, began: Date().addingTimeInterval(-2 * 86_400))
        let fresh = try recording(in: sandbox.root, began: Date())

        app.render(.failed(DictationFailure(Refused())))
        await app.sweeping?.value

        #expect(app.mainWindow == nil)
        #expect(!FileManager.default.fileExists(atPath: stale.path))
        #expect(FileManager.default.fileExists(atPath: fresh.path))
    }

    @Test("a finished dictation sweeps too")
    func insertedSweepsRecordings() async throws {
        let sandbox = Sandbox()
        let app = AppDelegate(container: sandbox.root)
        let stale = try recording(in: sandbox.root, began: Date().addingTimeInterval(-2 * 86_400))

        let outcome = DictationOutcome(text: "Sample words", method: .accessibility, cleanedBy: .rules)
        app.render(.inserted(outcome))
        await app.sweeping?.value

        #expect(!FileManager.default.fileExists(atPath: stale.path))
    }

    @Test("a sweep deletes transcripts past the retention setting")
    func sweepDropsExpiredTranscripts() async throws {
        let sandbox = Sandbox()
        let app = AppDelegate(container: sandbox.root)
        app.settingsChanged(to: Settings(transcriptRetentionDays: 30))
        let file = DictationHistoryStore.defaultFile(in: sandbox.root)
        let writer = DictationHistoryStore(file: file)
        let old = DictationRecord(text: "Sample words", when: Date().addingTimeInterval(-60 * 86_400))
        let recent = DictationRecord(text: "More sample words", when: Date())
        try await writer.append(old, keeping: Retention(days: 365, now: Date()))
        try await writer.append(recent, keeping: Retention(days: 365, now: Date()))

        app.sweepExpired()
        await app.sweeping?.value

        let onDisk = try JSONDecoder().decode([DictationRecord].self, from: Data(contentsOf: file))
        #expect(onDisk.map(\.id) == [recent.id])
    }

    @Test("a sweep under the default keeps every transcript")
    func defaultKeepsTranscripts() async throws {
        let sandbox = Sandbox()
        let app = AppDelegate(container: sandbox.root)
        let file = DictationHistoryStore.defaultFile(in: sandbox.root)
        let writer = DictationHistoryStore(file: file)
        let old = DictationRecord(text: "Sample words", when: Date().addingTimeInterval(-60 * 86_400))
        try await writer.append(old, keeping: Retention(days: 365, now: Date()))

        app.sweepExpired()
        await app.sweeping?.value

        let onDisk = try JSONDecoder().decode([DictationRecord].self, from: Data(contentsOf: file))
        #expect(onDisk.map(\.id) == [old.id])
    }

    @Test("a retention sweep deletes expired clipboard clips and their picture files")
    func sweepDropsExpiredClipboardClips() async throws {
        let sandbox = Sandbox()
        let app = AppDelegate(container: sandbox.root)
        let now = Date()

        let file = ClipboardStore.defaultFile(in: sandbox.root)
        let writer = ClipboardStore(file: file)
        let longWindow = ClipRetention(days: 30, now: now)
        _ = await writer.clips(keeping: longWindow)
        let old = Clip(text: "expired", kind: .text, copiedAt: now.addingTimeInterval(-8 * 86_400))
        let recent = Clip(text: "recent", kind: .text, copiedAt: now)
        let oldPictureDate = now.addingTimeInterval(-6 * 86_400)
        let imageID = UUID()
        let image = try await writer.keep(Data([1, 2, 3]), forClip: imageID, width: 1, height: 1)
        let oldPicture = Clip(
            id: imageID, text: "", kind: .image, copiedAt: oldPictureDate, image: image)
        try await writer.record(oldPicture, keeping: longWindow)
        try await writer.record(old, keeping: longWindow)
        try await writer.record(recent, keeping: longWindow)

        let imageURL = await writer.imagesFolder.appending(path: image.file)
        #expect(FileManager.default.fileExists(atPath: imageURL.path))

        app.settingsChanged(to: Settings(clipboardRetentionDays: 1))
        await app.sweeping?.value
        let afterSettingChange = try JSONDecoder().decode([Clip].self, from: Data(contentsOf: file))
        #expect(afterSettingChange.map(\.id) == [recent.id, imageID])

        app.sweepExpired(now: now.addingTimeInterval(2 * 86_400))
        await app.sweeping?.value

        #expect(!FileManager.default.fileExists(atPath: file.path))
        #expect(!FileManager.default.fileExists(atPath: imageURL.path))
    }
}
