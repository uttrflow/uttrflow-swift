// The committed index snapshots while clips move between their two files.

import Foundation
import UttrflowCore

/// Executes the saved-index bridge sequence while retaining successful write snapshots.
struct ClipPersistence {
    private let historyFile: URL

    init(historyFile: URL) {
        self.historyFile = historyFile
    }

    private var savedFile: URL {
        historyFile.deletingLastPathComponent()
            .appending(path: LocalStoreEntry.savedClips.name, directoryHint: .notDirectory)
    }

    func write(
        _ clips: [Clip], updating snapshot: inout ClipIndexSnapshot,
        persist: ([Clip], URL) throws(ClipboardStoreError) -> Void
    ) throws(ClipboardStoreError) {
        let wasSaved = snapshot.savedOnDisk ?? []
        let nowSaved = clips.filter(\.isKept)
        let nowHistory = clips.filter { !$0.isKept }
        let bridge = ClipPersistencePlan.bridging(clips, from: wasSaved, into: nowHistory)
        if !ClipPersistencePlan.holdsTheSameClips(bridge, as: wasSaved) {
            try persist(bridge, savedFile)
            snapshot.savedOnDisk = bridge
        }
        if nowHistory != snapshot.historyOnDisk {
            try persist(nowHistory, historyFile)
            snapshot.historyOnDisk = nowHistory
        }
        if nowSaved != bridge {
            try persist(nowSaved, savedFile)
            snapshot.savedOnDisk = nowSaved
        }
    }
}
