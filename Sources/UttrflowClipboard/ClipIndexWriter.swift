// The clipboard index file writer.

import Foundation
import UttrflowCore

/// Persists one clipboard index inside its store actor.
struct ClipIndexWriter {
    /// Uses the same file envelope as its owning store.
    let encryptedStore: EncryptedStore?

    /// Writes a whole list atomically, or removes its file when nothing is left to keep.
    func persist(
        _ clips: [Clip], to url: URL, classifierVersion: Int?,
        classifierVersions: [URL: Int], legacyIndexes: inout Set<URL>
    ) throws(ClipboardStoreError) {
        do {
            guard !clips.isEmpty else {
                ClipboardStore.writes?.record()
                try removeFile(url)
                legacyIndexes.remove(url)
                return
            }
            let index = ClipboardIndex(
                clips: clips,
                classifierVersion: classifierVersion ?? classifierVersions[url]
                    ?? ClipboardIndex.currentClassifierVersion)
            let data = try JSONEncoder().encode(index)
            ClipboardStore.writes?.record(data)
            if let encryptedStore {
                try encryptedStore.write(encoded: data, to: url, preservingPreviousGeneration: true)
            } else {
                try PrivateFile.write(data, to: url)
            }
            legacyIndexes.remove(url)
        } catch {
            throw ClipboardStore.writeFailure(error)
        }
    }

    /// Deletes a file if it is there; nothing to delete is success, not a failure.
    private func removeFile(_ url: URL) throws {
        if let encryptedStore { return try encryptedStore.remove(url) }
        let manager = FileManager.default
        guard manager.fileExists(atPath: url.path(percentEncoded: false)) else { return }
        try manager.removeItem(at: url)
    }
}
