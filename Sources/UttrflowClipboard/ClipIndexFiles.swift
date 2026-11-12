// The two clipboard indexes as one unit: their reads, their cached lists and their guarded writes.

import Foundation
import UttrflowCore

/// Reads, caches and writes the history and saved indexes; `ClipboardStore` decides when.
struct ClipIndexFiles {
    /// What one first read found: each index's persistable clips and the combined live list.
    struct Loaded {
        let saved: [Clip]
        let history: [Clip]
        let list: [Clip]
        let canRewrite: Bool
    }

    /// The history file; the saved file sits beside it.
    let historyFile: URL
    /// Reads both indexes and holds their recovery state.
    var reader: ClipboardIndexReader
    /// The loaded index contents and their combined live list.
    var snapshot = ClipIndexSnapshot()
    /// Writes each index through the same encryption envelope the reader opens.
    private let writer: ClipIndexWriter
    /// Whether the indexes are sealed, the only place a secret's value may be written.
    let isSealed: Bool

    init(historyFile: URL, encryptedStore: EncryptedStore?) {
        self.historyFile = historyFile
        reader = ClipboardIndexReader(encryptedStore: encryptedStore)
        writer = ClipIndexWriter(encryptedStore: encryptedStore)
        isSealed = encryptedStore != nil
    }

    /// Where saved clips are kept: beside the history and never in it. See `Docs/clipboard-store.md`.
    var savedFile: URL {
        historyFile.deletingLastPathComponent()
            .appending(path: LocalStoreEntry.savedClips.name, directoryHint: .notDirectory)
    }

    /// Reads both indexes, upgrades a legacy one when both may be rewritten, and caches the list.
    mutating func load() -> Loaded {
        // A clipboard written before the split keeps its saved clips in the history file.
        let saved = reader.read(savedFile).filter(ClipboardStore.isPersistable)
        // A move interrupted between the two writes leaves a clip in both files, and the saved copy wins.
        let history = reader.read(historyFile).filter(ClipboardStore.isPersistable)
        // Inspect both indexes before migration, since a save can rewrite both files.
        let canRewrite = ClipMigration.canRewriteIndexes(reader)
        if canRewrite {
            migrateLegacy(savedFile, clips: saved)
            migrateLegacy(historyFile, clips: history)
        }
        let list = snapshot.load(
            saved: saved, history: history, at: historyFile, unreplaceable: reader.unreplaceable)
        snapshot.wholeList = list
        return Loaded(saved: saved, history: history, list: list, canRewrite: canRewrite)
    }

    /// Upgrades a released bare array only after both indexes proved writable by this schema.
    private mutating func migrateLegacy(_ url: URL, clips: [Clip]) {
        let inspected = reader
        if ClipMigration.migrateLegacy(
            url, clips: clips, reader: inspected,
            persist: { clips, url throws(ClipboardStoreError) in try persist(clips, to: url) }
        ) {
            reader.legacyIndexes.remove(url)
        }
    }

    /// Whether every file that can name a picture was read, so a file named by neither is an orphan.
    var areTrustworthy: Bool {
        ClipMigration.indexesAreTrustworthy(reader, history: historyFile, saved: savedFile)
    }

    /// Whether an index was judged by an older clip detector than this build's.
    func needsReclassifying(_ url: URL) -> Bool {
        reader.classifierVersions[url, default: 0] < ClipboardIndex.currentClassifierVersion
    }

    /// Returns the currently loaded clips belonging to one index.
    func current(in url: URL) -> [Clip] {
        snapshot.current(in: url, savedFile: savedFile)
    }

    /// Writes a finished detector pass with the new detector version, then commits it to memory.
    mutating func commitReclassified(_ persistable: [Clip], in url: URL) throws(ClipboardStoreError) {
        // Only a sealed index may hold a secret's value, as in `write`.
        let onDisk = persistable.filter { isSealed || $0.kind != .secret }
        try persist(onDisk, to: url, classifierVersion: ClipboardIndex.currentClassifierVersion)
        reader.classifierVersions[url] = ClipboardIndex.currentClassifierVersion
        snapshot.replace(persistable, in: url, savedFile: savedFile)
    }

    /// Refuses a cached write over an index this build cannot rewrite without losing data.
    mutating func checkWritable() throws(ClipboardStoreError) {
        try validateBeforeWrite()
        guard reader.unsupportedFormatVersions.isEmpty else { throw .unsupportedFormat }
        // Validation cannot inspect an index another process removed after we read it.
        guard reader.unknownFieldIndexes.isEmpty else { throw .couldNotWrite }
    }

    /// Files each clip by what ``Clip/isKept`` says, keeping every index snapshot that was committed.
    mutating func write(_ persistable: [Clip]) throws(ClipboardStoreError) {
        var committed = snapshot
        defer { snapshot = committed }
        try ClipPersistence(historyFile: historyFile).write(persistable, updating: &committed) {
            clips, url throws(ClipboardStoreError) in
            try persist(clips, to: url)
        }
    }

    /// Writes a whole list atomically, or removes its file when nothing is left to keep.
    private mutating func persist(
        _ clips: [Clip], to url: URL, classifierVersion: Int? = nil
    ) throws(ClipboardStoreError) {
        // A file that could be neither read nor moved aside is the user's only copy, so it is not replaced.
        guard !reader.unreplaceable.contains(url) else { throw .couldNotWrite }
        ClipboardStore.beforePersistForTesting?(url)
        try validateBeforeWrite()
        try writer.persist(
            clips, to: url, classifierVersion: classifierVersion,
            classifierVersions: reader.classifierVersions,
            legacyIndexes: &reader.legacyIndexes)
    }

    /// Rechecks local index bytes through the reader before a cached write.
    private mutating func validateBeforeWrite() throws(ClipboardStoreError) {
        try reader.validateCurrentFormats(
            in: [historyFile, savedFile], reading: ClipboardStore.readIndexBytes)
    }
}
