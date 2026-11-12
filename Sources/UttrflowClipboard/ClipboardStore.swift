// The store behind the clipboard panel: what has been copied, in memory and across two files.

public import UttrflowCore
public import Foundation
import os

/// Everything the user has copied, kept on this Mac between launches. See `Docs/clipboard-store.md`.
public actor ClipboardStore {
    /// Every bound this store applies: records per pool, memory, days, and the largest clip kept at all.
    public static let defaultBudget = ClipboardBudget.standard

    /// What each pool of clips may cost, and for how long.
    private let budget: ClipboardBudget

    /// The retention rules over `budget`.
    let policy: RetentionPolicy

    /// The two index files, their recovery state and the lists last read from or written to them.
    var indexes: ClipIndexFiles

    /// The latest persisted eviction order assigned by this store.
    var lastUsedOrder: UInt64 = 0

    /// Whether this process has already reconciled the pictures folder; see ``sweepOnce()``.
    var hasSwept = false
    /// The once-a-launch background pass that seals plaintext pictures.
    var legacySealing = LegacyPictureSealing()
    /// Holds detector migrations so reads can return while classification runs in the background.
    var reclassifications = ClipReclassificationTasks()
    /// Holds picture references across undo, new arrivals and refused index writes.
    var pictureReferences = PictureReferences()

    /// Records that memory holds a use or a refused change the disk lacks; the next write, or `flushUse`, carries it.
    var hasUnwrittenUse = false

    /// Sets how long a use waits in memory for another write before it is written on its own.
    private let useFlushDelay: Duration
    /// The shared file envelope used by the app; nil only for stores created without encryption in tests/tools.
    let encryptedStore: EncryptedStore?

    /// Accesses picture files synchronously within this actor.
    let pictureVault: PictureVault

    /// The user's answers about whether a text is a secret, which outrank the detector.
    var secrecy: ClipSecrecyOverrides

    /// Holds the pending write of a use, so a run of pastes costs one write rather than one each.
    var useFlush: Task<Void, Never>?

    /// Counts the files written while bound, so a test can bound the writing without a clock.
    @TaskLocal package static var writes: StoreWriteTally?

    /// Receives each refused write's log line, so a test can read what the log would carry.
    @TaskLocal package static var refusedWriteLogForTesting: (@Sendable (String) -> Void)?

    /// Records refused writes, which have no other trace when the quit flush or a timed flush meets them.
    nonisolated static let log = Logger(subsystem: "com.uttrflow.Uttrflow", category: "clipboard")

    /// Lets a regression simulate another process replacing an index at the write boundary.
    @TaskLocal package static var beforePersistForTesting: (@Sendable (URL) -> Void)?

    /// Reads an index's current bytes, which every write checks before replacing the file.
    static let readIndexBytes: @Sendable (URL) throws -> Data = { try Data(contentsOf: $0) }

    public init(
        file: URL = ClipboardStore.defaultFile(),
        budget: ClipboardBudget = ClipboardStore.defaultBudget,
        useFlushDelay: Duration = .seconds(30),
        encryptedStore: EncryptedStore? = nil
    ) {
        self.budget = budget
        policy = RetentionPolicy(budget: budget)
        self.useFlushDelay = useFlushDelay
        self.encryptedStore = encryptedStore
        indexes = ClipIndexFiles(historyFile: file, encryptedStore: encryptedStore)
        pictureVault = PictureVault(
            imagesFolder: file.deletingLastPathComponent().appending(
                path: LocalStoreEntry.clipboardImages.name, directoryHint: .isDirectory),
            encryptedStore: encryptedStore)
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
        indexes.reader.takeUnreadableIndexSetAsides()
    }

    /// The number of malformed clip records found since the previous notice.
    public func takeUnreadableRecordCount() -> Int {
        indexes.reader.takeUnreadableRecordCount()
    }

    /// The number of records whose source index could not be preserved, once per notice.
    public func takeUnpreservedRecordCount() -> Int {
        indexes.reader.takeUnpreservedRecordCount()
    }

    /// Newer payload versions this build found, returned once for a clear read-only notice.
    package func takeUnsupportedFormatVersions() -> [Int] {
        indexes.reader.takeUnsupportedFormatVersions()
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
        indexes.snapshot.wholeList = onDisk
        hasUnwrittenUse = true
        scheduleUseFlush()
        return policy.retained(clips, keeping: retention)
    }

    /// Writes a use or a refused change still held in memory, which quitting asks for so a deletion is not undone.
    public func flushUse() {
        useFlush?.cancel()
        useFlush = nil
        guard hasUnwrittenUse, let wholeList = indexes.snapshot.wholeList else { return }
        try? save(wholeList)
    }

    /// Writes held uses after a quiet spell, unless another write carries them first.
    func scheduleUseFlush() {
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
        do { try LocalStore.removeSetAside(indexes.historyFile) } catch { throw Self.writeFailure(error) }
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
        guard indexes.reader.unreplaceable.isEmpty else { throw .couldNotWrite }
        try save([])
        try secrecy.forget()
        forgetHeldPictures()
        do {
            try LocalStore.removeSetAside(indexes.historyFile)
            try LocalStore.removeSetAside(savedFile)
        } catch {
            throw Self.writeFailure(error)
        }
    }

    // MARK: - The rules

    /// What a clip costs this process to hold; see `RetentionPolicy`.
    static func weight(of clip: Clip) -> Int { RetentionPolicy.weight(of: clip) }

    /// What a list of clips costs this process to hold.
    static func weight(of clips: [Clip]) -> Int { RetentionPolicy.weight(of: clips) }

    /// Applies one edit to one clip, then the retention rules, then writes.
    func change(
        _ id: UUID, keeping retention: ClipRetention, _ edit: (inout Clip) -> Void
    ) throws(ClipboardStoreError) -> [Clip] {
        let clips = try ClipEdits.changing(
            id, in: loaded(), keeping: retention, secrecy: &secrecy, policy: policy,
            lastUsedOrder: &lastUsedOrder, edit)
        return try settled(clips, keeping: retention)
    }

    /// Writes what may stay on the disk and answers with what may be shown. See `Docs/retention-clock.md`.
    func settled(
        _ clips: [Clip], keeping retention: ClipRetention
    ) throws(ClipboardStoreError) -> [Clip] {
        let unique = ClipOrdering.uniqueAliases(in: ClipOrdering.orderedForDisplay(clips))
        guard budget.fitsKeptPictures(unique, replacing: loaded()) else { throw .keptPicturesFull }
        try save(policy.keptOnDisk(unique, keeping: retention))
        return policy.retained(unique, keeping: retention)
    }

    /// Whether this clip crosses a launch: all but a secret nobody kept, which stays in this process.
    static func isPersistable(_ clip: Clip) -> Bool { clip.kind != .secret || clip.isKept }

    // MARK: - The two files

    /// Where saved clips are kept: beside the history and never in it. See `Docs/clipboard-store.md`.
    var savedFile: URL { indexes.savedFile }

    /// The list, read from disk the first time and from memory thereafter.
    func loaded() -> [Clip] {
        if let wholeList = indexes.snapshot.wholeList { return wholeList }
        let load = indexes.load()
        lastUsedOrder = load.list.compactMap(\.lastUsedOrder).max() ?? 0
        if load.canRewrite {
            scheduleReclassification(load.saved, at: savedFile)
            scheduleReclassification(load.history, at: indexes.historyFile)
        }
        sweepOnce()
        migrateLegacyImagesOnce()
        return load.list
    }
}
