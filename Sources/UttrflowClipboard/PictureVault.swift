// Accesses clipboard pictures inside their confined folder.
import CryptoKit
import Foundation
import Security
import UttrflowCore

/// Accesses the picture files owned by a clipboard store.
struct PictureVault {
    let imagesFolder: URL
    private let encryptedStore: EncryptedStore?

    init(imagesFolder: URL, encryptedStore: EncryptedStore?) {
        self.imagesFolder = imagesFolder
        self.encryptedStore = encryptedStore
    }

    /// Whether a picture's file is still a file where the clip expects it.
    func isOnDisk(_ image: ClipImage) -> Bool {
        guard let url = pictureURL(image.file) else { return false }
        return (try? url.resourceValues(forKeys: [.isRegularFileKey]))?.isRegularFile == true
    }

    /// Whether a clip's picture file is still present without opening the file.
    func hasImage(for image: ClipImage) -> Bool {
        guard let url = pictureURL(image.file) else { return false }
        return FileManager.default.fileExists(atPath: url.path(percentEncoded: false))
    }

    /// Reads a confined picture file before opening or preserving its bytes.
    func imageData(for image: ClipImage, unreplaceable: inout Set<URL>) -> Data? {
        guard let url = pictureURL(image.file),
            let data = FileManager.default.contents(atPath: url.path(percentEncoded: false))
        else {
            return nil
        }
        return imageData(data, from: url, for: image, unreplaceable: &unreplaceable)
    }

    /// Keeps picture bytes before recording their ownership and returning row metadata.
    func keep(
        _ data: Data, forClip id: UUID, dimensions: (width: Int, height: Int), sha: String?,
        didWrite: (String) -> Void
    ) throws(ClipboardStoreError) -> ClipImage {
        let name = "\(id.uuidString).png"
        try storeImage(data, named: name)
        didWrite(name)
        return ClipImage(
            file: name, width: dimensions.width, height: dimensions.height, bytes: data.count,
            sha: sha ?? Self.digest(of: data))
    }

    /// Maps a picture write failure into the clipboard store's existing typed error.
    func storeImage(_ data: Data, named name: String) throws(ClipboardStoreError) {
        do {
            try writeImage(data, named: name)
        } catch {
            throw ClipboardStore.writeFailure(error)
        }
    }

    /// A picture's bytes as a short hexadecimal cache key, not a signature.
    static func digest(of data: Data) -> String {
        SHA256.hash(data: data).prefix(16).map { String(format: "%02x", $0) }.joined()
    }

    /// Removes disk pictures only after their index, undo and pending-write references are accounted for.
    func forgetOrphanedImages(wanted: Set<String>, references: PictureReferences) {
        let onDisk =
            (try? FileManager.default.contentsOfDirectory(
                at: imagesFolder, includingPropertiesForKeys: nil)) ?? []
        // A picture waiting for the write that will name it is not an orphan yet.
        removePictures(references.orphaned(onDisk: Set(onDisk.map(\.lastPathComponent)), wanted: wanted))
    }

    /// Opens picture bytes or preserves their unreadable file.
    func imageData(
        _ data: Data, from url: URL, for image: ClipImage, unreplaceable: inout Set<URL>
    ) -> Data? {
        guard let encryptedStore else { return data }
        if EncryptedStore.isSealed(data) {
            do { return try encryptedStore.open(data, for: image.file) } catch {
                if case StoreKeyError.unavailable(let status) = error,
                    status != Int32(errSecItemNotFound)
                {
                    return nil
                }
                let setAside = LocalStore.setAside(url, now: Date())
                if setAside == nil { unreplaceable.insert(url) }
                return nil
            }
        }
        switch encryptedStore.acceptsLegacyPlaintext() {
        case .open: break
        case .closed:
            if LocalStore.setAside(url, now: Date()) == nil { unreplaceable.insert(url) }
            return nil
        case .unknown: return nil
        }
        // A plaintext legacy image remains usable if its one-time sealing write is temporarily unavailable.
        do { try writeImage(data, named: image.file) } catch { return data }
        return data
    }

    /// Writes PNG bytes sealed with the shared key and the image filename as authenticated data.
    func writeImage(_ data: Data, named name: String) throws {
        guard let url = pictureURL(name) else { throw CocoaError(.fileWriteInvalidFileName) }
        guard let encryptedStore else { return try PrivateFile.write(data, to: url) }
        try PrivateFile.write(try encryptedStore.seal(data, for: name), to: url)
    }

    /// Deletes pictures by name; best-effort, so a stuck file cannot cost the write that asked.
    func removePictures(_ names: Set<String>) {
        for name in names {
            guard let url = pictureURL(name) else { continue }
            try? FileManager.default.removeItem(at: url)
        }
    }

    /// Where a picture named by the index lives, or nil when the name is not one file inside the Images folder.
    func pictureURL(_ name: String) -> URL? {
        guard ClipImage.isConfinedFileName(name) else { return nil }
        return imagesFolder.appending(path: name, directoryHint: .notDirectory)
    }

    /// Seals a plaintext image after confirming the migration has not raced with another store write.
    func sealLegacyPicture(_ data: Data, named name: String, unreplaceable: inout Set<URL>) {
        guard let url = pictureURL(name),
            FileManager.default.fileExists(atPath: url.path(percentEncoded: false)),
            let header = try? FileHandle(forReadingFrom: url),
            let prefix = try? header.read(upToCount: EncryptedStore.sealedHeaderLength)
        else { return }
        try? header.close()
        guard !EncryptedStore.isSealed(prefix) else { return }
        switch encryptedStore?.acceptsLegacyPlaintext() {
        case .open?: break
        case .closed?:
            if LocalStore.setAside(url, now: Date()) == nil { unreplaceable.insert(url) }
            return
        case .unknown?, nil: return
        }
        // The atomic replacement leaves the plaintext source in place when sealing or writing fails.
        try? writeImage(data, named: name)
    }
}
