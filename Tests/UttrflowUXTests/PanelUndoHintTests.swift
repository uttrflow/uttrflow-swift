// Tests for the hint that offers the undo after a delete.
import Foundation
import UttrflowClipboard
import Testing

@testable import UttrflowUX

/// F7 trades the confirmation away for the undo, so an undo nobody is told about makes it a loss.
@Suite("Offering the undo")
struct PanelUndoHintTests {
    /// A plain clip.
    static let clip = PanelFixture.clip("a clip", minutesAgo: 1)

    /// A panel with or without a live undo.
    static func panel(canUndo: Bool) -> PanelSnapshot {
        var snapshot = PanelFixture.panel([Self.clip])
        snapshot.canUndoDelete = canUndo
        return snapshot
    }

    @Test("the hint offers the undo while one is live")
    func offeredWhileLive() {
        #expect(PanelPresenter.present(Self.panel(canUndo: true)).hint == PanelPresenter.undoHint)
        #expect(PanelPresenter.present(Self.panel(canUndo: true)).hint.contains("⌘Z"))
        #expect(PanelPresenter.present(Self.panel(canUndo: true)).hint.contains("last delete only"))
    }

    @Test("and goes back to teaching the keys once it has expired")
    func goneWhenExpired() {
        #expect(PanelPresenter.present(Self.panel(canUndo: false)).hint == PanelPresenter.hint)
    }

    @Test("the presentation says ⌘Z restores exactly while the footer offers it")
    func offersUndoFollowsTheHint() {
        var sheeted = Self.panel(canUndo: true)
        sheeted.sheet = .aliasing(Self.clip.id, draft: "")

        #expect(PanelPresenter.present(Self.panel(canUndo: true)).offersUndo)
        #expect(!PanelPresenter.present(Self.panel(canUndo: false)).offersUndo)
        #expect(!PanelPresenter.present(sheeted).offersUndo)
    }

    /// A sheet has its own keys, and teaching ⌘Z over a field where Return saves is the wrong key.
    @Test("a sheet still outranks the undo offer")
    func theSheetWins() {
        var snapshot = Self.panel(canUndo: true)
        snapshot.sheet = .aliasing(Self.clip.id, draft: "")

        #expect(PanelPresenter.present(snapshot).hint == PanelPresenter.sheetHint)
    }

    @Test("a search keeps the undo offer and teaches Escape to clear it")
    func searchKeepsUndoOffer() {
        var snapshot = PanelFixture.panel([], query: "needle")
        snapshot.canUndoDelete = true
        let presentation = PanelPresenter.present(snapshot)
        #expect(presentation.hint == PanelPresenter.searchUndoHint && presentation.offersUndo)
    }

    /// The panel cannot answer an undo, since only the app still holds the clip, so it maps to no key.
    @Test("undo is an intent the panel deliberately cannot answer")
    func undoIsNotAKey() {
        #expect(PanelIntent.undoDelete.key == nil)
    }
}
