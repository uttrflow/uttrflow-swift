// One private-window finding per dictation: any read that saw a private window sets it, and nothing clears it.
import UttrflowCore
import struct Foundation.UUID

extension DictationPipeline {
    /// Marks this dictation private when `read` shows a private-browsing window; a later or timed-out read never clears it.
    func notePrivateWindow(in read: AppContext) {
        if read.isInPrivateWindow { destinationIsPrivate = true }
    }

    /// Tells the kept recording its destination, with this dictation's private-window finding beside the identity.
    func recordDestination(_ destination: AppContext, fieldKind: Destination, for id: UUID) async {
        recordedFacts = (destination, fieldKind, id)
        await recordings.setDestination(
            destination, fieldKind: fieldKind, privateWindow: destinationIsPrivate, for: id)
    }

    /// Adds a private finding made after the destination was recorded, so a retry of this recording learns nothing either.
    func keepPrivateWindowFinding(for id: UUID) async {
        guard destinationIsPrivate else { return }
        let facts = recordedFacts.flatMap { $0.id == id ? $0 : nil }
        let destination = facts?.destination ?? recordingDestination ?? AppContext()
        let fieldKind =
            facts?.fieldKind
            ?? SituationResolver.resolve(from: destination, overrides: runningOverrides).destination
        await recordings.setDestination(destination, fieldKind: fieldKind, privateWindow: true, for: id)
    }
}
