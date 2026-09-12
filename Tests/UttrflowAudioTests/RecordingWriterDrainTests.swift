// Tests that ending a recording never waits for the disk.
import Foundation
import Synchronization
import Testing

@testable import UttrflowAudio
@testable import UttrflowCore

/// A writer whose file is a pipe nobody is reading cannot write, so the wait to close it is visible.
@Suite("RecordingWriter drain")
struct RecordingWriterDrainTests {
    /// A boolean two threads may share, since `Mutex` itself cannot be handed to a closure.
    private final class Flag: Sendable {
        private let state = Mutex(false)
        func set() { state.withLock { $0 = true } }
        var isSet: Bool { state.withLock { $0 } }
    }

    /// A named pipe with its read end held open, so writes to it block until this test chooses to read.
    private final class StalledFile: Sendable {
        let directory: URL
        let url: URL
        private let reader: Int32
        private let read = DispatchSemaphore(value: 0)
        private let started = Flag()

        init() throws {
            directory = URL(fileURLWithPath: NSTemporaryDirectory())
                .appending(path: "uttrflow-stall-\(UUID().uuidString)")
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            url = directory.appending(path: "take.wav")
            guard mkfifo(url.path, 0o600) == 0 else {
                throw AudioCaptureError.engineFailed(description: "could not make a pipe")
            }
            reader = open(url.path, O_RDONLY | O_NONBLOCK)
            guard reader >= 0 else {
                throw AudioCaptureError.engineFailed(description: "could not open the pipe")
            }
        }

        /// Starts reading the pipe `delay` from now, on a thread of its own, and says when it began.
        func readEverything(after delay: Duration) {
            let reader = self.reader
            let started = self.started
            let read = self.read
            DispatchQueue.global().asyncAfter(deadline: .now() + delay.inSeconds) {
                started.set()
                var buffer = [UInt8](repeating: 0, count: 65_536)
                let deadline = Date().addingTimeInterval(10)
                while Date() < deadline {
                    let count = buffer.withUnsafeMutableBytes {
                        Darwin.read(reader, $0.baseAddress, $0.count)
                    }
                    if count == 0 { break }
                    if count < 0 { usleep(1_000) }
                }
                read.signal()
            }
        }

        /// Whether the reader has begun, which is what a writer must not have waited for.
        var hasRead: Bool { started.isSet }

        /// Lets the reader finish before the pipe goes away under it.
        func waitForReader() { read.wait() }

        deinit {
            close(reader)
            try? FileManager.default.removeItem(at: directory)
        }
    }

    /// Roughly 400 kB of PCM, far more than a pipe holds, so the sink is still writing when the key is released.
    private let block = [Float](repeating: 0.3, count: 200_000)

    @Test("ending a recording answers for it without waiting for the bytes")
    func finishDoesNotWaitForTheDisk() async throws {
        let file = try StalledFile()
        let writer = try RecordingWriter(url: file.url)
        writer.append(block)
        file.readEverything(after: .milliseconds(200))

        let recording = writer.finish()

        #expect(file.hasRead == false, "finish() waited for the disk before answering")
        #expect(recording.duration == .seconds(200_000.0 / 16_000.0))
        await writer.drained()
        file.waitForReader()
    }

    @Test("cancelling a recording returns without waiting for the file to close")
    func abandonDoesNotWaitForTheDisk() async throws {
        let file = try StalledFile()
        let writer = try RecordingWriter(url: file.url)
        writer.append(block)
        file.readEverything(after: .milliseconds(200))

        writer.abandon()

        #expect(file.hasRead == false, "abandon() waited for the disk before returning")
        await writer.drained()
        file.waitForReader()
        #expect(!FileManager.default.fileExists(atPath: file.url.path))
    }
}
