// The clipboard store's background passes: detector migrations and the legacy picture sealing.

import Foundation

extension ClipboardStore {
    /// Starts the picture pass off the clipboard actor so sealed files do not slow down ⇧⌘V.
    func migrateLegacyImagesOnce() {
        legacySealing.startOnce(in: imagesFolder, store: encryptedStore) { [weak self] data, name in
            await self?.sealLegacyPicture(data, named: name)
        }
    }

    /// Waits for the background migration in tests that inspect the migrated files.
    func waitForLegacyPictureMigration() async {
        await legacySealing.pass?.value
    }

    /// Seals a plaintext image after confirming the migration has not raced with another store write.
    private func sealLegacyPicture(_ data: Data, named name: String) {
        pictureVault.sealLegacyPicture(data, named: name, unreplaceable: &indexes.reader.unreplaceable)
    }

    /// Schedules stale detector work after the current list returns.
    func scheduleReclassification(_ clips: [Clip], at url: URL) {
        guard indexes.needsReclassifying(url), !reclassifications.isRunning(url), canReclassify(url)
        else { return }
        reclassifications.start(url, classifying: clips) { [weak self] updated in
            await self?.finishReclassification(updated, from: clips, at: url)
        }
    }

    /// Whether an index may be rewritten with fresh detector results.
    private func canReclassify(_ url: URL) -> Bool {
        ClipMigration.canReclassify(url, reader: indexes.reader, secrecy: &secrecy)
    }

    /// Persists a completed background pass only when the source clips still match the loaded snapshot.
    private func finishReclassification(_ updated: [Clip], from snapshot: [Clip], at url: URL) {
        defer { reclassifications.finished(url) }
        guard indexes.needsReclassifying(url), canReclassify(url) else { return }
        guard
            let persistable = ClipReclassification.rewrite(
                updated, from: snapshot, into: indexes.current(in: url),
                liveOrder: indexes.snapshot.wholeList ?? [], secrecy: &secrecy)
        else { return }
        // A refused write leaves the old index version, so the detector retries on the next launch.
        try? indexes.commitReclassified(persistable, in: url)
    }

    /// Applies detector-owned fields only when the classified snapshot still names the current text.
    package static func mergeClassifierResults(
        _ updated: [Clip], from snapshot: [Clip], into current: [Clip]
    ) -> (clips: [Clip], coversCurrentText: Bool) {
        ClipReclassification.merge(updated, from: snapshot, into: current)
    }

    /// Waits for background detector migrations in store tests.
    package func waitForClassifierMigrations() async {
        for task in reclassifications.pending { await task.value }
    }
}
