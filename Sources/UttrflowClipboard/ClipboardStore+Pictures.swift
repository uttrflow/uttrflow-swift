// The clipboard store's pictures: writing, reading and forgetting the files beside the indexes.

public import Foundation

extension ClipboardStore {
    /// Where the pictures live: a folder beside the clipboard file, never inside that whole-file rewrite.
    public var imagesFolder: URL {
        pictureVault.imagesFolder
    }

    /// Records a noticed copy, writing its picture first so a clip never points at a file that is missing.
    @discardableResult
    public func record(
        _ noticed: NoticedClip, keeping retention: ClipRetention
    ) throws(ClipboardStoreError) -> [Clip] {
        guard let picture = noticed.picture else {
            return try record(noticed.clip, keeping: retention)
        }
        guard Self.isPersistable(noticed.clip) else {
            return try record(noticed.clip, keeping: retention)
        }
        // Hashed before it is written, so a screenshot copied twice costs a counter, not another file.
        let sha = ClipboardStore.digest(of: picture.data)
        var image = alreadyKept(sha, in: noticed.clip.origin)
        // A repeat whose file has gone brings the bytes back, under the name the kept clip already points at.
        if let kept = image, !pictureVault.isOnDisk(kept) {
            try restore(picture.data, as: kept.file)
        }
        if image == nil {
            image = try keep(
                picture.data, forClip: noticed.clip.id, width: picture.width,
                height: picture.height, sha: sha)
        }
        return try record(
            Self.rebuilding(
                noticed.clip, text: noticed.clip.text, richText: noticed.clip.richText,
                image: image),
            keeping: retention)
    }

    /// The picture already on disk for these bytes in this list, if one is there.
    private func alreadyKept(_ sha: String, in origin: ClipOrigin) -> ClipImage? {
        loaded().first { $0.origin == origin && $0.image?.sha == sha }?.image
    }

    /// Writes a picture's bytes back under the file name its clip already records.
    private func restore(_ data: Data, as name: String) throws(ClipboardStoreError) {
        try pictureVault.storeImage(data, named: name)
    }

    /// Keeps a picture on disk and answers with what a row needs; throws, since a missing file is forever.
    public func keep(
        _ data: Data, forClip id: UUID, width: Int, height: Int, sha: String? = nil
    ) throws(ClipboardStoreError) -> ClipImage {
        try pictureVault.keep(data, forClip: id, dimensions: (width, height), sha: sha) { name in
            pictureReferences.unnamedPictures.insert(name)
        }
    }

    /// A picture's bytes as a short hexadecimal digest; truncated because this is a cache key, not a signature.
    public static func digest(of data: Data) -> String {
        PictureVault.digest(of: data)
    }

    /// Whether a clip's picture file is still present without opening the file.
    public func hasImage(for image: ClipImage) -> Bool {
        pictureVault.hasImage(for: image)
    }

    /// The bytes of a clip's picture, or `nil` when the file has gone from under the app.
    public func imageData(for image: ClipImage) -> Data? {
        pictureVault.imageData(for: image, unreplaceable: &indexes.reader.unreplaceable)
    }

    /// Releases the pictures held for an undo, deleting each one no clip has taken back.
    public func forgetHeldPictures() {
        let released = pictureReferences.heldPictures.subtracting(loaded().compactMap(\.image?.file))
        pictureReferences.heldPictures = []
        pictureVault.removePictures(released)
    }

    /// Deletes pictures no clip refers to any more; best-effort, so a stuck file cannot cost a write.
    public func forgetOrphanedImages() {
        guard indexes.areTrustworthy else { return }
        let wanted = Set(loaded().compactMap(\.image?.file))
        pictureVault.forgetOrphanedImages(wanted: wanted, references: pictureReferences)
    }

    /// Reconciles the pictures folder once a launch, catching orphans no write of ours can notice.
    func sweepOnce() {
        // A list left empty by a failed read is what `areTrustworthy` refuses, so emptiness is honest.
        guard !hasSwept, indexes.areTrustworthy else { return }
        hasSwept = true
        forgetOrphanedImages()
    }
}
