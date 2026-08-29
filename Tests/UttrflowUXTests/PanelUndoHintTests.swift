import Foundation
import UttrflowClipboard
import Testing

@testable import UttrflowUX

/// F7 trades the confirmation dialog away *for* the undo. An undo nobody is told about
/// turns that trade into a loss: the clip is gone with neither a question beforehand nor
/// a visible way back afterwards.
@Suite("Offering the undo")
struct PanelUndoHintTests {
    static let clip = PanelFixture.clip("a clip", minutesAgo: 1)

    static func panel(canUndo: Bool) -> PanelSnapshot {
        var snapshot = PanelFixture.panel([Self.clip])
        snapshot.canUndoDelete = canUndo
        return snapshot
    }

    @Test("the hint offers the undo while one is live")
    func offeredWhileLive() {
        #expect(PanelPresenter.present(Self.panel(canUndo: true)).hint == PanelPresenter.undoHint)
        #expect(PanelPresenter.present(Self.panel(canUndo: true)).hint.contains("⌘Z"))
    }

    @Test("and goes back to teaching the keys once it has expired")
    func goneWhenExpired() {
        #expect(PanelPresenter.present(Self.panel(canUndo: false)).hint == PanelPresenter.hint)
    }

    /// A sheet has its own keys, and the ones it displaces include Return. Teaching ⌘Z
    /// over a field where Return saves would be teaching the wrong key at the moment it
    /// matters most.
    @Test("a sheet still outranks the undo offer")
    func theSheetWins() {
        var snapshot = Self.panel(canUndo: true)
        snapshot.sheet = .aliasing(Self.clip.id, draft: "")

        #expect(PanelPresenter.present(snapshot).hint == PanelPresenter.sheetHint)
    }

    /// The panel cannot answer an undo: the store has forgotten the clip and only the app
    /// is still holding it. So it carries no identity and maps to no key.
    @Test("undo is an intent the panel deliberately cannot answer")
    func undoIsNotAKey() {
        #expect(PanelIntent.undoDelete.key == nil)
    }
}
