// Starts the legacy picture pass once a launch, off the clipboard actor.

import Foundation
import UttrflowCore

/// Runs `LegacyPictureMigration` once per process in the background, so sealed files do not slow ⇧⌘V.
struct LegacyPictureSealing {
    private var hasStarted = false

    /// The background pass, held so a test can wait for the files it migrates.
    private(set) var pass: Task<Void, Never>?

    /// Starts the pass the first time it is asked; a store without encryption has nothing to seal.
    mutating func startOnce(
        in folder: URL, store: EncryptedStore?, seal: @escaping LegacyPictureMigration.Seal
    ) {
        guard !hasStarted else { return }
        hasStarted = true
        guard let store else { return }
        pass = Task.detached(priority: .utility) {
            await LegacyPictureMigration().run(in: folder, seal: seal)
            try? store.markLegacyMigrationComplete(for: .clipboardPictures)
        }
    }
}
