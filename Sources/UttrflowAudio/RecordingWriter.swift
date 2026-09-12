// Writes a recording's WAV to disk while it is still being captured.
public import Foundation
public import UttrflowCore
private import Synchronization

/// Appends microphone blocks to a WAV file as they arrive, so a crash loses at most the last block.
public final class RecordingWriter: Sendable {
    /// What the capture thread hands the sink, in the order it happened.
    private enum Piece: Sendable {
        case audio([Float])
        case close(keeping: Bool)
    }

    /// Owns the descriptor, so every write to it happens on one isolated task rather than on a caller's thread.
    private actor Sink {
        private let url: URL
        private let descriptor: Int32
        private var frames = 0
        private var isOpen = true

        init(descriptor: Int32, url: URL) {
            self.descriptor = descriptor
            self.url = url
        }

        /// Writes each piece as it arrives and closes the file when the stream ends, however it ends.
        func consume(_ pieces: AsyncStream<Piece>) async {
            for await piece in pieces {
                switch piece {
                case .audio(let block): append(block)
                case .close(let keeping): close(keeping: keeping)
                }
            }
            close(keeping: true)
        }

        private func append(_ block: [Float]) {
            guard isOpen, RecordingWriter.write(WAVEncoder.pcm(block), to: descriptor) else { return }
            frames += block.count
        }

        /// Rewrites the header with the frames that reached disk, or deletes a file nobody wants.
        private func close(keeping: Bool) {
            guard isOpen else { return }
            isOpen = false
            if keeping {
                let header = WAVEncoder.header(
                    frames: frames, sampleRate: AudioSamples.canonicalSampleRate)
                _ = RecordingWriter.write(header, to: descriptor, at: 0)
            }
            Darwin.close(descriptor)
            if !keeping { try? FileManager.default.removeItem(at: url) }
        }
    }

    /// What the recording is worth saying about before any of its bytes are durable.
    private struct Bookkeeping: Sendable {
        var frames = 0
        var isOpen = true
    }

    public let id: UUID
    public let url: URL
    /// When the microphone opened.
    public let when: Date

    private let bookkeeping = Mutex(Bookkeeping())
    /// Off the capture thread, which must never wait on a disk, and off the cooperative pool, which must never block.
    private let pieces: AsyncStream<Piece>.Continuation
    private let sink: Task<Void, Never>

    /// Creates the file with a header that claims no frames yet. See `Docs/recordings.md`.
    public init(url: URL, id: UUID = UUID(), when: Date = Date()) throws(AudioCaptureError) {
        self.id = id
        self.url = url
        self.when = when
        let descriptor = open(url.path, O_WRONLY | O_CREAT | O_TRUNC, 0o600)
        guard descriptor >= 0 else {
            throw .engineFailed(description: "could not create \(url.lastPathComponent)")
        }
        let header = WAVEncoder.header(frames: 0, sampleRate: AudioSamples.canonicalSampleRate)
        guard Self.write(header, to: descriptor) else {
            close(descriptor)
            throw .engineFailed(description: "could not write \(url.lastPathComponent)")
        }
        let (stream, continuation) = AsyncStream<Piece>.makeStream()
        pieces = continuation
        let sink = Sink(descriptor: descriptor, url: url)
        self.sink = Task { await sink.consume(stream) }
    }

    /// Hands `block` to the sink and returns at once.
    public func append(_ block: [Float]) {
        guard !block.isEmpty else { return }
        let accepted = bookkeeping.withLock { state -> Bool in
            guard state.isOpen else { return false }
            state.frames += block.count
            return true
        }
        guard accepted else { return }
        pieces.yield(.audio(block))
    }

    /// Ends the recording and answers for it from what was handed over, before the last bytes reach the disk.
    public func finish() -> KeptRecording {
        let frames = bookkeeping.withLock { state -> Int in
            if state.isOpen {
                state.isOpen = false
                pieces.yield(.close(keeping: true))
                pieces.finish()
            }
            return state.frames
        }
        return KeptRecording(id: id, when: when, duration: Self.duration(ofFrames: frames))
    }

    /// Asks for the file to be closed and deleted: nothing in it is wanted.
    public func abandon() {
        bookkeeping.withLock { state in
            guard state.isOpen else { return }
            state.isOpen = false
            pieces.yield(.close(keeping: false))
            pieces.finish()
        }
    }

    /// Suspends until every block handed over has reached the disk, which only a reader of the file needs.
    public func drained() async {
        await sink.value
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
