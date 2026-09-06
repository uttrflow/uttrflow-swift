// The store behind the clipboard panel: what has been copied, in memory and across two files.

import UttrflowCore
import CryptoKit

public import struct Foundation.Date
public import struct Foundation.URL
public import struct Foundation.UUID

public import struct Foundation.Data
public import class Foundation.FileManager
public import class Foundation.JSONDecoder
public import class Foundation.JSONEncoder

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

    /// The history and the saved clips as one list, or `nil` before the files have been read.
    private var wholeList: [Clip]?

    /// Whether this process has already reconciled the pictures folder; see ``sweepOnce(against:)``.
    private var hasSwept = false

    public init(
        file: URL = ClipboardStore.defaultFile(),
        budget: ClipboardBudget = ClipboardStore.defaultBudget
    ) {
        self.file = file
        self.budget = budget
    }

    /// Where the clipboard lives by default; versioned in the name so a new shape can sit beside it.
    public static func defaultFile(in directory: URL = .applicationSupportDirectory) -> URL {
        LocalStore.file("clipboard.v1.json", in: directory)
    }

    // MARK: - Reading

    /// Everything still retained, newest first; the call ⇧⌘V waits on, and it does no I/O.
    public func clips(keeping retention: ClipRetention) -> [Clip] {
        let stored = loaded()
        let kept = retained(stored, keeping: retention)
        // Time passes while the app idles, so the window drops clips here; the catch-up is best-effort.
        if kept.count != stored.count { try? save(kept) }
        return kept
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
        guard budget.largestClip <= 0 || Self.weight(of: clip) <= budget.largestClip else {
            return retained(loaded(), keeping: retention)
        }

        let existing = loaded()
        let previous = Self.previous(for: clip, in: existing)
        let arrival = previous.map { inheriting($0, from: clip) } ?? clip

        // Prepended, not sorted in: a machine whose clock moved must not shuffle what the user sees.
        let displaced = previous.map { [$0.id] } ?? []
        let updated = [arrival] + existing.filter { !displaced.contains($0.id) }
        let kept = retained(updated, keeping: retention)
        try save(kept)
        return kept
    }

    /// Notes that a clip has just been reached for, so the eviction policy ranks it as recently used.
    @discardableResult
    public func markUsed(
        _ id: UUID, at moment: Date, keeping retention: ClipRetention
    ) -> [Clip] {
        var clips = loaded()
        guard let index = clips.firstIndex(where: { $0.id == id }) else {
            return retained(clips, keeping: retention)
        }
        clips[index] = clips[index].used(at: moment)
        let kept = retained(clips, keeping: retention)
        // Bookkeeping for a later eviction, so a disk that refuses must not fail somebody's paste.
        try? save(kept)
        return kept
    }

    /// Forgets one clip and answers with what is left; an identifier that is not there is not an error.
    @discardableResult
    public func delete(
        _ id: UUID, keeping retention: ClipRetention
    ) throws(ClipboardStoreError) -> [Clip] {
        let kept = retained(loaded().filter { $0.id != id }, keeping: retention)
        try save(kept)
        return kept
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
        return retained(saved, keeping: retention)
    }

    /// Removes every clip, pinned ones included, which is what resetting personalisation promises.
    public func forgetEverything() throws(ClipboardStoreError) {
        try save([])
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
        try change(id, keeping: retention) { $0.alias = alias }
    }

    /// Replaces a clip's plain text, keeping its identity and leaving its formatted note alone.
    @discardableResult
    public func setText(
        _ text: String, of id: UUID, keeping retention: ClipRetention
    ) throws(ClipboardStoreError) -> [Clip] {
        try change(id, keeping: retention) { clip in
            clip = Self.rebuilding(clip, text: text, richText: clip.richText, image: clip.image)
        }
    }

    // MARK: - Pictures

    /// Where the pictures live: a folder beside the clipboard file, never inside that whole-file rewrite.
    public var imagesFolder: URL {
        file.deletingLastPathComponent().appending(path: "Images", directoryHint: .isDirectory)
    }

    /// Records a noticed copy, writing its picture first so a clip never points at a file that is missing.
    @discardableResult
    public func record(
        _ noticed: NoticedClip, keeping retention: ClipRetention
    ) throws(ClipboardStoreError) -> [Clip] {
        guard let picture = noticed.picture else {
            return try record(noticed.clip, keeping: retention)
        }
        // Hashed before it is written, so a screenshot copied twice costs a counter, not another file.
        let sha = ClipboardStore.digest(of: picture.data)
        var image = alreadyKept(sha, in: noticed.clip.origin)
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

    /// Keeps a picture on disk and answers with what a row needs; throws, since a missing file is forever.
    public func keep(
        _ data: Data, forClip id: UUID, width: Int, height: Int, sha: String? = nil
    ) throws(ClipboardStoreError) -> ClipImage {
        let name = "\(id.uuidString).png"
        do {
            try FileManager.default.createDirectory(
                at: imagesFolder, withIntermediateDirectories: true)
            try data.write(to: imagesFolder.appending(path: name, directoryHint: .notDirectory))
        } catch {
            throw .couldNotWrite
        }
        return ClipImage(
            file: name, width: width, height: height, bytes: data.count,
            sha: sha ?? ClipboardStore.digest(of: data))
    }

    /// A picture's bytes as a short hexadecimal digest; truncated because this is a cache key, not a signature.
    public static func digest(of data: Data) -> String {
        SHA256.hash(data: data).prefix(16).map { String(format: "%02x", $0) }.joined()
    }

    /// The bytes of a clip's picture, or `nil` when the file has gone from under the app.
    public func imageData(for image: ClipImage) -> Data? {
        try? Data(
            contentsOf: imagesFolder.appending(path: image.file, directoryHint: .notDirectory))
    }

    /// Deletes pictures no clip refers to any more; best-effort, so a stuck file cannot cost a write.
    public func forgetOrphanedImages() {
        let wanted = Set(loaded().compactMap(\.image?.file))
        let onDisk =
            (try? FileManager.default.contentsOfDirectory(
                at: imagesFolder, includingPropertiesForKeys: nil)) ?? []
        for file in onDisk where !wanted.contains(file.lastPathComponent) {
            try? FileManager.default.removeItem(at: file)
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
        Clip(
            id: clip.id, text: text, kind: clip.kind, copiedAt: clip.copiedAt,
            source: clip.source, origin: clip.origin, lastUsedAt: clip.lastUsedAt,
            language: clip.language, richText: richText, image: image,
            alias: clip.alias, category: clip.category, isPinned: clip.isPinned,
            timesCopied: clip.timesCopied)
    }

    /// Carries what the user chose about a clip onto the copy that has just replaced it.
    private func inheriting(_ previous: Clip, from arrival: Clip) -> Clip {
        Clip(
            id: previous.id, text: arrival.text, kind: arrival.kind, copiedAt: arrival.copiedAt,
            source: arrival.source,
            // Named rather than defaulted, so a repeat cannot quietly become a ⌘C.
            origin: previous.origin,
            // Copying something again is reaching for it, so the eviction clock moves too.
            lastUsedAt: arrival.copiedAt,
            // The arrival's, detected from the text recorded now and from this pasteboard.
            language: arrival.language, richText: arrival.richText,
            // The file already on disk, not the one just written; the arrival's would strand it.
            image: previous.image ?? arrival.image,
            // Everything the user decided stays with the clip they decided it about.
            alias: previous.alias, category: previous.category, isPinned: previous.isPinned,
            // The point of recognising a repeat: this clip happening once more, not a new one.
            timesCopied: previous.timesCopied + 1)
    }

    /// Applies one edit to one clip, then the retention rules, then writes.
    private func change(
        _ id: UUID, keeping retention: ClipRetention, _ edit: (inout Clip) -> Void
    ) throws(ClipboardStoreError) -> [Clip] {
        var clips = loaded()
        if let index = clips.firstIndex(where: { $0.id == id }) { edit(&clips[index]) }
        let kept = retained(clips, keeping: retention)
        try save(kept)
        return kept
    }

    /// Spares every kept clip, then applies the window and the per-pool caps to the history.
    private func retained(_ clips: [Clip], keeping retention: ClipRetention) -> [Clip] {
        // Kept clips are not candidates at all: their pool has no tier to be an exception to.
        let history = clips.filter { ClipClass(of: $0).isEvictable }
        let surviving = history.filter { survives($0, keeping: retention) }

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

    /// What a list of clips costs this process to hold.
    static func weight(of clips: [Clip]) -> Int {
        clips.reduce(0) { $0 + weight(of: $1) }
    }

    /// Drops the least recently used clips of a text pool until it fits its memory quota.
    private func withinMemory(_ clips: [Clip]) -> [Clip] {
        var dropped: Set<UUID> = []
        // Only the text pools: a picture's bytes are a file, and its thumbnail is bounded elsewhere.
        for pool in [ClipClass.copied, .dictation] {
            guard let tier = budget.tier(for: pool), tier.bytes > 0 else { continue }
            let list = clips.filter { ClipClass(of: $0) == pool }
            var weight = Self.weight(of: list)
            guard weight > tier.bytes else { continue }
            for clip in list.sorted(by: { $0.lastUsedAt < $1.lastUsedAt }) where weight > tier.bytes {
                dropped.insert(clip.id)
                weight -= Self.weight(of: clip)
            }
        }
        return clips.filter { !dropped.contains($0.id) }
    }

    /// Drops the least recently used pictures until the folder fits its disk budget.
    private func withinDisk(_ clips: [Clip]) -> [Clip] {
        guard budget.disk > 0 else { return clips }
        let pictures = clips.filter { ClipClass(of: $0) == .images }
        var weight = pictures.reduce(0) { $0 + ($1.image?.bytes ?? 0) }
        guard weight > budget.disk else { return clips }
        var dropped: Set<UUID> = []
        for clip in pictures.sorted(by: { $0.lastUsedAt < $1.lastUsedAt }) where weight > budget.disk {
            dropped.insert(clip.id)
            weight -= clip.image?.bytes ?? 0
        }
        return clips.filter { !dropped.contains($0.id) }
    }

    /// Whether an unkept clip is still inside its window; zero days keeps nothing.
    private func survives(_ clip: Clip, keeping retention: ClipRetention) -> Bool {
        // The pool's own window where it has one, and the user's transcript setting for a dictation.
        let clipClass = ClipClass(of: clip)
        let days =
            clipClass == .dictation
            ? (retention.dictationDays ?? budget.tier(for: clipClass)?.days ?? retention.days)
            : (budget.tier(for: clipClass)?.days ?? retention.days)
        guard days > 0 else { return false }
        return clip.copiedAt.addingTimeInterval(Double(days) * 86_400) > retention.now
    }

    // MARK: - The two files

    /// Where saved clips are kept: beside the history and never in it. See `Docs/clipboard-store.md`.
    var savedFile: URL {
        file.deletingLastPathComponent()
            .appending(path: "saved.v1.json", directoryHint: .notDirectory)
    }

    /// The list, read from disk the first time and from memory thereafter.
    private func loaded() -> [Clip] {
        if let wholeList { return wholeList }
        // A clipboard written before the split keeps its saved clips in the history file.
        let fromSavedFile = read(savedFile)
        savedOnDisk = fromSavedFile
        let stored = fromSavedFile + read(file)
        let list = Self.interleaving(
            saved: stored.filter(\.isKept), history: stored.filter { !$0.isKept })
        wholeList = list
        sweepOnce(against: list)
        return list
    }

    /// The two lists as one, newest first; a merge rather than a sort, so two draws cannot disagree.
    private static func interleaving(saved: [Clip], history: [Clip]) -> [Clip] {
        var out: [Clip] = []
        out.reserveCapacity(saved.count + history.count)
        var left = 0
        var right = 0
        while left < saved.count, right < history.count {
            if saved[left].copiedAt >= history[right].copiedAt {
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

    /// Reconciles the pictures folder once a launch, catching orphans no write of ours can notice.
    private func sweepOnce(against clips: [Clip]) {
        // An empty list is what a bad read looks like too, so sweeping on one would delete everything.
        guard !hasSwept, !clips.isEmpty else { return }
        hasSwept = true
        forgetOrphanedImages()
    }

    /// Reads one file, answering with nothing when there is nothing readable there.
    private func read(_ url: URL) -> [Clip] {
        guard let data = try? Data(contentsOf: url),
            let clips = try? JSONDecoder().decode([Clip].self, from: data)
        else { return [] }
        return clips
    }

    /// Writes the list to memory and then to disk, filing each clip by what ``Clip/isKept`` says.
    private func save(_ clips: [Clip]) throws(ClipboardStoreError) {
        let before = Set(loaded().compactMap(\.image?.file))
        let wasSaved = savedOnDisk ?? []
        let nowSaved = clips.filter(\.isKept)
        let nowHistory = clips.filter { !$0.isKept }

        // Memory first and unconditionally, so a refusing disk does not also cost the change itself.
        wholeList = clips

        // The permanent file first, so a disk that refuses leaves the collection whole and history stale.
        // Only when it has changed: nearly every write is a ⌘C that belongs in the history alone.
        if nowSaved != wasSaved {
            try persist(nowSaved, to: savedFile)
            savedOnDisk = nowSaved
        }
        try persist(nowHistory, to: file)

        // Only when a file stops being referenced, so a text copy never pays for a directory scan.
        if !before.subtracting(Set(clips.compactMap(\.image?.file))).isEmpty {
            forgetOrphanedImages()
        }
    }

    /// Writes a whole list atomically, or removes its file when nothing is left to keep.
    private func persist(_ clips: [Clip], to url: URL) throws(ClipboardStoreError) {
        do {
            guard !clips.isEmpty else {
                try removeFile(url)
                return
            }
            try FileManager.default.createDirectory(
                at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try JSONEncoder().encode(clips).write(to: url, options: .atomic)
        } catch {
            throw .couldNotWrite
        }
    }

    /// Deletes a file if it is there; nothing to delete is success, not a failure.
    private func removeFile(_ url: URL) throws {
        let manager = FileManager.default
        guard manager.fileExists(atPath: url.path(percentEncoded: false)) else { return }
        try manager.removeItem(at: url)
    }
}
