// The store behind the clipboard panel: what has been copied, in memory and across two files.

public import UttrflowCore
public import Foundation
import CryptoKit
private import Synchronization

/// The settled clipboard after undo and whether the restored alias conflicts.
public struct ClipboardRestoreResult: Sendable, Equatable {
    public let clips: [Clip]
    public let aliasWasAlreadyInUse: Bool

    package init(clips: [Clip], aliasWasAlreadyInUse: Bool) {
        self.clips = clips
        self.aliasWasAlreadyInUse = aliasWasAlreadyInUse
    }
}

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

    /// The retention rules over `budget`.
    private let policy: RetentionPolicy

    /// The loaded index contents and their combined live list.
    private var indexSnapshot = ClipIndexSnapshot()

    /// The latest persisted eviction order assigned by this store.
    private var lastUsedOrder: UInt64 = 0

    /// Whether this process has already reconciled the pictures folder; see ``sweepOnce()``.
    private var hasSwept = false
    /// Whether this process has tried sealing every legacy picture, including pictures of unreadable indexes.
    private var hasMigratedLegacyImages = false
    /// Holds the background task that checks picture headers and seals plaintext files.
    private var legacyImageMigration: Task<Void, Never>?
    /// Reads clipboard indexes and holds their recovery state inside this actor.
    private var indexReader: ClipboardIndexReader
    /// Holds detector migrations so reads can return while classification runs in the background.
    private var classifierMigrations: [URL: Task<Void, Never>] = [:]
    /// Holds picture references across undo, new arrivals and refused index writes.
    private var pictureReferences = PictureReferences()

    /// Records that memory holds a use or a refused change the disk lacks; the next write, or `flushUse`, carries it.
    private var hasUnwrittenUse = false

    /// Sets how long a use waits in memory for another write before it is written on its own.
    private let useFlushDelay: Duration
    /// The shared file envelope used by the app; nil only for stores created without encryption in tests/tools.
    private let encryptedStore: EncryptedStore?

    /// Writes index files through the same immutable encryption envelope.
    private let indexWriter: ClipIndexWriter
    /// Accesses picture files synchronously within this actor.
    private let pictureVault: PictureVault

    /// The user's answers about whether a text is a secret, which outrank the detector.
    private var secrecy: ClipSecrecyOverrides

    /// Holds the pending write of a use, so a run of pastes costs one write rather than one each.
    private var useFlush: Task<Void, Never>?

    /// Counts the files written while bound, so a test can bound the writing without a clock.
    @TaskLocal package static var writes: StoreWriteTally?

    /// Lets a regression simulate another process replacing an index at the write boundary.
    @TaskLocal package static var beforePersistForTesting: (@Sendable (URL) -> Void)?

    public init(
        file: URL = ClipboardStore.defaultFile(),
        budget: ClipboardBudget = ClipboardStore.defaultBudget,
        useFlushDelay: Duration = .seconds(30),
        encryptedStore: EncryptedStore? = nil
    ) {
        self.file = file
        self.budget = budget
        policy = RetentionPolicy(budget: budget)
        self.useFlushDelay = useFlushDelay
        self.encryptedStore = encryptedStore
        indexWriter = ClipIndexWriter(encryptedStore: encryptedStore)
        pictureVault = PictureVault(
            imagesFolder: file.deletingLastPathComponent().appending(
                path: LocalStoreEntry.clipboardImages.name, directoryHint: .isDirectory),
            encryptedStore: encryptedStore)
        indexReader = ClipboardIndexReader(encryptedStore: encryptedStore)
        secrecy = ClipSecrecyOverrides(
            file: file.deletingLastPathComponent()
                .appending(path: LocalStoreEntry.notSecretClips.name, directoryHint: .notDirectory),
            encryptedStore: encryptedStore)
    }

    /// Where the clipboard lives by default; versioned in the name so a new shape can sit beside it.
    public static func defaultFile(in directory: URL = .applicationSupportDirectory) -> URL {
        LocalStoreEntry.clipboard.location(in: directory)
    }

    // MARK: - Reading

    /// Everything still retained, newest first; one read, then a best-effort rewrite when clips age out.
    public func clips(keeping retention: ClipRetention) -> [Clip] {
        let stored = loaded()
        let onDisk = policy.keptOnDisk(stored, keeping: retention)
        // Time passes while the app idles, so the window drops clips here; the catch-up is best-effort.
        if onDisk.count != stored.count { try? save(onDisk) }
        return policy.retained(stored, keeping: retention)
    }

    /// Returns each damaged index copy once, so the app can tell the user where it is kept.
    public func takeUnreadableIndexSetAsides() -> [URL] {
        indexReader.takeUnreadableIndexSetAsides()
    }

    /// The number of malformed clip records found since the previous notice.
    public func takeUnreadableRecordCount() -> Int {
        indexReader.takeUnreadableRecordCount()
    }

    /// The number of records whose source index could not be preserved, once per notice.
    public func takeUnpreservedRecordCount() -> Int {
        indexReader.takeUnpreservedRecordCount()
    }

    /// Newer payload versions this build found, returned once for a clear read-only notice.
    package func takeUnsupportedFormatVersions() -> [Int] {
        indexReader.takeUnsupportedFormatVersions()
    }

    // MARK: - Writing

    /// Records a copy, moving a repeat to the top rather than adding a row. See `Docs/clipboard-store.md`.
    @discardableResult
    public func record(
        _ clip: Clip, keeping retention: ClipRetention
    ) throws(ClipboardStoreError) -> [Clip] {
        // A picture has no text and is still worth keeping — the emptiness is the point.
        guard clip.image != nil || clip.files != nil || ClipContent.isWorthKeeping(clip.text) else {
            return policy.retained(loaded(), keeping: retention)
        }
        // Refused rather than truncated: one copied log file would be rewritten on every later ⌘C.
        guard policy.fitsLargestClip(clip) else {
            return policy.retained(loaded(), keeping: retention)
        }

        let existing = loaded()
        let clip = secrecy.applied(to: clip)
        let updated = Self.recording(clip, in: existing, nextUseOrder: nextUseOrder)
        return try settled(updated, keeping: retention)
    }

    /// Restores a deleted clip unchanged, unless a newer copy already exists.
    @discardableResult
    public func restore(
        _ clip: Clip, keeping retention: ClipRetention
    ) throws(ClipboardStoreError) -> [Clip] {
        try restoreReportingAliasConflict(clip, keeping: retention).clips
    }

    /// Restores a deleted clip and reports whether its former name was already in use.
    public func restoreReportingAliasConflict(
        _ clip: Clip, keeping retention: ClipRetention
    ) throws(ClipboardStoreError) -> ClipboardRestoreResult {
        let existing = loaded()
        guard !existing.contains(where: { $0.id == clip.id }) else {
            return ClipboardRestoreResult(
                clips: policy.retained(existing, keeping: retention), aliasWasAlreadyInUse: false)
        }
        let reconciled = Self.restoring(clip, in: existing)
        let clips = try settled(reconciled.clips, keeping: retention)
        return ClipboardRestoreResult(clips: clips, aliasWasAlreadyInUse: reconciled.aliasWasAlreadyInUse)
    }

    /// Moves a used clip to the top of its history or saved pool; the disk hears of it with the next write.
    @discardableResult
    public func markUsed(
        _ id: UUID, at moment: Date, keeping retention: ClipRetention
    ) -> [Clip] {
        var clips = loaded()
        guard let index = clips.firstIndex(where: { $0.id == id }) else {
            return policy.retained(clips, keeping: retention)
        }
        clips[index] = clips[index].used(at: moment, order: nextUseOrder())
        clips = ClipOrdering.orderedForDisplay(clips)
        let onDisk = policy.keptOnDisk(clips, keeping: retention)
        // A clip that aged out is a real change, written now; a use alone is bookkeeping for a later eviction.
        guard onDisk.count == clips.count else {
            try? save(onDisk)
            return policy.retained(clips, keeping: retention)
        }
        indexSnapshot.wholeList = onDisk
        hasUnwrittenUse = true
        scheduleUseFlush()
        return policy.retained(clips, keeping: retention)
    }

    /// Writes a use or a refused change still held in memory, which quitting asks for so a deletion is not undone.
    public func flushUse() {
        useFlush?.cancel()
        useFlush = nil
        guard hasUnwrittenUse, let wholeList = indexSnapshot.wholeList else { return }
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
        ClipEdits.nextUseOrder(&lastUsedOrder)
    }

    /// Forgets one clip and answers with what is left; an identifier that is not there is not an error.
    @discardableResult
    public func delete(
        _ id: UUID, keeping retention: ClipRetention, holdingPicture: Bool = false
    ) throws(ClipboardStoreError) -> [Clip] {
        if holdingPicture, let file = loaded().first(where: { $0.id == id })?.image?.file {
            pictureReferences.heldPictures.insert(file)
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
        return policy.retained(saved, keeping: retention)
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
        guard changed else { return policy.retained(stored, keeping: retention) }
        return try settled(left, keeping: retention)
    }

    /// Removes every clip, pinned ones included, and every answer about secrets, as resetting personalisation promises.
    public func forgetEverything() throws(ClipboardStoreError) {
        _ = loaded()
        guard indexReader.unreplaceable.isEmpty else { throw .couldNotWrite }
        try save([])
        try secrecy.forget()
        forgetHeldPictures()
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

    /// Replaces a clip's plain text and clears the old formatted form, keeping its identity.
    @discardableResult
    public func setText(
        _ text: String, of id: UUID, keeping retention: ClipRetention
    ) throws(ClipboardStoreError) -> [Clip] {
        try change(id, keeping: retention) { clip in
            // A file clip's words are its files' names, which an edit would only contradict.
            guard clip.files == nil else { return }
            clip = Self.rebuilding(clip, text: text, richText: nil, image: clip.image)
        }
    }

    // MARK: - Pictures

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
        do {
            try pictureVault.writeImage(data, named: name)
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
            try pictureVault.writeImage(data, named: name)
        } catch {
            throw Self.writeFailure(error)
        }
        pictureReferences.unnamedPictures.insert(name)
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
        pictureVault.hasImage(for: image)
    }

    /// The bytes of a clip's picture, or `nil` when the file has gone from under the app.
    public func imageData(for image: ClipImage) -> Data? {
        guard let url = pictureVault.pictureURL(image.file), let data = try? Data(contentsOf: url) else {
            return nil
        }
        return pictureVault.imageData(
            data, from: url, for: image, unreplaceable: &indexReader.unreplaceable)
    }

    /// Releases the pictures held for an undo, deleting each one no clip has taken back.
    public func forgetHeldPictures() {
        let released = pictureReferences.heldPictures.subtracting(loaded().compactMap(\.image?.file))
        pictureReferences.heldPictures = []
        pictureVault.removePictures(released)
    }

    /// Deletes pictures no clip refers to any more; best-effort, so a stuck file cannot cost a write.
    public func forgetOrphanedImages() {
        guard indexesAreTrustworthy else { return }
        let wanted = Set(loaded().compactMap(\.image?.file))
        let onDisk =
            (try? FileManager.default.contentsOfDirectory(
                at: imagesFolder, includingPropertiesForKeys: nil)) ?? []
        // A picture waiting for the write that will name it is not an orphan yet.
        pictureVault.removePictures(
            pictureReferences.orphaned(onDisk: Set(onDisk.map(\.lastPathComponent)), wanted: wanted))
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

    // MARK: - The rules

    /// What a clip costs this process to hold; see `RetentionPolicy`.
    static func weight(of clip: Clip) -> Int { RetentionPolicy.weight(of: clip) }

    /// What a list of clips costs this process to hold.
    static func weight(of clips: [Clip]) -> Int { RetentionPolicy.weight(of: clips) }

    /// Applies one edit to one clip, then the retention rules, then writes.
    private func change(
        _ id: UUID, keeping retention: ClipRetention, _ edit: (inout Clip) -> Void
    ) throws(ClipboardStoreError) -> [Clip] {
        let clips = try ClipEdits.changing(
            id, in: loaded(), keeping: retention, secrecy: &secrecy, policy: policy,
            lastUsedOrder: &lastUsedOrder, edit)
        return try settled(clips, keeping: retention)
    }

    /// Writes what may stay on the disk and answers with what may be shown. See `Docs/retention-clock.md`.
    private func settled(
        _ clips: [Clip], keeping retention: ClipRetention
    ) throws(ClipboardStoreError) -> [Clip] {
        let unique = ClipOrdering.uniqueAliases(in: ClipOrdering.orderedForDisplay(clips))
        guard budget.fitsKeptPictures(unique, replacing: loaded()) else { throw .keptPicturesFull }
        try save(policy.keptOnDisk(unique, keeping: retention))
        return policy.retained(unique, keeping: retention)
    }

    /// Whether this clip may cross a launch boundary; secrets stay in this process only.
    static func isPersistable(_ clip: Clip) -> Bool { clip.kind != .secret }

    // MARK: - The two files

    /// Where saved clips are kept: beside the history and never in it. See `Docs/clipboard-store.md`.
    var savedFile: URL {
        file.deletingLastPathComponent()
            .appending(path: LocalStoreEntry.savedClips.name, directoryHint: .notDirectory)
    }

    /// The list, read from disk the first time and from memory thereafter.
    private func loaded() -> [Clip] {
        if let wholeList = indexSnapshot.wholeList { return wholeList }
        // A clipboard written before the split keeps its saved clips in the history file.
        let rawSaved = indexReader.read(savedFile).filter(Self.isPersistable)
        // A move interrupted between the two writes leaves a clip in both files, and the saved copy wins.
        let rawHistory = indexReader.read(file).filter(Self.isPersistable)
        // Inspect both indexes before migration, since a save can rewrite both files.
        let canRewriteIndexes =
            indexReader.unsupportedFormatVersions.isEmpty && indexReader.unknownFieldIndexes.isEmpty
            && !indexReader.hasUnreadableIndex
        let fromSavedFile = rawSaved
        let fromHistoryFile = rawHistory
        if canRewriteIndexes {
            migrateLegacyIndex(savedFile, clips: fromSavedFile)
            migrateLegacyIndex(file, clips: fromHistoryFile)
        }
        let normalized = indexSnapshot.load(
            saved: fromSavedFile, history: fromHistoryFile, at: file,
            unreplaceable: indexReader.unreplaceable)
        lastUsedOrder = normalized.compactMap(\.lastUsedOrder).max() ?? 0
        indexSnapshot.wholeList = normalized
        if canRewriteIndexes {
            scheduleReclassification(fromSavedFile, at: savedFile)
            scheduleReclassification(fromHistoryFile, at: file)
        }
        sweepOnce()
        migrateLegacyImagesOnce()
        return normalized
    }

    /// Starts the picture pass off the clipboard actor so sealed files do not slow down ⇧⌘V.
    private func migrateLegacyImagesOnce() {
        guard !hasMigratedLegacyImages else { return }
        hasMigratedLegacyImages = true
        guard let store = encryptedStore else { return }
        let folder = imagesFolder
        legacyImageMigration = Task.detached(priority: .utility) { [weak self] in
            await LegacyPictureMigration().run(in: folder) { [weak self] data, name in
                await self?.sealLegacyPicture(data, named: name)
            }
            try? store.markLegacyMigrationComplete(for: .clipboardPictures)
        }
    }

    /// Waits for the background migration in tests that inspect the migrated files.
    func waitForLegacyPictureMigration() async {
        await legacyImageMigration?.value
    }

    /// Seals a plaintext image after confirming the migration has not raced with another store write.
    private func sealLegacyPicture(_ data: Data, named name: String) {
        pictureVault.sealLegacyPicture(data, named: name, unreplaceable: &indexReader.unreplaceable)
    }

    /// Schedules stale detector work after the current list returns.
    private func scheduleReclassification(_ clips: [Clip], at url: URL) {
        guard indexReader.classifierVersions[url, default: 0] < ClipboardIndex.currentClassifierVersion,
            classifierMigrations[url] == nil, canReclassify(url)
        else { return }
        let candidates = clips.filter { $0.image == nil && $0.files == nil }
        let task = Task { [weak self] in
            let updated = await Task.detached(priority: .utility) {
                await ClipReclassification.classify(candidates)
            }.value
            await self?.finishReclassification(updated, from: clips, at: url)
        }
        classifierMigrations[url] = task
    }

    /// Whether an index may be rewritten with fresh detector results.
    private func canReclassify(_ url: URL) -> Bool {
        // A set-aside copy is left for the user to recover; it never makes this file unwritable.
        guard !indexReader.hasUnreadableIndex, !indexReader.unreplaceable.contains(url),
            !LocalStore.hasSetAside(url),
            indexReader.unsupportedFormatVersions.isEmpty, indexReader.unknownFieldIndexes.isEmpty
        else { return false }
        // Without the user's answers a clip they unmasked would be masked again and leave the disk.
        return secrecy.areKnown()
    }

    /// Persists a completed background pass only when the source clips still match the loaded snapshot.
    private func finishReclassification(_ updated: [Clip], from snapshot: [Clip], at url: URL) {
        defer { classifierMigrations[url] = nil }
        guard indexReader.classifierVersions[url, default: 0] < ClipboardIndex.currentClassifierVersion,
            canReclassify(url)
        else { return }
        let merge = Self.mergeClassifierResults(updated, from: snapshot, into: currentClips(in: url))
        // A changed or new clip has no detector result, so the next launch needs a fresh snapshot.
        guard merge.coversCurrentText else { return }
        // The rewritten index keeps the eviction orders the live list gave on load, so it reopens equal.
        let merged = ClipReclassification.ordered(
            merge.clips, in: indexSnapshot.wholeList ?? [], secrecy: &secrecy)
        let persistable = merged.filter(Self.isPersistable)
        do {
            try persist(persistable, to: url, classifierVersion: ClipboardIndex.currentClassifierVersion)
            indexReader.classifierVersions[url] = ClipboardIndex.currentClassifierVersion
            replaceCurrentClips(persistable, in: url)
        } catch {
            // Leave the old index version so the detector retries on the next launch.
        }
    }

    /// Applies detector-owned fields only when the classified snapshot still names the current text.
    package static func mergeClassifierResults(
        _ updated: [Clip], from snapshot: [Clip], into current: [Clip]
    ) -> (clips: [Clip], coversCurrentText: Bool) {
        ClipReclassification.merge(updated, from: snapshot, into: current)
    }

    /// Returns the currently loaded clips belonging to one index.
    private func currentClips(in url: URL) -> [Clip] {
        indexSnapshot.current(in: url, savedFile: savedFile)
    }

    /// Replaces one index's clips in memory after its background detector pass commits.
    private func replaceCurrentClips(_ clips: [Clip], in url: URL) {
        indexSnapshot.replace(clips, in: url, savedFile: savedFile)
    }

    /// Waits for background detector migrations in store tests.
    package func waitForClassifierMigrations() async {
        let tasks = Array(classifierMigrations.values)
        for task in tasks { await task.value }
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
        indexReader.unsupportedFormatVersions.isEmpty && indexReader.unknownFieldIndexes.isEmpty
            && !indexReader.hasUnreadableIndex
            && !LocalStore.hasSetAside(file) && !LocalStore.hasSetAside(savedFile)
    }

    /// Rechecks local index bytes through the reader before a cached write.
    private func validateCurrentIndexFormatsBeforeWrite() throws(ClipboardStoreError) {
        try indexReader.validateCurrentFormats(in: [file, savedFile]) { try Data(contentsOf: $0) }
    }

    /// Upgrades a released bare array only after both indexes proved writable by this schema.
    private func migrateLegacyIndex(_ url: URL, clips: [Clip]) {
        guard indexReader.legacyIndexes.contains(url), !indexReader.unreplaceable.contains(url),
            !LocalStore.hasSetAside(url)
        else {
            return
        }
        do {
            try persist(clips.filter(Self.isPersistable), to: url)
            indexReader.legacyIndexes.remove(url)
        } catch {
            // The legacy format remains readable and a later user write can retry the migration.
        }
    }

    /// Writes the list to memory and then to disk, filing each clip by what ``Clip/isKept`` says.
    private func save(_ clips: [Clip]) throws(ClipboardStoreError) {
        let current = loaded()
        try validateCurrentIndexFormatsBeforeWrite()
        guard indexReader.unsupportedFormatVersions.isEmpty else { throw .unsupportedFormat }
        // Validation cannot inspect an index another process removed after we read it.
        guard indexReader.unknownFieldIndexes.isEmpty else { throw .couldNotWrite }
        // First, so the launch sweep this read can trigger still sees what is waiting to be named.
        let before = Set(current.compactMap(\.image?.file))
        let named = Set(clips.compactMap(\.image?.file))
        // A picture written for a clip this list drops is ours to remove, whether the writes below land or not.
        let unnamed = pictureReferences.takeUnnamed(naming: named)
        defer { pictureVault.removePictures(unnamed) }
        let persistable = clips.filter(Self.isPersistable)

        // Memory first and unconditionally, so a refusing disk does not also cost the change itself.
        indexSnapshot.wholeList = clips
        // This write carries every use held in memory, so none is left waiting for its own.
        hasUnwrittenUse = false
        useFlush?.cancel()
        useFlush = nil

        let dropped = pictureReferences.dropped(before: before, naming: named)
        do throws(ClipboardStoreError) {
            try ClipPersistence(historyFile: file).write(persistable, updating: &indexSnapshot) {
                clips, url throws(ClipboardStoreError) in
                try persist(clips, to: url)
            }
        } catch {
            // The change stays in memory and is retried by the next write, the timed flush and quitting.
            hasUnwrittenUse = true
            pictureReferences.picturesAwaitingWrite = dropped
            scheduleUseFlush()
            throw error
        }
        pictureReferences.picturesAwaitingWrite = []

        // Only the files that stopped being referenced, so a picture no read could vouch for is never touched.
        pictureVault.removePictures(pictureReferences.unheld(dropped))
    }

    /// Writes a whole list atomically, or removes its file when nothing is left to keep.
    private func persist(
        _ clips: [Clip], to url: URL, classifierVersion: Int? = nil
    ) throws(ClipboardStoreError) {
        // A file that could be neither read nor moved aside is the user's only copy, so it is not replaced.
        guard !indexReader.unreplaceable.contains(url) else { throw .couldNotWrite }
        Self.beforePersistForTesting?(url)
        try validateCurrentIndexFormatsBeforeWrite()
        try indexWriter.persist(
            clips, to: url, classifierVersion: classifierVersion,
            classifierVersions: indexReader.classifierVersions,
            legacyIndexes: &indexReader.legacyIndexes)
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
}
