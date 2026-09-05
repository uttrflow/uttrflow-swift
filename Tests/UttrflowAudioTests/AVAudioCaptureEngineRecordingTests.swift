import Foundation
import Testing

@testable import UttrflowAudio
@testable import UttrflowCore

@Suite("AVAudioCaptureEngine keeps the recording beside the buffer")
struct AVAudioCaptureEngineRecordingTests {
    private struct Sandbox: ~Copyable {
        let directory: URL
        init() {
            directory = URL(fileURLWithPath: NSTemporaryDirectory())
                .appending(path: "uttrflow-engine-\(UUID().uuidString)")
        }
        deinit { try? FileManager.default.removeItem(at: directory) }
    }

    @Test("every block the buffer gets, the file gets too")
    func fileMatchesBuffer() async throws {
        let sandbox = Sandbox()
        let store = RecordingStore(directory: sandbox.directory)
        let source = FakeMicrophoneSource()
        let engine = AVAudioCaptureEngine(source: source, recordings: store)

        try await engine.start()
        source.emit([0.1, 0.2])
        source.emit([0.3])
        let audio = try await engine.stop()

        let recording = try #require(await store.current())
        #expect(audio.samples == [0.1, 0.2, 0.3])
        let kept = try await store.audio(of: recording.id)
        #expect(kept.samples.count == 3)
        #expect(zip(kept.samples, audio.samples).allSatisfy { abs($0 - $1) < 0.001 })
    }

    @Test("a cancelled recording leaves no file")
    func cancelAbandonsTheFile() async throws {
        let sandbox = Sandbox()
        let store = RecordingStore(directory: sandbox.directory)
        let source = FakeMicrophoneSource()
        let engine = AVAudioCaptureEngine(source: source, recordings: store)

        try await engine.start()
        source.emit([0.5])
        await engine.cancel()

        #expect(await store.current() == nil)
        #expect(await store.waiting(now: Date()).isEmpty)
    }

    @Test("a microphone that will not start leaves no file either")
    func failedStartAbandonsTheFile() async {
        let sandbox = Sandbox()
        let store = RecordingStore(directory: sandbox.directory)
        let engine = AVAudioCaptureEngine(
            source: FakeMicrophoneSource(startError: .noInputDevice), recordings: store)

        await #expect(throws: AudioCaptureError.noInputDevice) { try await engine.start() }

        #expect(await store.waiting(now: Date()).isEmpty)
        #expect(await engine.state == .idle)
    }

    @Test("records nothing when it has nowhere to keep it")
    func noStoreMeansNoFile() async throws {
        let engine = AVAudioCaptureEngine(source: FakeMicrophoneSource())
        try await engine.start()
        _ = try await engine.stop()
        #expect(await engine.state == .idle)
    }
}
