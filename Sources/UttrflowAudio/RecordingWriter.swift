public import Foundation
public import UttrflowCore
private import Synchronization

/// Appends microphone blocks to a WAV file as they arrive, so a crash loses at most the last block.
public final class RecordingWriter: Sendable {
    private struct State: Sendable {
        var descriptor: Int32
        var frames = 0
        var isOpen = true
    }

    public let id: UUID
    public let url: URL
    /// When the microphone opened.
    public let when: Date

    private let state: Mutex<State>
    /// Off the capture thread, which must never wait on a disk.
    private let queue = DispatchQueue(label: "com.uttrflow.recording-writer", qos: .utility)

    /// Creates the file with a header that claims no frames yet. See `Docs/recordings.md`.
    public init(url: URL, id: UUID = UUID(), when: Date = Date()) throws(AudioCaptureError) {
        self.id = id
        self.url = url
        self.when = when
        let descriptor = open(url.path, O_WRONLY | O_CREAT | O_TRUNC, 0o600)
        guard descriptor >= 0 else {
            throw .engineFailed(description: "could not create \(url.lastPathComponent)")
        }
        state = Mutex(State(descriptor: descriptor))
        let header = WAVEncoder.header(frames: 0, sampleRate: AudioSamples.canonicalSampleRate)
        guard Self.write(header, to: descriptor) else {
            close(descriptor)
            throw .engineFailed(description: "could not write \(url.lastPathComponent)")
        }
    }

    /// Queues `block` for writing and returns at once.
    public func append(_ block: [Float]) {
        guard !block.isEmpty else { return }
        queue.async { [self] in
            state.withLock { state in
                guard state.isOpen, Self.write(WAVEncoder.pcm(block), to: state.descriptor) else { return }
                state.frames += block.count
            }
        }
    }

    /// Flushes what is queued, writes the true frame count into the header and closes the file.
    public func finish() -> KeptRecording {
        let frames = queue.sync {
            state.withLock { state -> Int in
                defer { state.isOpen = false }
                guard state.isOpen else { return state.frames }
                let header = WAVEncoder.header(
                    frames: state.frames, sampleRate: AudioSamples.canonicalSampleRate)
                _ = Self.write(header, to: state.descriptor, at: 0)
                close(state.descriptor)
                return state.frames
            }
        }
        return KeptRecording(id: id, when: when, duration: Self.duration(ofFrames: frames))
    }

    /// Closes and deletes the file: nothing in it is wanted.
    public func abandon() {
        queue.sync {
            state.withLock { state in
                guard state.isOpen else { return }
                state.isOpen = false
                close(state.descriptor)
            }
        }
        try? FileManager.default.removeItem(at: url)
    }

    /// Rewrites the header of a file whose writer never finished, from the bytes that made it to disk.
    public static func repair(_ url: URL) {
        guard let size = try? FileManager.default.attributesOfItem(atPath: url.path)[.size] as? Int,
            size > WAVEncoder.headerSize,
            let descriptor = Optional(open(url.path, O_RDWR)), descriptor >= 0
        else { return }
        defer { close(descriptor) }
        var declared: UInt32 = 0
        let read = withUnsafeMutableBytes(of: &declared) {
            pread(descriptor, $0.baseAddress, 4, off_t(WAVEncoder.dataSizeOffset))
        }
        guard read == 4, UInt32(littleEndian: declared) == 0 else { return }
        let frames = WAVEncoder.frames(inFileOf: size)
        let header = WAVEncoder.header(frames: frames, sampleRate: AudioSamples.canonicalSampleRate)
        _ = write(header, to: descriptor, at: 0)
    }

    /// How long `frames` of canonical audio last.
    static func duration(ofFrames frames: Int) -> Duration {
        .seconds(Double(frames) / Double(AudioSamples.canonicalSampleRate))
    }

    /// Writes all of `data`, at the current position or at `offset`.
    private static func write(_ data: Data, to descriptor: Int32, at offset: off_t? = nil) -> Bool {
        data.withUnsafeBytes { bytes -> Bool in
            var written = 0
            while written < bytes.count {
                guard let base = bytes.baseAddress else { return false }
                let remaining = bytes.count - written
                let count =
                    offset.map { pwrite(descriptor, base + written, remaining, $0 + off_t(written)) }
                    ?? Darwin.write(descriptor, base + written, remaining)
                guard count > 0 else { return false }
                written += count
            }
            return true
        }
    }
}
