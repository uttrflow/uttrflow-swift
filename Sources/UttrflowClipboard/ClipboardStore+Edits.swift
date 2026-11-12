// The clipboard store's edits to one clip or one collection, each settled in a single write.

public import Foundation

extension ClipboardStore {
    /// Pins a clip or unpins it, which is also how it stops ageing out; the panel decides the order.
    @discardableResult
    public func setPinned(
        _ isPinned: Bool, of id: UUID, keeping retention: ClipRetention
    ) throws(ClipboardStoreError) -> [Clip] {
        try change(id, keeping: retention) { $0.isPinned = isPinned }
    }

    /// Gives a clip a handle the user can find it by, or takes it away and lets the clip age again.
    @discardableResult
    public func setAlias(
        _ alias: String?, of id: UUID, keeping retention: ClipRetention
    ) throws(ClipboardStoreError) -> [Clip] {
        if let alias, loaded().contains(where: { $0.id != id && $0.alias == alias }) {
            throw .aliasAlreadyInUse
        }
        return try change(id, keeping: retention) { $0.alias = alias }
    }

    /// Sets a clip's name and its tags together, so one save from the rename sheet is one write.
    @discardableResult
    public func setLabels(
        alias: String?, tags: [String], of id: UUID, keeping retention: ClipRetention
    ) throws(ClipboardStoreError) -> [Clip] {
        if let alias, loaded().contains(where: { $0.id != id && $0.alias == alias }) {
            throw .aliasAlreadyInUse
        }
        return try change(id, keeping: retention) {
            $0.alias = alias
            $0.tags = tags
        }
    }

    /// The user's answer to whether a text clip is a secret, kept for its text from now on. See `Docs/clipboard-secrets.md`.
    @discardableResult
    public func setSecret(
        _ isSecret: Bool, of id: UUID, keeping retention: ClipRetention
    ) throws(ClipboardStoreError) -> [Clip] {
        var clips = loaded()
        guard let index = clips.firstIndex(where: { $0.id == id }), clips[index].image == nil,
            clips[index].files == nil,
            (clips[index].kind == .secret) != isSecret
        else { return policy.retained(clips, keeping: retention) }
        let clip = clips[index]
        // The answer is recorded before the clip changes, so a refused write leaves the clip unchanged.
        if isSecret {
            try secrecy.markSecret(clip.text)
            clips[index] = clip.reclassified(as: ClipClassification(kind: .secret, language: nil))
        } else {
            try secrecy.markNotSecret(clip.text)
            clips[index] = clip.reclassified(
                as: ClipKindDetector.classification(of: clip.text, askingSecret: false))
        }
        return try settled(clips, keeping: retention)
    }

    /// Replaces a clip's plain text, keeping its identity; an editable note is rebuilt, any other formatted form cleared.
    @discardableResult
    public func setText(
        _ text: String, of id: UUID, keeping retention: ClipRetention
    ) throws(ClipboardStoreError) -> [Clip] {
        try change(id, keeping: retention) { clip in
            // A file clip's words are its files' names, which an edit would only contradict.
            guard clip.files == nil else { return }
            guard let note = clip.richText, NotePromotion.isEditableNote(note) else {
                clip = Self.rebuilding(clip, text: text, richText: nil, image: clip.image)
                return
            }
            // One definition of the plain form, so the row, a paste and the checklist count agree.
            let edited = NotePromotion.editedNote(from: text)
            clip = Self.rebuilding(
                clip, text: RichTextPlainForm.plainText(fromHTML: edited), richText: edited,
                image: clip.image)
        }
    }

    /// Replaces a clip's formatted note, leaving its plain form recoverable.
    @discardableResult
    public func setRichText(
        _ richText: String?, of id: UUID, keeping retention: ClipRetention
    ) throws(ClipboardStoreError) -> [Clip] {
        try change(id, keeping: retention) { clip in
            guard clip.files == nil else { return }
            clip = Self.rebuilding(clip, text: clip.text, richText: richText, image: clip.image)
        }
    }

    /// Files a clip into a collection, or takes it out of one.
    @discardableResult
    public func setCategory(
        _ category: String?, of id: UUID, keeping retention: ClipRetention
    ) throws(ClipboardStoreError) -> [Clip] {
        try change(id, keeping: retention) { $0.category = category }
    }

    /// Moves every clip in one collection to another, or out of any when `destination` is `nil`, in one write.
    @discardableResult
    public func moveCategory(
        _ name: String, to destination: String?, keeping retention: ClipRetention
    ) throws(ClipboardStoreError) -> [Clip] {
        let clips = ClipEdits.movingCategory(
            name, to: destination, in: loaded(), keeping: retention, lastUsedOrder: &lastUsedOrder)
        return try settled(clips, keeping: retention)
    }

    /// Deletes a collection and every clip filed in it, in one write.
    @discardableResult
    public func deleteCategory(
        _ name: String, keeping retention: ClipRetention
    ) throws(ClipboardStoreError) -> [Clip] {
        try settled(loaded().filter { $0.category != name }, keeping: retention)
    }

    /// Deletes a collection for the panel's undo offer and returns the exact clips removed.
    package func deleteCategoryForUndo(
        _ name: String, keeping retention: ClipRetention
    ) throws(ClipboardStoreError) -> [Clip] {
        let clips = loaded()
        let deleted = clips.filter { $0.category == name }
        pictureReferences.heldPictures.formUnion(deleted.compactMap(\.image?.file))
        _ = try settled(clips.filter { $0.category != name }, keeping: retention)
        return deleted
    }
}
