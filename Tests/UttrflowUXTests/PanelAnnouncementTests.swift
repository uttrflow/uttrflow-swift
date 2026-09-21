// Tests for what VoiceOver is told about the panel's notices and rows.
import Foundation
import UttrflowClipboard
import Testing

@testable import UttrflowUX

/// A notice nobody hears is, for a VoiceOver user, a paste that silently did nothing.
@Suite("What the panel says aloud")
struct PanelAnnouncementTests {
    /// A panel over one clip with this notice, undo state and insertion.
    static func panel(
        notice: PanelNotice? = nil, canUndo: Bool = false, insertion: PanelInsertion = .atCaret
    ) -> PanelPresentation {
        var snapshot = PanelFixture.panel([PanelFixture.clip("a clip", minutesAgo: 1)])
        snapshot.notice = notice
        snapshot.canUndoDelete = canUndo
        snapshot.insertion = insertion
        return PanelPresenter.present(snapshot)
    }

    @Test("a quiet panel announces nothing")
    func quietPanel() {
        #expect(Self.panel().announcements.isEmpty)
    }

    @Test("every copy-only notice is announced in its own words", arguments: PanelInsertionObstacle.allCases)
    func copyOnlyNotices(_ obstacle: PanelInsertionObstacle) {
        #expect(Self.panel(notice: obstacle.notice).announcements == [obstacle.notice.message])
    }

    @Test("a refused write is announced")
    func refusedWrite() {
        let notice = PanelNotice.writeFailed("The clipboard could not be saved.")
        #expect(Self.panel(notice: notice).announcements == ["The clipboard could not be saved."])
    }

    @Test("a missing picture is announced")
    func missingPicture() {
        let clip = PanelFixture.clip("", kind: .image)
        guard case .say(let notice) = PanelOutcome.pictureMissing(clip).effect else {
            Issue.record("a missing picture should say something")
            return
        }
        #expect(Self.panel(notice: notice).announcements == [notice.message])
    }

    @Test("the undo offer is announced with its key spelled out")
    func undoOffer() {
        #expect(Self.panel(canUndo: true).announcements == [PanelPresenter.undoAnnouncement])
        #expect(PanelPresenter.undoAnnouncement.contains("Command-Z"))
    }

    @Test("a notice and the undo offer are both announced")
    func both() {
        let notice = PanelNotice.writeFailed("The clipboard could not be saved.")
        #expect(
            Self.panel(notice: notice, canUndo: true).announcements
                == ["The clipboard could not be saved.", PanelPresenter.undoAnnouncement])
    }

    @Test("a row promises a paste only when the panel can paste")
    func rowHintAtCaret() {
        #expect(Self.panel().rowHint == PanelPresenter.pasteRowHint)
    }

    @Test("and says it copies when the panel can only copy", arguments: PanelInsertionObstacle.allCases)
    func rowHintCopyOnly(_ obstacle: PanelInsertionObstacle) {
        let hint = Self.panel(insertion: .clipboardOnly(obstacle)).rowHint
        #expect(hint == PanelPresenter.copyRowHint)
        #expect(hint.contains("Copies"))
    }
}
