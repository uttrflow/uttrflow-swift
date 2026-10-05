// Crash-recoverable recording chunks use the shared authenticated installation key.

import CryptoKit
import Foundation
import Synchronization
import Testing
import UttrflowCore

@testable import UttrflowAudio

@Suite("Encrypted recording files")
struct EncryptedRecordingTests {
    private struct Keys: StoreKeyProviding {
        let value = SymmetricKey(size: .bits256)
        func key(createIfMissing: Bool) throws -> SymmetricKey { value }
    }

    private final class CountingKeys: StoreKeyProviding, Sendable {
        let value = SymmetricKey(size: .bits256)
        let lookups = Mutex(0)
        func key(createIfMissing: Bool) throws -> SymmetricKey {
            lookups.withLock { $0 += 1 }
            return value
        }
    }

    private struct Sandbox: ~Copyable {
        let directory = URL.temporaryDirectory.appending(
            path: "uttrflow-encrypted-recordings-\(UUID().uuidString)", directoryHint: .isDirectory)
        init() throws {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        }
        func file(_ name: String) -> URL { directory.appending(path: name, directoryHint: .notDirectory) }
        deinit { try? FileManager.default.removeItem(at: directory) }
    }

    private func envelopeSize(_ data: Data, at offset: Int) -> Int {
        Int(data.readLittleEndianUInt32(at: offset + 4))
    }

    @Test("streamed recordings contain encrypted fixed-size chunks and decrypt for retry")
    func encryptedRoundTrip() async throws {
        let sandbox = try Sandbox()
        let keys = Keys()
        let encryptedStore = EncryptedStore(keys: keys)
        let file = sandbox.file("take.wav")
        let writer = RecordingWriter(url: file, encryptedStore: encryptedStore)
        let expected = Array(repeating: Float(0.25), count: EncryptedRecordingFile.maximumChunkFrames + 800)
        writer.append(Array(expected[..<10_000]))
        writer.append(Array(expected[10_000...]))
        _ = writer.finish()
        await writer.drained()

        let stored = try Data(contentsOf: file)
        #expect(stored.starts(with: EncryptedRecordingFile.magic))
        #expect(!stored.starts(with: Data("RIFF".utf8)))
        #expect(stored != WAVEncoder.encode(.canonical(expected)))
        let audio = try EncryptedRecordingFile.read(
            from: file, encryptedStore: EncryptedStore(keys: keys))
        #expect(audio.samples.count == expected.count)
        #expect(abs((audio.samples.first ?? 0) - 0.25) < 0.001)
    }

    @Test("a multi-chunk recording reads the store key once")
    func multiChunkRecordingReadsKeyOnce() async throws {
        let sandbox = try Sandbox()
        let keys = CountingKeys()
        let encryptedStore = EncryptedStore(keys: keys)
        let file = sandbox.file("long.wav")
        let writer = RecordingWriter(url: file, encryptedStore: encryptedStore)
        writer.append(Array(repeating: 0.1, count: EncryptedRecordingFile.maximumChunkFrames * 3 + 5))
        _ = writer.finish()
        await writer.drained()
        _ = try EncryptedRecordingFile.read(from: file, encryptedStore: encryptedStore)
        #expect(keys.lookups.withLock { $0 } == 1)
    }

    @Test("a recording truncated at a chunk boundary still decrypts all complete chunks")
    func crashAtChunkBoundary() async throws {
        let sandbox = try Sandbox()
        let crypto = EncryptedStore(keys: Keys())
        let file = sandbox.file("boundary.wav")
        let writer = RecordingWriter(url: file, encryptedStore: crypto)
        writer.append(Array(repeating: 0.2, count: EncryptedRecordingFile.maximumChunkFrames))
        writer.append(Array(repeating: 0.3, count: 1_000))
        _ = writer.finish()
        await writer.drained()

        let stored = try Data(contentsOf: file)
        let endOfFirstChunk =
            EncryptedRecordingFile.headerSize
            + EncryptedRecordingFile.chunkHeaderSize
            + envelopeSize(stored, at: EncryptedRecordingFile.headerSize)
        try stored.prefix(endOfFirstChunk).write(to: file)

        let recovered = try EncryptedRecordingFile.read(from: file, encryptedStore: crypto)
        #expect(recovered.samples.count == EncryptedRecordingFile.maximumChunkFrames)
        #expect(abs((recovered.samples.last ?? 0) - 0.2) < 0.001)
    }

    @Test("a recording truncated inside a chunk keeps earlier complete chunks")
    func crashInsideChunk() async throws {
        let sandbox = try Sandbox()
        let crypto = EncryptedStore(keys: Keys())
        let file = sandbox.file("partial.wav")
        let writer = RecordingWriter(url: file, encryptedStore: crypto)
        writer.append(Array(repeating: 0.2, count: EncryptedRecordingFile.maximumChunkFrames))
        writer.append(Array(repeating: 0.3, count: 1_000))
        _ = writer.finish()
        await writer.drained()

        let stored = try Data(contentsOf: file)
        let firstRecordEnd =
            EncryptedRecordingFile.headerSize
            + EncryptedRecordingFile.chunkHeaderSize
            + envelopeSize(stored, at: EncryptedRecordingFile.headerSize)
        try stored.prefix(firstRecordEnd + EncryptedRecordingFile.chunkHeaderSize + 12).write(to: file)

        let recovered = try EncryptedRecordingFile.read(from: file, encryptedStore: crypto)
        #expect(recovered.samples.count == EncryptedRecordingFile.maximumChunkFrames)
    }

    @Test("legacy WAV recordings migrate when listed and remain readable")
    func legacyRecordingMigrates() async throws {
        let sandbox = try Sandbox()
        let now = Date()
        let id = UUID()
        let file = sandbox.file("\(id.uuidString).wav")
        let original = AudioSamples.canonical(Array(repeating: 0.125, count: 1_600))
        try PrivateFile.write(WAVEncoder.encode(original), to: file)
        try FileManager.default.setAttributes([.creationDate: now], ofItemAtPath: file.path)
        let crypto = EncryptedStore(keys: Keys())
        let store = RecordingStore(directory: sandbox.directory, encryptedStore: crypto)

        let listed = await store.waiting(now: now)
        #expect(listed.map(\.id) == [id])
        #expect(EncryptedRecordingFile.isEncrypted(file))
        #expect(try await store.audio(of: id).samples.count == original.samples.count)
    }
}

private extension Data {
    func readLittleEndianUInt32(at offset: Int) -> UInt32 {
        UInt32(self[offset]) | UInt32(self[offset + 1]) << 8 | UInt32(self[offset + 2]) << 16
            | UInt32(self[offset + 3]) << 24
    }
}
