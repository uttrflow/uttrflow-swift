// Tests the on-disk recording store.
import Foundation
import Testing

@testable import UttrflowAudio
@testable import UttrflowCore

@Suite("RecordingStore")
struct RecordingStoreTests {
    private struct Sandbox: ~Copyable {
        let directory: URL
        init() {
            directory = URL(fileURLWithPath: NSTemporaryDirectory())
                .appending(path: "uttrflow-store-\(UUID().uuidString)/recordings")
        }
        deinit { try? FileManager.default.removeItem(at: directory.deletingLastPathComponent()) }
    }

    private let now = Date(timeIntervalSince1970: 1_800_000_000)

    @Test("the recording that just finished is the current one, and the current one is not waiting")
    func finishedBecomesCurrent() async throws {
        let sandbox = Sandbox()
        let store = RecordingStore(directory: sandbox.directory)

        let writer = try #require(await store.begin(at: now))
        writer.append(Array(repeating: 0.2, count: 3_200))
        #expect(await store.waiting(now: now).isEmpty, "a file still being written is not a recording yet")
        let finished = await store.finish(writer)

        #expect(await store.current() == finished)
        #expect(finished.duration == .seconds(0.2))
        #expect(await store.waiting(now: now) == [finished])
    }

    @Test("a new recording forgets the last one")
    func beginClearsCurrent() async throws {
        let sandbox = Sandbox()
        let store = RecordingStore(directory: sandbox.directory)
        let first = try #require(await store.begin(at: now))
        _ = await store.finish(first)

        let second = try #require(await store.begin(at: now))
        #expect(await store.current() == nil)
        _ = await store.finish(second)
        #expect(await store.waiting(now: now).count == 2)
    }

    @Test("discarding deletes the file and forgets it")
    func discardDeletes() async throws {
        let sandbox = Sandbox()
        let store = RecordingStore(directory: sandbox.directory)
        let writer = try #require(await store.begin(at: now))
        let finished = await store.finish(writer)

        await store.discard(finished.id)

        #expect(await store.current() == nil)
        #expect(await store.waiting(now: now).isEmpty)
        #expect(!FileManager.default.fileExists(atPath: writer.url.path))
    }

    @Test("abandoning a recording under way leaves nothing behind")
    func abandonLeavesNothing() async throws {
        let sandbox = Sandbox()
        let store = RecordingStore(directory: sandbox.directory)
        let writer = try #require(await store.begin(at: now))
        writer.append([0.1])

        await store.abandon(writer)

        #expect(await store.waiting(now: now).isEmpty)
        #expect(await store.current() == nil)
    }

    @Test("a waiting recording reads back as the audio that was written")
    func audioRoundTrip() async throws {
        let sandbox = Sandbox()
        let store = RecordingStore(directory: sandbox.directory)
        let writer = try #require(await store.begin(at: now))
        writer.append(Array(repeating: 0.3, count: 1_600))
        let finished = await store.finish(writer)

        let audio = try await store.audio(of: finished.id)
        #expect(audio.samples.count == 1_600)
        #expect(abs((audio.samples.first ?? 0) - 0.3) < 0.001)
    }

    @Test("asking for audio that is gone fails rather than answering silence")
    func missingAudioThrows() async {
        let sandbox = Sandbox()
        let store = RecordingStore(directory: sandbox.directory)
        await #expect(throws: AudioCaptureError.self) { _ = try await store.audio(of: UUID()) }
    }

    @Test("a recording older than the window is deleted when the list is read")
    func staleRecordingsExpire() async throws {
        let sandbox = Sandbox()
        let store = RecordingStore(directory: sandbox.directory, retention: .seconds(60))
        let writer = try #require(await store.begin(at: now))
        let finished = await store.finish(writer)

        #expect(await store.waiting(now: now) == [finished])
        #expect(await store.waiting(now: now.addingTimeInterval(120)).isEmpty)
        #expect(!FileManager.default.fileExists(atPath: writer.url.path))
    }

    @Test("newest first, and only the files that are recordings")
    func listsNewestFirstIgnoringStrays() async throws {
        let sandbox = Sandbox()
        let store = RecordingStore(directory: sandbox.directory)
        let older = try #require(await store.begin(at: now))
        let olderFinished = await store.finish(older)
        try? FileManager.default.setAttributes(
            [.creationDate: now.addingTimeInterval(-600)], ofItemAtPath: older.url.path)
        let newer = try #require(await store.begin(at: now))
        let newerFinished = await store.finish(newer)
        try "not audio".write(
            to: sandbox.directory.appending(path: "notes.txt"), atomically: true, encoding: .utf8)
        try Data().write(to: sandbox.directory.appending(path: "stray.wav"))

        let waiting = await store.waiting(now: now)
        #expect(waiting.map(\.id) == [newerFinished.id, olderFinished.id])
    }

    /// The app died while the key was held: the file is on disk with a header that says it is empty.
    @Test("a recording from before a crash is listed with its audio repaired")
    func crashedRecordingIsRecovered() async throws {
        let sandbox = Sandbox()
        try FileManager.default.createDirectory(at: sandbox.directory, withIntermediateDirectories: true)
        let id = UUID()
        var data = WAVEncoder.header(frames: 0, sampleRate: AudioSamples.canonicalSampleRate)
        data.append(WAVEncoder.pcm(Array(repeating: 0.4, count: 16_000)))
        try data.write(to: sandbox.directory.appending(path: "\(id.uuidString).wav"))
        let store = RecordingStore(directory: sandbox.directory)

        let waiting = await store.waiting(now: Date())

        #expect(waiting.map(\.id) == [id])
        #expect(waiting.first?.duration == .seconds(1))
        #expect(try await store.audio(of: id).samples.count == 16_000)
    }

    @Test("answers nothing rather than failing when the folder cannot be made")
    func unwritableFolder() async {
        let store = RecordingStore(directory: URL(fileURLWithPath: "/dev/null/recordings"))
        #expect(await store.begin(at: now) == nil)
        #expect(await store.waiting(now: now).isEmpty)
    }

    @Test("lives under Application Support by default")
    func defaultDirectory() {
        let container = URL(fileURLWithPath: "/tmp/container")
        #expect(RecordingStore.defaultDirectory(in: container).path == "/tmp/container/Uttrflow/recordings")
    }

    @Test("the shipped app keeps the recordings folder it already has")
    func shippedAppKeepsItsFolder() {
        let container = URL(fileURLWithPath: "/tmp/container")
        let shipped = RecordingStore.defaultDirectory(in: container, for: LocalStore.productionIdentifier)
        #expect(shipped.path == "/tmp/container/Uttrflow/recordings")
    }

    @Test("a development build keeps its recordings beside the shipped app's, not among them")
    func developmentBuildHasItsOwnFolder() {
        let container = URL(fileURLWithPath: "/tmp/container")
        let development = RecordingStore.defaultDirectory(in: container, for: "com.uttrflow.Uttrflow.dev")
        let shipped = RecordingStore.defaultDirectory(in: container, for: LocalStore.productionIdentifier)
        #expect(development.path == "/tmp/container/Uttrflow.dev/recordings")
        #expect(development.standardizedFileURL != shipped.standardizedFileURL)
    }

    @Test("pruning in a development build leaves the shipped app's recordings alone")
    func pruningStaysInsideOneBuild() async throws {
        let sandbox = Sandbox()
        let container = sandbox.directory.deletingLastPathComponent()
        let shipped = RecordingStore(
            directory: RecordingStore.defaultDirectory(in: container, for: LocalStore.productionIdentifier))
        let development = RecordingStore(
            directory: RecordingStore.defaultDirectory(in: container, for: "com.uttrflow.Uttrflow.dev"),
            retention: .seconds(60))
        let writer = try #require(await shipped.begin(at: now))
        let kept = await shipped.finish(writer)

        #expect(await development.waiting(now: now.addingTimeInterval(120)).isEmpty)
        await development.discard(kept.id)

        #expect(FileManager.default.fileExists(atPath: writer.url.path))
        #expect(await shipped.waiting(now: now) == [kept])
    }
}

@Suite("RecordingStore, emptied")
struct RecordingStoreDiscardEverythingTests {
    private let now = Date(timeIntervalSince1970: 1_800_000_000)

    /// A fresh folder per test, removed by the test itself.
    private func directory() -> URL {
        URL(fileURLWithPath: NSTemporaryDirectory())
            .appending(path: "uttrflow-store-\(UUID().uuidString)/recordings")
    }

    @Test("discarding everything deletes every waiting recording and forgets the current one")
    func discardsEveryRecording() async throws {
        let folder = directory()
        defer { try? FileManager.default.removeItem(at: folder.deletingLastPathComponent()) }
        let store = RecordingStore(directory: folder)
        let first = try #require(await store.begin(at: now))
        _ = await store.finish(first)
        let second = try #require(await store.begin(at: now))
        _ = await store.finish(second)
        let stray = folder.appending(path: "not-a-uuid.wav")
        try Data("x".utf8).write(to: stray)

        try await store.discardEverything()

        #expect(await store.current() == nil)
        #expect(await store.waiting(now: now).isEmpty)
        #expect(!FileManager.default.fileExists(atPath: stray.path))
    }

    @Test("discarding everything leaves the recording still being written")
    func keepsTheOpenRecording() async throws {
        let folder = directory()
        defer { try? FileManager.default.removeItem(at: folder.deletingLastPathComponent()) }
        let store = RecordingStore(directory: folder)
        let finished = try #require(await store.begin(at: now))
        _ = await store.finish(finished)
        let open = try #require(await store.begin(at: now))

        try await store.discardEverything()

        #expect(!FileManager.default.fileExists(atPath: finished.url.path))
        #expect(FileManager.default.fileExists(atPath: open.url.path))
        await store.abandon(open)
    }

    @Test("discarding everything with no folder yet is nothing to do")
    func nothingToDiscard() async throws {
        try await RecordingStore(directory: directory()).discardEverything()
    }
}
