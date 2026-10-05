// The store behind the clipboard panel: what has been copied, in memory and across two files.

public import UttrflowCore
public import Foundation
import CryptoKit
import Security
private import Synchronization

/// Counts the files a store writes while this is bound to `ClipboardStore.writes`.
package final class StoreWriteTally: Sendable {
    private let files = Mutex(0)
    private let bytes = Mutex<[Data]>([])

    package init() {}

    /// Answers how many files have been written or removed so far.
    package var count: Int { files.withLock { $0 } }

    /// Every encoded list written so far, in order; a removal adds nothing here.
    package var written: [Data] { bytes.withLock { $0 } }

    func record(_ data: Data? = nil) {
        files.withLock { $0 += 1 }
        if let data { bytes.withLock { $0.append(data) } }
    }
}

/// Everything the user has copied, kept on this Mac between launches. See `Docs/clipboard-store.md`.
public actor ClipboardStore {
    /// Every bound this store applies: records per pool, memory, days, and the largest clip kept at all.
    public static let defaultBudget = ClipboardBudget.standard

    /// The history file, injected so a test writes into a temporary directory rather than a real clipboard.
    private let file: URL

    /// What each pool of clips may cost, and for how long.
    private let budget: ClipboardBudget

    /// What the saved file is known to hold, which the migration off one file makes differ from memory.
    private var savedOnDisk: [Clip]?

    /// What the history file is known to hold, so an edit to a kept clip leaves it unwritten.
    private var historyOnDisk: [Clip]?

    /// The history and the saved clips as one list, or `nil` before the files have been read.
    private var wholeList: [Clip]?

    /// The latest persisted eviction order assigned by this store.
    private var lastUsedOrder: UInt64 = 0

    /// Whether this process has already reconciled the pictures folder; see ``sweepOnce()``.
    private var hasSwept = false
    /// Whether this process has tried sealing every legacy picture, including pictures of unreadable indexes.
    private var hasMigratedLegacyImages = false
    /// Holds the background task that checks picture headers and seals plaintext files.
    private var legacyImageMigration: Task<Void, Never>?
    /// Whether stored clips have been checked once with the detector shipped by this build.
    private var reclassifiedFiles: Set<URL> = []
    /// Pictures of deleted clips an undo can still bring back, left on disk until ``forgetHeldPictures()``.
    private var heldPictures: Set<String> = []
    /// Pictures written for a clip no index names yet, which only the write that follows can account for.
    private var unnamedPictures: Set<String> = []

    /// Whether a file this process read was there and could not be read, so its pictures are unknown.
    private var hasUnreadableIndex = false

    /// Files that could not be read or moved aside, which no write may replace.
    private var unreplaceable: Set<URL> = []

    /// Copies of damaged indexes waiting for the app to tell the user where they were saved.
    private var unreadableIndexSetAsides: [URL] = []

    /// Records that a use is in memory and not yet on disk; the next write, or `flushUse`, carries it.
    private var hasUnwrittenUse = false

    /// Sets how long a use waits in memory for another write before it is written on its own.
    private let useFlushDelay: Duration
    /// The shared file envelope used by the app; nil only for stores created without encryption in tests/tools.
    private let encryptedStore: EncryptedStore?

    /// Holds the pending write of a use, so a run of pastes costs one write rather than one each.
    private var useFlush: Task<Void, Never>?

    /// Counts the files written while bound, so a test can bound the writing without a clock.
    @TaskLocal package static var writes: StoreWriteTally?

    public init(
        file: URL = ClipboardStore.defaultFile(),
        budget: ClipboardBudget = ClipboardStore.defaultBudget,
        useFlushDelay: Duration = .seconds(30),
        encryptedStore: EncryptedStore? = nil
    ) {
        self.file = file
        self.budget = budget
        self.useFlushDelay = useFlushDelay
        self.encryptedStore = encryptedStore
    }

    /// Where the clipboard lives by default; versioned in the name so a new shape can sit beside it.
    public static func defaultFile(in directory: URL = .applicationSupportDirectory) -> URL {
        LocalStoreEntry.clipboard.location(in: directory)
    }

    // MARK: - Reading

    /// Everything still retained, newest first; the call ⇧⌘V waits on, and it does no I/O.
    public func clips(keeping retention: ClipRetention) -> [Clip] {
        let stored = loaded()
        let onDisk = keptOnDisk(stored, keeping: retention)
        // Time passes while the app idles, so the window drops clips here; the catch-up is best-effort.
        if onDisk.count != stored.count { try? save(onDisk) }
        return retained(stored, keeping: retention)
    }

    /// Returns each damaged index copy once, so the app can tell the user where it was preserved.
    public func takeUnreadableIndexSetAsides() -> [URL] {
        defer { unreadableIndexSetAsides = [] }
        return unreadableIndexSetAsides
    }

    // MARK: - Writing

    /// Records a copy, moving a repeat to the top rather than adding a row. See `Docs/clipboard-store.md`.
    @discardableResult
    public func record(
        _ clip: Clip, keeping retention: ClipRetention
    ) throws(ClipboardStoreError) -> [Clip] {
        // A picture has no text and is still worth keeping — the emptiness is the point.
        guard clip.image != nil || ClipContent.isWorthKeeping(clip.text) else {
            return retained(loaded(), keeping: retention)
        }
        // Refused rather than truncated: one copied log file would be rewritten on every later ⌘C.
        guard fitsLargestClipBound(clip) else {
            return retained(loaded(), keeping: retention)
        }

        let existing = loaded()
        let previous = Self.previous(for: clip, in: existing)
        var arrival = previous.map { inheriting($0, from: clip) } ?? clip
        if let alias = arrival.alias,
            existing.contains(where: { $0.id != arrival.id && $0.alias == alias })
        {
            arrival.alias = nil
        }
        arrival = arrival.orderedForEviction(nextUseOrder())

        // Prepended, not sorted in: a machine whose clock moved must not shuffle what the user sees.
        let displaced = previous.map { [$0.id] } ?? []
        let updated = [arrival] + existing.filter { !displaced.contains($0.id) }
        return try settled(updated, keeping: retention)
    }

    /// Restores a deleted clip as it was, unless a newer copy already exists.
    @discardableResult
    public func restore(
        _ clip: Clip, keeping retention: ClipRetention
    ) throws(ClipboardStoreError) -> [Clip] {
        let existing = loaded()
        guard !existing.contains(where: { $0.id == clip.id }) else {
            return retained(existing, keeping: retention)
        }
        guard let matching = Self.previous(for: clip, in: existing) else {
            return try settled([clip] + existing, keeping: retention)
        }
        let restored = restoring(clip, over: matching)
        let updated = existing.map { $0.id == matching.id ? restored : $0 }
        return try settled(updated, keeping: retention)
    }

    /// Moves a used clip to the top of its history or saved pool; the disk hears of it with the next write.
    @discardableResult
    public func markUsed(
        _ id: UUID, at moment: Date, keeping retention: ClipRetention
    ) -> [Clip] {
        var clips = loaded()
        guard let index = clips.firstIndex(where: { $0.id == id }) else {
            return retained(clips, keeping: retention)
        }
        clips[index] = clips[index].used(at: moment, order: nextUseOrder())
        clips = Self.orderedForDisplay(clips)
        let onDisk = keptOnDisk(clips, keeping: retention)
        // A clip that aged out is a real change, written now; a use alone is bookkeeping for a later eviction.
        guard onDisk.count == clips.count else {
            try? save(onDisk)
            return retained(clips, keeping: retention)
        }
        wholeList = onDisk
        hasUnwrittenUse = true
        scheduleUseFlush()
        return retained(clips, keeping: retention)
    }

    /// Writes a use still held in memory; a disk that refuses costs only the eviction order.
    public func flushUse() {
        useFlush?.cancel()
        useFlush = nil
        guard hasUnwrittenUse, let wholeList else { return }
        try? save(wholeList)
    }

    /// Writes held uses after a quiet spell, unless another write carries them first.
    private func scheduleUseFlush() {
        guard useFlush == nil else { return }
        let flushAfter = useFlushDelay
        useFlush = Task { [weak self] in
            try? await Task.sleep(for: flushAfter)
            guard !Task.isCancelled else { return }
            await self?.flushUse()
        }
    }

    /// Advances the store's persisted LRU sequence independently of wall-clock time.
    private func nextUseOrder() -> UInt64 {
        if lastUsedOrder < .max { lastUsedOrder += 1 }
        return lastUsedOrder
    }

    /// Forgets one clip and answers with what is left; an identifier that is not there is not an error.
    @discardableResult
    public func delete(
        _ id: UUID, keeping retention: ClipRetention, holdingPicture: Bool = false
    ) throws(ClipboardStoreError) -> [Clip] {
        if holdingPicture, let file = loaded().first(where: { $0.id == id })?.image?.file {
            heldPictures.insert(file)
        }
        return try settled(loaded().filter { $0.id != id }, keeping: retention)
    }

    /// Forgets the history and deliberately not the saved clips. See `Docs/clipboard-store.md`.
    @discardableResult
    public func deleteEverything(
        keeping retention: ClipRetention
    ) throws(ClipboardStoreError)
        -> [Clip]
    {
        let saved = loaded().filter(\.isKept)
        // Reaches the disk here rather than at the next write: clearing and then quitting must stick.
        try save(saved)
        // A copy set aside from the history file is history too; the saved file's copies are saved clips.
        do { try LocalStore.removeSetAside(file) } catch { throw Self.writeFailure(error) }
        return retained(saved, keeping: retention)
    }

    /// Forgets every copy of one dictation, pinned or edited; `spoken` finds copies older than the link.
    @discardableResult
    public func deleteCopies(
        ofDictation id: UUID, saying spoken: String?, keeping retention: ClipRetention
    ) throws(ClipboardStoreError) -> [Clip] {
        let stored = loaded()
        var changed = false
        let left: [Clip] = stored.compactMap { clip in
            guard clip.isCopy(ofDictation: id, saying: spoken) else { return clip }
            changed = true
            let others = clip.dictations.filter { $0 != id }
            // A clip another dictation still copies loses only this dictation's link.
            return others.isEmpty ? nil : Self.relinking(clip, to: others)
        }
        guard changed else { return retained(stored, keeping: retention) }
        return try settled(left, keeping: retention)
    }

    /// Removes every clip, pinned ones included, which is what resetting personalisation promises.
    public func forgetEverything() throws(ClipboardStoreError) {
        try save([])
        do {
            try LocalStore.removeSetAside(file)
            try LocalStore.removeSetAside(savedFile)
        } catch {
            throw Self.writeFailure(error)
        }
    }

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

    /// Replaces a clip's plain text and clears the old formatted form, keeping its identity.
    @discardableResult
    public func setText(
        _ text: String, of id: UUID, keeping retention: ClipRetention
    ) throws(ClipboardStoreError) -> [Clip] {
        try change(id, keeping: retention) { clip in
            clip = Self.rebuilding(clip, text: text, richText: nil, image: clip.image)
        }
    }

    // MARK: - Pictures

    /// Where the pictures live: a folder beside the clipboard file, never inside that whole-file rewrite.
    public var imagesFolder: URL {
        file.deletingLastPathComponent().appending(
            path: LocalStoreEntry.clipboardImages.name, directoryHint: .isDirectory)
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
        if let kept = image, !isOnDisk(kept) {
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

    /// Whether a picture's file is still a file where the clip expects it.
    private func isOnDisk(_ image: ClipImage) -> Bool {
        let url = imagesFolder.appending(path: image.file, directoryHint: .notDirectory)
        return (try? url.resourceValues(forKeys: [.isRegularFileKey]))?.isRegularFile == true
    }

    /// Writes a picture's bytes back under the file name its clip already records.
    private func restore(_ data: Data, as name: String) throws(ClipboardStoreError) {
        do {
            try writeImage(data, named: name)
        } catch {
            throw Self.writeFailure(error)
        }
    }

    /// Keeps a picture on disk and answers with what a row needs; throws, since a missing file is forever.
    public func keep(
        _ data: Data, forClip id: UUID, width: Int, height: Int, sha: String? = nil
    ) throws(ClipboardStoreError) -> ClipImage {
        let name = "\(id.uuidString).png"
        do {
            try writeImage(data, named: name)
        } catch {
            throw Self.writeFailure(error)
        }
        unnamedPictures.insert(name)
        return ClipImage(
            file: name, width: width, height: height, bytes: data.count,
            sha: sha ?? ClipboardStore.digest(of: data))
    }

    /// A picture's bytes as a short hexadecimal digest; truncated because this is a cache key, not a signature.
    public static func digest(of data: Data) -> String {
        SHA256.hash(data: data).prefix(16).map { String(format: "%02x", $0) }.joined()
    }

    /// Whether a clip's picture file is still present without opening the file.
    public func hasImage(for image: ClipImage) -> Bool {
        FileManager.default.fileExists(
            atPath: imagesFolder.appending(path: image.file, directoryHint: .notDirectory)
                .path(percentEncoded: false))
    }

    /// The bytes of a clip's picture, or `nil` when the file has gone from under the app.
    public func imageData(for image: ClipImage) -> Data? {
        let url = imagesFolder.appending(path: image.file, directoryHint: .notDirectory)
        guard let data = try? Data(contentsOf: url) else { return nil }
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
        // A plaintext legacy image remains usable if its one-time sealing write is temporarily unavailable.
        do { try writeImage(data, named: image.file) } catch { return data }
        return data
    }

    /// Writes PNG bytes sealed with the shared key and the image filename as authenticated data.
    private func writeImage(_ data: Data, named name: String) throws {
        let url = imagesFolder.appending(path: name, directoryHint: .notDirectory)
        guard let encryptedStore else { return try PrivateFile.write(data, to: url) }
        try PrivateFile.write(try encryptedStore.seal(data, for: name), to: url)
    }

    /// Releases the pictures held for an undo, deleting each one no clip has taken back.
    public func forgetHeldPictures() {
        let released = heldPictures.subtracting(loaded().compactMap(\.image?.file))
        heldPictures = []
        removePictures(released)
    }

    /// Deletes pictures no clip refers to any more; best-effort, so a stuck file cannot cost a write.
    public func forgetOrphanedImages() {
        guard indexesAreTrustworthy else { return }
        let wanted = Set(loaded().compactMap(\.image?.file))
        let onDisk =
            (try? FileManager.default.contentsOfDirectory(
                at: imagesFolder, includingPropertiesForKeys: nil)) ?? []
        // A picture waiting for the write that will name it is not an orphan yet.
        removePictures(
            Set(onDisk.map(\.lastPathComponent)).subtracting(wanted)
                .subtracting(heldPictures).subtracting(unnamedPictures))
    }

    /// Deletes pictures by name; best-effort, so a stuck file cannot cost the write that asked.
    private func removePictures(_ names: Set<String>) {
        for name in names {
            try? FileManager.default.removeItem(
                at: imagesFolder.appending(path: name, directoryHint: .notDirectory))
        }
    }

    /// Replaces a clip's formatted note, leaving its plain form recoverable.
    @discardableResult
    public func setRichText(
        _ richText: String?, of id: UUID, keeping retention: ClipRetention
    ) throws(ClipboardStoreError) -> [Clip] {
        try change(id, keeping: retention) { clip in
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
        var clips = loaded()
        var freshlyUnkept: Set<UUID> = []
        for index in clips.indices where clips[index].category == name {
            let wasKept = clips[index].isKept
            clips[index].category = destination
            if resetAgeIfUnkept(&clips[index], wasKept: wasKept, keeping: retention) {
                freshlyUnkept.insert(clips[index].id)
            }
        }
        if !freshlyUnkept.isEmpty {
            clips =
                clips.filter { freshlyUnkept.contains($0.id) }
                + clips.filter { !freshlyUnkept.contains($0.id) }
        }
        return try settled(clips, keeping: retention)
    }

    /// Deletes a collection and every clip filed in it, in one write.
    @discardableResult
    public func deleteCategory(
        _ name: String, keeping retention: ClipRetention
    ) throws(ClipboardStoreError) -> [Clip] {
        try settled(loaded().filter { $0.category != name }, keeping: retention)
    }

    // MARK: - The rules

    /// The clip this arrival is another copy of, if the same list already holds it.
    static func previous(for clip: Clip, in existing: [Clip]) -> Clip? {
        // Only within one list: a sentence dictated and the same sentence copied are two clips.
        let sameList = existing.filter { $0.origin == clip.origin }
        if let sha = clip.image?.sha {
            return sameList.first { $0.image?.sha == sha }
        }
        guard clip.image == nil else { return nil }
        return sameList.first { $0.text == clip.text && $0.image == nil }
    }

    /// A copy of a clip keeping its identity and every field the user chose, differing only where named.
    static func rebuilding(
        _ clip: Clip, text: String, richText: String?, image: ClipImage?
    ) -> Clip {
        let classified =
            image == nil
            ? ClipKindDetector.classification(of: text)
            : ClipClassification(kind: .image, language: nil)
        return Clip(
            id: clip.id, text: text, kind: classified.kind, copiedAt: clip.copiedAt,
            source: clip.source, origin: clip.origin, dictations: clip.dictations,
            // An unlinked dictation copy keeps its first words, the only thing deleting its dictation can match.
            dictatedText: clip.dictatedText ?? (clip.isUnlinkedDictationCopy ? clip.text : nil),
            lastUsedAt: clip.lastUsedAt,
            lastUsedOrder: clip.lastUsedOrder,
            language: classified.language, richText: richText, image: image,
            alias: clip.alias, category: clip.category, isPinned: clip.isPinned,
            timesCopied: clip.timesCopied)
    }

    /// The same clip, copying only `dictations`.
    static func relinking(_ clip: Clip, to dictations: [UUID]) -> Clip {
        Clip(
            id: clip.id, text: clip.text, kind: clip.kind, copiedAt: clip.copiedAt,
            source: clip.source, origin: clip.origin, dictations: dictations,
            dictatedText: clip.dictatedText, lastUsedAt: clip.lastUsedAt,
            lastUsedOrder: clip.lastUsedOrder,
            language: clip.language, richText: clip.richText, image: clip.image,
            alias: clip.alias, category: clip.category, isPinned: clip.isPinned,
            timesCopied: clip.timesCopied)
    }

    /// Carries what the user chose about a clip onto the copy that has just replaced it.
    private func inheriting(_ previous: Clip, from arrival: Clip) -> Clip {
        // A kept clip the user chose to keep on disk is never made a memory-only secret by a repeat of the same text.
        let staysKept = previous.isKept && Self.isPersistable(previous) && !Self.isPersistable(arrival)
        let classified = staysKept ? previous : arrival
        return Clip(
            id: previous.id, text: arrival.text, kind: classified.kind, copiedAt: arrival.copiedAt,
            source: arrival.source,
            // Named rather than defaulted, so a repeat cannot quietly become a ⌘C.
            origin: previous.origin,
            // Both dictations, so the clip goes only once neither of them is left.
            dictations: previous.dictations
                + arrival.dictations.filter {
                    !previous.dictations.contains($0)
                },
            dictatedText: previous.dictatedText,
            // Copying something again is reaching for it, so the eviction clock moves too.
            lastUsedAt: arrival.copiedAt,
            // Detected from the text recorded now and from this pasteboard, unless the kind stayed the kept clip's.
            language: classified.language,
            // A plain repeat keeps the clip's rich text, which may be a note the user wrote in the panel.
            richText: arrival.richText ?? previous.richText,
            // The file already on disk, not the one just written; the arrival's would strand it.
            image: previous.image ?? arrival.image,
            // Everything the user decided stays with the clip they decided it about.
            alias: previous.alias, category: previous.category, isPinned: previous.isPinned,
            // One more time, not a new clip; saturates at Int.max instead of trapping.
            timesCopied: previous.timesCopied == .max ? .max : previous.timesCopied + 1)
    }

    /// Restoring a duplicate revives the deleted clip's choices without rewinding the newer copy.
    private func restoring(_ deleted: Clip, over newer: Clip) -> Clip {
        Clip(
            id: newer.id, text: newer.text, kind: newer.kind, copiedAt: newer.copiedAt,
            source: newer.source, origin: newer.origin,
            dictations: newer.dictations
                + deleted.dictations.filter { !newer.dictations.contains($0) },
            dictatedText: newer.dictatedText ?? deleted.dictatedText,
            lastUsedAt: newer.lastUsedAt, lastUsedOrder: newer.lastUsedOrder,
            language: newer.language, richText: newer.richText, image: newer.image,
            alias: newer.alias ?? deleted.alias, category: newer.category ?? deleted.category,
            isPinned: newer.isPinned || deleted.isPinned,
            timesCopied: newer.timesCopied == .max ? .max : newer.timesCopied + 1)
    }

    /// Applies one edit to one clip, then the retention rules, then writes.
    private func change(
        _ id: UUID, keeping retention: ClipRetention, _ edit: (inout Clip) -> Void
    ) throws(ClipboardStoreError) -> [Clip] {
        var clips = loaded()
        if let index = clips.firstIndex(where: { $0.id == id }) {
            let wasKept = clips[index].isKept
            edit(&clips[index])
            guard fitsLargestClipBound(clips[index]) else { throw .couldNotWrite }
            if resetAgeIfUnkept(&clips[index], wasKept: wasKept, keeping: retention) {
                let fresh = clips.remove(at: index)
                clips.insert(fresh, at: 0)
            }
        }
        return try settled(clips, keeping: retention)
    }

    /// Resets a clip's age when this edit removes its last keeping marker.
    private func resetAgeIfUnkept(
        _ clip: inout Clip, wasKept: Bool, keeping retention: ClipRetention
    ) -> Bool {
        guard wasKept && !clip.isKept else { return false }
        clip = clip.recopied(at: retention.now, order: nextUseOrder())
        return true
    }

    /// Writes what may stay on the disk and answers with what may be shown. See `Docs/retention-clock.md`.
    private func settled(
        _ clips: [Clip], keeping retention: ClipRetention
    ) throws(ClipboardStoreError) -> [Clip] {
        let unique = Self.uniqueAliases(in: Self.orderedForDisplay(clips))
        try save(keptOnDisk(unique, keeping: retention))
        return retained(unique, keeping: retention)
    }

    /// Keeps the first clip holding an alias and removes that alias from later clips.
    private static func uniqueAliases(in clips: [Clip]) -> [Clip] {
        var aliases: Set<String> = []
        return clips.map { clip in
            guard let alias = clip.alias else { return clip }
            guard aliases.insert(alias).inserted else {
                var unnamed = clip
                unnamed.alias = nil
                return unnamed
            }
            return clip
        }
    }

    /// Spares every kept clip, then applies the window and the per-pool caps to the history.
    private func retained(_ clips: [Clip], keeping retention: ClipRetention) -> [Clip] {
        held(clips, keeping: retention) { survives($0, keeping: retention) }
    }

    /// The same, plus what a clock too far ahead to be believed says is past. See `Docs/retention-clock.md`.
    private func keptOnDisk(_ clips: [Clip], keeping retention: ClipRetention) -> [Clip] {
        held(clips, keeping: retention) { clip in
            let window = window(for: clip, keeping: retention)
            return window.keeps(clip.copiedAt) || !window.mayDelete(clip.copiedAt)
        }
    }

    /// The caps and quotas, over whichever clips the window has spared.
    private func held(
        _ clips: [Clip], keeping retention: ClipRetention, _ survives: (Clip) -> Bool
    ) -> [Clip] {
        // Kept clips are not candidates at all: their pool has no tier to be an exception to.
        let history = clips.filter { ClipClass(of: $0).isEvictable }
        let surviving = history.filter(survives)

        // Per pool, so a morning of dictating cannot push out yesterday's ⌘C or a picture.
        var taken: [ClipClass: Int] = [:]
        var within: Set<UUID> = []
        for clip in surviving {
            let pool = ClipClass(of: clip)
            guard let tier = budget.tier(for: pool), taken[pool, default: 0] < tier.items
            else { continue }
            taken[pool, default: 0] += 1
            within.insert(clip.id)
        }

        // Filtered rather than concatenated, which keeps arrival order in one pass and without a sort.
        let kept = clips.filter { !ClipClass(of: $0).isEvictable || within.contains($0.id) }
        return withinDisk(withinMemory(kept))
    }

    /// What a clip costs this process to hold: its words, and deliberately not its picture's file.
    static func weight(of clip: Clip) -> Int {
        clip.text.utf8.count + (clip.richText?.utf8.count ?? 0)
    }

    /// Applies the same text-and-rich-text bound to copied clips and every stored edit.
    private func fitsLargestClipBound(_ clip: Clip) -> Bool {
        budget.largestClip <= 0 || Self.weight(of: clip) <= budget.largestClip
    }

    /// What a list of clips costs this process to hold.
    static func weight(of clips: [Clip]) -> Int {
        clips.reduce(0) { $0 + weight(of: $1) }
    }

    /// Whether this clip may cross a launch boundary; secrets stay in this process only.
    private static func isPersistable(_ clip: Clip) -> Bool { clip.kind != .secret }

    /// Drops the least recently used clips of a text pool until it fits its memory quota.
    private func withinMemory(_ clips: [Clip]) -> [Clip] {
        var dropped: Set<UUID> = []
        // Only the text pools: a picture's bytes are a file, and its thumbnail is bounded elsewhere.
        for pool in [ClipClass.copied, .dictation] {
            guard let tier = budget.tier(for: pool), tier.bytes > 0 else { continue }
            let list = clips.filter { ClipClass(of: $0) == pool }
            var weight = Self.weight(of: list)
            guard weight > tier.bytes else { continue }
            for clip in list.sorted(by: { ($0.lastUsedOrder ?? 0) < ($1.lastUsedOrder ?? 0) })
            where weight > tier.bytes {
                dropped.insert(clip.id)
                weight -= Self.weight(of: clip)
            }
        }
        return clips.filter { !dropped.contains($0.id) }
    }

    /// Drops the least recently used pictures until the folder fits its disk budget.
    private func withinDisk(_ clips: [Clip]) -> [Clip] {
        guard budget.disk > 0 else { return clips }
        // Pinned pictures count toward the budget so pinning many of them cannot push the unpinned pool past the bound.
        let pictures = clips.filter { $0.kind == .image || $0.image != nil }
        var weight = pictures.reduce(0) { $0 + ($1.image?.bytes ?? 0) }
        guard weight > budget.disk else { return clips }
        var dropped: Set<UUID> = []
        // Only the un-kept pictures may be evicted; kept ones are exempt by the kept pool's rule.
        let evictable =
            pictures
            .filter { !$0.isKept }
            .sorted { ($0.lastUsedOrder ?? 0) < ($1.lastUsedOrder ?? 0) }
        for clip in evictable where weight > budget.disk {
            dropped.insert(clip.id)
            weight -= clip.image?.bytes ?? 0
        }
        return clips.filter { !dropped.contains($0.id) }
    }

    /// Whether an unkept clip is still inside its window; zero days keeps nothing.
    private func survives(_ clip: Clip, keeping retention: ClipRetention) -> Bool {
        window(for: clip, keeping: retention).keeps(clip.copiedAt)
    }

    /// The promise this clip is held to, as the rule the three stores share states it.
    private func window(for clip: Clip, keeping retention: ClipRetention) -> RetentionWindow {
        // The pool's own window where it has one, and the user's transcript setting for a dictation.
        let clipClass = ClipClass(of: clip)
        let days =
            clipClass == .dictation
            ? (retention.dictationDays ?? budget.tier(for: clipClass)?.days ?? retention.days)
            : (budget.tier(for: clipClass)?.days ?? retention.days)
        return RetentionWindow(days: days, now: retention.now)
    }

    // MARK: - The two files

    /// Where saved clips are kept: beside the history and never in it. See `Docs/clipboard-store.md`.
    var savedFile: URL {
        file.deletingLastPathComponent()
            .appending(path: LocalStoreEntry.savedClips.name, directoryHint: .notDirectory)
    }

    /// The list, read from disk the first time and from memory thereafter.
    private func loaded() -> [Clip] {
        if let wholeList { return wholeList }
        // A clipboard written before the split keeps its saved clips in the history file.
        let fromSavedFile = read(savedFile).filter(Self.isPersistable)
        savedOnDisk = fromSavedFile
        // A move interrupted between the two writes leaves a clip in both files, and the saved copy wins.
        let savedIDs = Set(fromSavedFile.map(\.id))
        let fromHistoryFile = read(file).filter(Self.isPersistable)
        // An unreplaceable file is unknown rather than empty, so every save still meets its refusal.
        historyOnDisk = unreplaceable.contains(file) ? nil : fromHistoryFile
        let stored = fromSavedFile + fromHistoryFile.filter { !savedIDs.contains($0.id) }
        let list = Self.uniqueAliases(
            in: Self.interleaving(
                saved: Self.orderedForDisplay(stored.filter(\.isKept)),
                history: Self.orderedForDisplay(stored.filter { !$0.isKept })))
        let ordered = list.enumerated().sorted { left, right in
            switch (left.element.lastUsedOrder, right.element.lastUsedOrder) {
            case (let leftOrder?, let rightOrder?):
                return leftOrder == rightOrder ? left.offset < right.offset : leftOrder < rightOrder
            case (nil, nil):
                let leftDate = left.element.lastUsedAt
                let rightDate = right.element.lastUsedAt
                return leftDate == rightDate ? left.offset < right.offset : leftDate < rightDate
            case (nil, .some):
                return true
            case (.some, nil):
                return false
            }
        }
        var orderByIndex = Array(repeating: UInt64(0), count: list.count)
        for (order, clip) in ordered.enumerated() {
            orderByIndex[clip.offset] = UInt64(order + 1)
        }
        let normalized = list.enumerated().map { pair in
            pair.element.orderedForEviction(orderByIndex[pair.offset])
        }
        lastUsedOrder = UInt64(normalized.count)
        wholeList = normalized
        sweepOnce()
        migrateLegacyImagesOnce()
        return normalized
    }

    /// Starts the picture pass off the clipboard actor so sealed files do not slow down ⇧⌘V.
    private func migrateLegacyImagesOnce() {
        guard !hasMigratedLegacyImages else { return }
        hasMigratedLegacyImages = true
        guard encryptedStore != nil else { return }
        let folder = imagesFolder
        legacyImageMigration = Task.detached(priority: .utility) { [weak self] in
            await LegacyPictureMigration().run(in: folder) { [weak self] data, name in
                await self?.sealLegacyPicture(data, named: name)
            }
        }
    }

    /// Waits for the background migration in tests that inspect the migrated files.
    func waitForLegacyPictureMigration() async {
        await legacyImageMigration?.value
    }

    /// Seals a plaintext image after confirming the migration has not raced with another store write.
    private func sealLegacyPicture(_ data: Data, named name: String) {
        let url = imagesFolder.appending(path: name, directoryHint: .notDirectory)
        guard FileManager.default.fileExists(atPath: url.path(percentEncoded: false)),
            let header = try? FileHandle(forReadingFrom: url),
            let prefix = try? header.read(upToCount: EncryptedStore.sealedHeaderLength)
        else { return }
        try? header.close()
        guard !EncryptedStore.isSealed(prefix) else { return }
        // The atomic replacement leaves the plaintext source in place when sealing or writing fails.
        try? writeImage(data, named: name)
    }

    /// Rechecks each readable index once so a corrected detector can mask clips it previously missed.
    private func reclassifyStoredClips(_ clips: [Clip], at url: URL) -> [Clip] {
        guard reclassifiedFiles.insert(url).inserted, !hasUnreadableIndex, !unreplaceable.contains(url)
        else { return clips }
        guard !LocalStore.hasSetAside(url) else { unreplaceable.insert(url); return clips }
        let updated = clips.map { clip in
            clip.reclassified(as: ClipKindDetector.classification(of: clip.text))
        }
        guard updated != clips else { return clips }
        // A secret clip's picture is removed only after its replacement index is safely written.
        let becameSecret = Set(updated.filter { $0.kind == .secret }.map(\.id))
        let picturesToRemove = Set(clips.filter { becameSecret.contains($0.id) }.compactMap(\.image?.file))
        do {
            let persistable = updated.filter(Self.isPersistable)
            if persistable == clips { return updated }
            try persist(persistable, to: url)
            removePictures(picturesToRemove)
            return updated
        } catch {
            // Keep the old persisted classification if the replacement cannot be committed.
            return clips
        }
    }

    /// The two lists as one, newest used first; a merge keeps each persisted pool's order intact.
    private static func interleaving(saved: [Clip], history: [Clip]) -> [Clip] {
        var out: [Clip] = []
        out.reserveCapacity(saved.count + history.count)
        var left = 0
        var right = 0
        while left < saved.count, right < history.count {
            if precedesForDisplay(saved[left], history[right]) {
                out.append(saved[left])
                left += 1
            } else {
                out.append(history[right])
                right += 1
            }
        }
        out.append(contentsOf: saved[left...])
        out.append(contentsOf: history[right...])
        return out
    }

    /// Sorts each persisted pool by its monotonic use order, retaining arrival order for legacy clips.
    private static func orderedForDisplay(_ clips: [Clip]) -> [Clip] {
        clips.enumerated().sorted { left, right in
            if precedesForDisplay(left.element, right.element) { return true }
            if precedesForDisplay(right.element, left.element) { return false }
            return left.offset < right.offset
        }.map(\.element)
    }

    /// Compares by persisted use order and falls back to arrival time only before an order was stored.
    private static func precedesForDisplay(_ left: Clip, _ right: Clip) -> Bool {
        switch (left.lastUsedOrder, right.lastUsedOrder) {
        case (let leftOrder?, let rightOrder?):
            return leftOrder == rightOrder ? left.copiedAt > right.copiedAt : leftOrder > rightOrder
        case (.some, nil): return true
        case (nil, .some): return false
        case (nil, nil): return left.copiedAt > right.copiedAt
        }
    }

    /// Reconciles the pictures folder once a launch, catching orphans no write of ours can notice.
    private func sweepOnce() {
        // A list left empty by a failed read is what `indexesAreTrustworthy` refuses, so emptiness is honest.
        guard !hasSwept, indexesAreTrustworthy else { return }
        hasSwept = true
        forgetOrphanedImages()
    }

    /// Whether every file that can name a picture was read, so a file named by neither is an orphan.
    private var indexesAreTrustworthy: Bool {
        !hasUnreadableIndex && !LocalStore.hasSetAside(file) && !LocalStore.hasSetAside(savedFile)
    }

    /// Reads one file, setting an unreadable one aside and remembering that its pictures are unknown.
    private func read(_ url: URL) -> [Clip] {
        guard !unreplaceable.contains(url) else { return [] }
        let stored = encryptedStore?.read([Clip].self, from: url) ?? LocalStore.read([Clip].self, from: url)
        if case .unreadable(let setAside) = stored {
            hasUnreadableIndex = true
            if let setAside {
                unreadableIndexSetAsides.append(setAside)
            } else {
                unreplaceable.insert(url)
            }
        }
        let clips = stored.value ?? []
        let reclassified = reclassifyStoredClips(clips, at: url)
        if url == savedFile { savedOnDisk = reclassified.filter(Self.isPersistable) }
        if url == file { historyOnDisk = reclassified.filter(Self.isPersistable) }
        return reclassified
    }

    /// Writes the list to memory and then to disk, filing each clip by what ``Clip/isKept`` says.
    private func save(_ clips: [Clip]) throws(ClipboardStoreError) {
        // First, so the launch sweep this read can trigger still sees what is waiting to be named.
        let before = Set(loaded().compactMap(\.image?.file))
        let named = Set(clips.compactMap(\.image?.file))
        // A picture written for a clip this list drops is ours to remove, whether the writes below land or not.
        let unnamed = unnamedPictures.subtracting(named).subtracting(heldPictures)
        unnamedPictures = []
        defer { removePictures(unnamed) }
        let wasSaved = savedOnDisk ?? []
        let persistable = clips.filter(Self.isPersistable)
        let nowSaved = persistable.filter(\.isKept)
        let nowHistory = persistable.filter { !$0.isKept }

        // Memory first and unconditionally, so a refusing disk does not also cost the change itself.
        wholeList = clips
        // This write carries every use held in memory, so none is left waiting for its own.
        hasUnwrittenUse = false
        useFlush?.cancel()
        useFlush = nil

        // Every clip reaches its new file before leaving its old one, so a refusing disk never loses one.
        let bridge = Self.bridging(persistable, from: wasSaved, into: nowHistory)
        if bridge != wasSaved {
            try persist(bridge, to: savedFile)
            savedOnDisk = bridge
        }
        if nowHistory != historyOnDisk {
            try persist(nowHistory, to: file)
            historyOnDisk = nowHistory
        }
        if nowSaved != bridge {
            try persist(nowSaved, to: savedFile)
            savedOnDisk = nowSaved
        }

        // Only the files that stopped being referenced, so a picture no read could vouch for is never touched.
        removePictures(before.subtracting(named).subtracting(heldPictures))
    }

    /// What the saved file holds while clips move: the new saved list, plus the old copy of any leaving it.
    private static func bridging(
        _ clips: [Clip], from wasSaved: [Clip], into nowHistory: [Clip]
    ) -> [Clip] {
        let leaving = Set(nowHistory.map(\.id)).intersection(wasSaved.map(\.id))
        guard !leaving.isEmpty else { return clips.filter(\.isKept) }
        let old = Dictionary(wasSaved.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        return clips.compactMap { $0.isKept ? $0 : leaving.contains($0.id) ? old[$0.id] : nil }
    }

    /// Writes a whole list atomically, or removes its file when nothing is left to keep.
    private func persist(_ clips: [Clip], to url: URL) throws(ClipboardStoreError) {
        // A file that could be neither read nor moved aside is the user's only copy, so it is not replaced.
        guard !unreplaceable.contains(url) else { throw .couldNotWrite }
        do {
            guard !clips.isEmpty else {
                Self.writes?.record()
                try removeFile(url)
                return
            }
            let data = try JSONEncoder().encode(clips)
            Self.writes?.record(data)
            if let encryptedStore {
                try encryptedStore.write(clips, to: url)
            } else {
                try PrivateFile.write(data, to: url)
            }
        } catch {
            throw Self.writeFailure(error)
        }
    }

    /// Distinguishes exhausted storage from other file-system failures.
    package static func writeFailure(_ error: any Error) -> ClipboardStoreError {
        let nsError = error as NSError
        if nsError.domain == NSPOSIXErrorDomain, nsError.code == Int(ENOSPC) { return .diskFull }
        if let underlying = nsError.userInfo[NSUnderlyingErrorKey] as? any Error {
            return writeFailure(underlying)
        }
        return .couldNotWrite
    }

    /// Deletes a file if it is there; nothing to delete is success, not a failure.
    private func removeFile(_ url: URL) throws {
        let manager = FileManager.default
        guard manager.fileExists(atPath: url.path(percentEncoded: false)) else { return }
        try manager.removeItem(at: url)
    }
}
