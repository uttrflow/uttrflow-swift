// Tests that expired recordings and transcripts leave the disk with no window open.

import Foundation
import UttrflowAudio
import UttrflowCore
import UttrflowHistory
import UttrflowPipeline
import Testing

@testable import Uttrflow

@MainActor
@Suite("Recordings and transcripts past retention are deleted without a window")
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
}
