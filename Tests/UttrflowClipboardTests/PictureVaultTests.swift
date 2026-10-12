import CryptoKit
import Foundation
import Testing
import UttrflowCore

@testable import UttrflowClipboard

@Suite("Picture byte storage preserves confinement and ownership order")
struct PictureVaultTests {
    private struct Keys: StoreKeyProviding {
        let value: SymmetricKey
        func key(createIfMissing: Bool) throws -> SymmetricKey { value }
    }

    private struct FullDiskKeys: StoreKeyProviding {
        func key(createIfMissing: Bool) throws -> SymmetricKey {
            throw NSError(domain: NSPOSIXErrorDomain, code: Int(ENOSPC))
        }
    }

    @Test("bytes exist before ownership is reported and exact metadata is returned")
    func keepReportsAfterWrite() throws {
        let folder = try TemporaryFolder()
        let vault = PictureVault(imagesFolder: folder.url.appending(path: "Images"), encryptedStore: nil)
        let id = UUID()
        let data = Data([1, 2, 3])
        var written: [String] = []
        let image = try vault.keep(data, forClip: id, dimensions: (10, 20), sha: nil) { name in
            #expect((try? Data(contentsOf: vault.imagesFolder.appending(path: name))) == data)
            written.append(name)
        }
        #expect(written == ["\(id.uuidString).png"])
        #expect(image.file == written.first)
        #expect(image.width == 10 && image.height == 20)
        #expect(image.bytes == data.count)
        #expect(image.sha == "039058c6f2c0cb492c533b0a4d14ef77")
        var unreplaceable: Set<URL> = []
        #expect(vault.imageData(for: image, unreplaceable: &unreplaceable) == data)
        #expect(unreplaceable.isEmpty)
    }

    @Test("sealed bytes retain the supplied digest and open under their filename")
    func sealedRoundTrip() throws {
        let folder = try TemporaryFolder()
        let encrypted = EncryptedStore(keys: Keys(value: SymmetricKey(size: .bits256)))
        let vault = PictureVault(
            imagesFolder: folder.url.appending(path: "Images"), encryptedStore: encrypted)
        let data = Data(repeating: 0x89, count: 16)
        var writes = 0
        let image = try vault.keep(data, forClip: UUID(), dimensions: (2, 3), sha: "synthetic-cached-digest")
        {
            name in
            let bytes = try? Data(contentsOf: vault.imagesFolder.appending(path: name))
            #expect(bytes.map(EncryptedStore.isSealed) == true)
            #expect(bytes != data)
            writes += 1
        }
        #expect(writes == 1)
        #expect(image.sha == "synthetic-cached-digest")
        var unreplaceable: Set<URL> = []
        #expect(vault.imageData(for: image, unreplaceable: &unreplaceable) == data)
        #expect(unreplaceable.isEmpty)
    }

    @Test("a failed byte write never reports a newly owned picture")
    func writeFailureRetainsNoOwnership() throws {
        let folder = try TemporaryFolder()
        let blocked = folder.url.appending(path: "Images")
        try PrivateFile.write(Data("Synthetic blocking file.".utf8), to: blocked)
        let vault = PictureVault(imagesFolder: blocked, encryptedStore: nil)
        var writes = 0
        #expect(throws: ClipboardStoreError.couldNotWrite) {
            try vault.keep(Data([1]), forClip: UUID(), dimensions: (1, 1), sha: nil) { _ in writes += 1 }
        }
        #expect(writes == 0)
        #expect(try Data(contentsOf: blocked) == Data("Synthetic blocking file.".utf8))
    }

    @Test("write adaptation preserves the store's exhausted-storage category")
    func exhaustedStorage() throws {
        let folder = try TemporaryFolder()
        let vault = PictureVault(
            imagesFolder: folder.url.appending(path: "Images"),
            encryptedStore: EncryptedStore(keys: FullDiskKeys()))
        #expect(throws: ClipboardStoreError.diskFull) {
            try vault.storeImage(Data([1]), named: "synthetic.png")
        }
    }

    @Test("missing and unconfined filenames read nothing and alter no recovery state")
    func confinedReads() throws {
        let folder = try TemporaryFolder()
        let outside = folder.url.appending(path: "outside.png")
        let data = Data([1, 2, 3])
        try PrivateFile.write(data, to: outside)
        let vault = PictureVault(imagesFolder: folder.url.appending(path: "Images"), encryptedStore: nil)
        var unreplaceable: Set<URL> = []
        for name in ["../outside.png", "missing.png"] {
            let image = ClipImage(file: name, width: 1, height: 1, bytes: data.count)
            #expect(vault.imageData(for: image, unreplaceable: &unreplaceable) == nil)
        }
        #expect(unreplaceable.isEmpty)
        #expect(try Data(contentsOf: outside) == data)
        #expect(throws: ClipboardStoreError.couldNotWrite) {
            try vault.storeImage(Data([9]), named: "../outside.png")
        }
        #expect(try Data(contentsOf: outside) == data)
    }

    @Test("orphan enumeration retains index, undo and pending-arrival references")
    func protectedOrphans() throws {
        let folder = try TemporaryFolder()
        let vault = PictureVault(imagesFolder: folder.url.appending(path: "Images"), encryptedStore: nil)
        let wanted = "wanted.png"
        let held = "held.png"
        let unnamed = "unnamed.png"
        let stray = "stray.png"
        for name in [wanted, held, unnamed, stray] { try vault.storeImage(Data([1]), named: name) }
        let references = PictureReferences(heldPictures: [held], unnamedPictures: [unnamed])
        vault.forgetOrphanedImages(wanted: [wanted], references: references)
        let remaining = try FileManager.default.contentsOfDirectory(atPath: vault.imagesFolder.path)
        #expect(Set(remaining) == [wanted, held, unnamed])
    }

    @Test("filesystem reads preserve empty data and non-ASCII confined names")
    func filesystemReadForms() throws {
        let folder = try TemporaryFolder()
        let vault = PictureVault(imagesFolder: folder.url.appending(path: "Images"), encryptedStore: nil)
        let samples: [(String, Data)] = [("empty.png", Data()), ("synthetic-é.png", Data([1, 2, 3]))]
        var unreplaceable: Set<URL> = []
        for (name, data) in samples {
            try vault.storeImage(data, named: name)
            let image = ClipImage(file: name, width: 1, height: 1, bytes: data.count)
            #expect(vault.imageData(for: image, unreplaceable: &unreplaceable) == data)
        }
        let directory = vault.imagesFolder.appending(path: "directory.png")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let invalid = ClipImage(file: "directory.png", width: 1, height: 1, bytes: 0)
        #expect(vault.imageData(for: invalid, unreplaceable: &unreplaceable) == nil)
        #expect(unreplaceable.isEmpty)
    }

}
