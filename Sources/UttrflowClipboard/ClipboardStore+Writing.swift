// The clipboard store's writes: memory first, then both index files, then the pictures a list dropped.

import Foundation
import os
import UttrflowCore

extension ClipboardStore {
    /// Writes the list to memory and then to disk, filing each clip by what ``Clip/isKept`` says.
    func save(_ clips: [Clip]) throws(ClipboardStoreError) {
        do throws(ClipboardStoreError) {
            try write(clips)
        } catch {
            // The error case alone: a clip's text never reaches the log.
            Self.log.error("clipboard write refused: \(ErrorLog.failure(error), privacy: .public)")
            Self.refusedWriteLogForTesting?("clipboard write refused: \(ErrorLog.failure(error))")
            throw error
        }
    }

    /// Does the write `save` reports on: memory first, then the files, then the pictures the list dropped.
    private func write(_ clips: [Clip]) throws(ClipboardStoreError) {
        let current = loaded()
        try indexes.checkWritable()
        // First, so the launch sweep this read can trigger still sees what is waiting to be named.
        let before = Set(current.compactMap(\.image?.file))
        let named = Set(clips.compactMap(\.image?.file))
        // A picture written for a clip this list drops is ours to remove, whether the writes below land or not.
        let unnamed = pictureReferences.takeUnnamed(naming: named)
        defer { pictureVault.removePictures(unnamed) }
        // Only a sealed index may hold a secret's value: a store with no key writes the rest.
        let persistable = clips.filter { Self.isPersistable($0) && (indexes.isSealed || $0.kind != .secret) }

        // Memory first and unconditionally, so a refusing disk does not also cost the change itself.
        indexes.snapshot.wholeList = clips
        // This write carries every use held in memory, so none is left waiting for its own.
        hasUnwrittenUse = false
        useFlush?.cancel()
        useFlush = nil

        let dropped = pictureReferences.dropped(before: before, naming: named)
        do throws(ClipboardStoreError) {
            try indexes.write(persistable)
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
