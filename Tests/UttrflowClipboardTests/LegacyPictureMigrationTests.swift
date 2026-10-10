import CryptoKit
import Foundation
import Synchronization
import Testing
import UttrflowCore

@testable import UttrflowClipboard

@Suite("Legacy picture migration", .bug(id: 3741))
struct LegacyPictureMigrationTests {
    private struct Keys: StoreKeyProviding {
        let value = SymmetricKey(size: .bits256)
        func key(createIfMissing: Bool) throws -> SymmetricKey { value }
    }

    @Test("migration reads only the sealed header for many sealed pictures")
    func sealedPicturesReadOnlyHeaders() async throws {
        let folder = FileManager.default.temporaryDirectory.appending(
            path: UUID().uuidString, directoryHint: .isDirectory)
        let images = folder.appending(path: "Images", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: images, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }

        let crypto = EncryptedStore(keys: Keys())
        let raw = Data(repeating: 0x41, count: 400_000)
        for index in 0..<300 {
            let name = String(format: "%03d.png", index)
            try crypto.seal(raw, for: name).write(to: images.appending(path: name))
        }

        let bytesRead = Mutex(0)
        let wholeReads = Mutex(0)
        let migration = LegacyPictureMigration(
            readHeader: { url in
                guard let handle = try? FileHandle(forReadingFrom: url) else { return nil }
                defer { try? handle.close() }
                let data = try? handle.read(upToCount: EncryptedStore.sealedHeaderLength)
                bytesRead.withLock { $0 += data?.count ?? 0 }
                return data
            },
            readContents: { url in
                wholeReads.withLock { $0 += 1 }
                return try? Data(contentsOf: url)
            })

        await migration.run(in: images) { _, _ in }

        #expect(bytesRead.withLock { $0 } == 300 * EncryptedStore.sealedHeaderLength)
        #expect(wholeReads.withLock { $0 } == 0)
    }
}
