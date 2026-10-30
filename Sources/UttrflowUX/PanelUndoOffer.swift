// Tracks which delete or edit the panel's undo offer describes, so an older delete finishing late cannot claim it.
package import Foundation
package import UttrflowClipboard

/// The one delete or text edit that can be undone, and a count of deletes so a late one can tell it was superseded.
package struct PanelUndoOffer: Sendable, Equatable {
    /// The clips the undo offer restores, empty when there is nothing to undo.
    package private(set) var clips: [Clip] = []
    /// The first clip, retained for callers that only need to know whether an offer exists.
    package var clip: Clip? { clips.first }
    /// The clip and its text before the most recent edit, when that edit is what undo reverses.
    package private(set) var edit: PanelUndoEdit?
    /// How many deletes have been offered; each delete's ticket is the value it saw.
    package private(set) var deletes = 0
    /// The store operation that must finish before the current offer can be restored.
    package private(set) var pendingDelete: Task<Result<Void, ClipboardStoreError>, Never>?

    package static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.clips == rhs.clips && lhs.edit == rhs.edit && lhs.deletes == rhs.deletes
    }

    /// An empty offer.
    package init() {}

    /// Offers every removed clip as one undo action and returns that delete's ticket.
    package mutating func offer(_ clips: [Clip]) -> Int {
        deletes += 1
        self.clips = clips
        edit = nil
        pendingDelete = nil
        return deletes
    }

    /// Offers a text edit as the one undo action, superseding any delete still on offer.
    package mutating func offerEdit(of id: UUID, previousText: String) {
        withdraw()
        edit = PanelUndoEdit(id: id, previousText: previousText)
    }

    /// Associates the delete operation with its offer while allowing undo to wait for it.
    package mutating func trackDelete(
        _ task: Task<Result<Void, ClipboardStoreError>, Never>, ticket: Int
    ) {
        guard isLatest(ticket) else { return }
        pendingDelete = task
    }

    /// Claims the current clips and their delete task so only this request can restore them.
    package mutating func claimForRestore() -> PanelUndoClaim? {
        guard !clips.isEmpty || edit != nil else { return nil }
        let claim = PanelUndoClaim(clips: clips, edit: edit, pendingDelete: pendingDelete)
        withdraw()
        return claim
    }

    /// Completes a reserved collection-delete offer without changing its ticket.
    package mutating func complete(_ ticket: Int, with clips: [Clip]) -> Bool {
        guard isLatest(ticket) else { return false }
        self.clips = clips
        return true
    }

    /// Whether the delete holding `ticket` is still the one the offer describes.
    package func isLatest(_ ticket: Int) -> Bool { ticket == deletes }

    /// Withdraws the offer; a delete still in flight is superseded by it.
    package mutating func withdraw() {
        deletes += 1
        clips = []
        edit = nil
        pendingDelete = nil
    }
}

/// A clip's text as it stood before an edit, which undo writes back.
package struct PanelUndoEdit: Sendable, Equatable {
    /// The edited clip.
    package let id: UUID
    /// The text the edit replaced.
    package let previousText: String
}

/// A claimed undo whose clip must wait for its delete to finish before restoration.
package struct PanelUndoClaim: Sendable {
    /// The clips this claim restores as one action.
    package let clips: [Clip]
    /// The edit this claim reverses, when the last change was an edit rather than a delete.
    package let edit: PanelUndoEdit?
    /// The first clip for code that only needs to identify an existing claim.
    package var clip: Clip? { clips.first }
    fileprivate let pendingDelete: Task<Result<Void, ClipboardStoreError>, Never>?

    /// Waits for the delete tied to this clip and preserves its write error.
    package func waitForDelete() async throws(ClipboardStoreError) {
        guard let pendingDelete else { return }
        switch await pendingDelete.value {
        case .success:
            return
        case .failure(let error):
            throw error
        }
    }
}

/// Withdraws the undo offer before awaiting picture cleanup.
@MainActor
package enum PanelUndoExpiry {
    /// Runs the offer withdrawal synchronously before releasing held pictures.
    package static func expire(withdraw: () -> Void, releasingPictures: () async -> Void) async {
        withdraw()
        await releasingPictures()
    }
}
