// Tests what the panel says when clipboard capture is off or paused.
import Foundation
import Testing

@testable import UttrflowUX

@Suite("The panel when clipboard capture is off or paused")
struct PanelCaptureTests {
    private let resumes = PanelFixture.now.addingTimeInterval(41 * 60 + 10)

    @Test("capture on says nothing about capture, with an empty list or a full one")
    func onIsSilent() {
        let empty = PanelPresenter.present(PanelFixture.panel([]))
        #expect(empty.emptyState?.title == "Nothing copied yet")
        #expect(empty.emptyAction == nil)
        let full = PanelPresenter.present(PanelFixture.panel([PanelFixture.clip("one")]))
        #expect(full.notice == nil)
    }

    @Test("capture off says so over an empty list and offers to turn it on")
    func offEmpty() {
        var snapshot = PanelFixture.panel([])
        snapshot.capture = .off
        let shown = PanelPresenter.present(snapshot)
        #expect(shown.emptyState?.title == "Clipboard history is off")
        #expect(shown.emptyAction?.intent == .turnOnCapture)
        #expect(shown.emptyAction?.title == "Turn on")
    }

    @Test("a pause says the minutes left, rounded up, and offers to resume")
    func pausedEmpty() {
        var snapshot = PanelFixture.panel([])
        snapshot.capture = .paused(until: resumes)
        let shown = PanelPresenter.present(snapshot)
        #expect(shown.emptyState?.title == "Clipboard history is paused")
        #expect(shown.emptyState?.message.hasPrefix("Paused, 42 minutes left.") == true)
        #expect(shown.emptyAction?.intent == .resumeCapture)
    }

    @Test("a banner over a non-empty list says the same, with the same button")
    func bannerOverClips() {
        var snapshot = PanelFixture.panel([PanelFixture.clip("one")])
        snapshot.capture = .off
        let off = PanelPresenter.present(snapshot)
        #expect(off.emptyState == nil)
        #expect(off.notice?.message == "Clipboard history is off")
        #expect(off.notice?.action?.intent == .turnOnCapture)

        snapshot.capture = .paused(until: PanelFixture.now.addingTimeInterval(30))
        let paused = PanelPresenter.present(snapshot)
        #expect(paused.notice?.message == "Paused, 1 minute left.")
        #expect(paused.notice?.action?.intent == .resumeCapture)
    }

    @Test("a notice the app set is not hidden by the banner")
    func appNoticeWins() {
        var snapshot = PanelFixture.panel([PanelFixture.clip("one")])
        snapshot.capture = .off
        snapshot.notice = .writeFailed("The disk is full.")
        #expect(PanelPresenter.present(snapshot).notice?.message == "The disk is full.")
    }

    @Test("the banner keeps one identity across redraws")
    func bannerIsAnnouncedOnce() {
        var snapshot = PanelFixture.panel([PanelFixture.clip("one")])
        snapshot.capture = .off
        #expect(
            PanelPresenter.present(snapshot).notice?.announcementID
                == PanelPresenter.present(snapshot).notice?.announcementID)
    }
}
