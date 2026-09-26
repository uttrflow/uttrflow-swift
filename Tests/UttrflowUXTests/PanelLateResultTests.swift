// Tests for dropping a late formatter result or notice that no longer belongs to the panel.
import Foundation
import Testing
import UttrflowClipboard

@testable import UttrflowUX

/// A result that arrives after the panel has moved on is dropped, never written over what is there.
@Suite("Late results in the clipboard panel")
struct PanelLateResultTests {
    /// A formatter run on the first clip, asked for in open 3 with no sheet showing.
    static func request(_ panel: PanelSnapshot, run: Int = 1) -> PanelFormatRequest {
        let clip = panel.clips[0]
        return PanelFormatRequest(
            owner: PanelLateRequest(opens: 3, sheet: panel.sheet), clip: clip.id, text: clip.text,
            run: run)
    }

    @Test("a result for the same open, sheet and text is accepted")
    func acceptedWhenNothingMoved() {
        let panel = PanelFixture.panel()
        #expect(Self.request(panel).accepts(into: panel, opens: 3, latestRun: 1))
    }

    @Test("a result after the panel closed is dropped")
    func droppedWhenClosed() {
        #expect(!Self.request(PanelFixture.panel()).accepts(into: nil, opens: 3, latestRun: 1))
    }

    @Test("a result after the panel reopened is dropped")
    func droppedWhenReopened() {
        let panel = PanelFixture.panel()
        #expect(!Self.request(panel).accepts(into: panel, opens: 4, latestRun: 1))
    }

    @Test("a result after another sheet opened is dropped")
    func droppedWhenSheetOpened() {
        var panel = PanelFixture.panel()
        let request = Self.request(panel)
        panel.sheet = .aliasing(panel.clips[0].id, draft: "pg")
        #expect(!request.accepts(into: panel, opens: 3, latestRun: 1))
    }

    @Test("a result for text that has since changed is dropped")
    func droppedWhenTextChanged() {
        let panel = PanelFixture.panel()
        let stale = PanelFormatRequest(
            owner: PanelLateRequest(opens: 3, sheet: nil), clip: panel.clips[0].id,
            text: "The first thing, before an edit", run: 1)
        #expect(!stale.accepts(into: panel, opens: 3, latestRun: 1))
    }

    @Test("a result for a clip no longer in the list is dropped")
    func droppedWhenClipGone() {
        let panel = PanelFixture.panel()
        let request = Self.request(panel)
        #expect(!request.accepts(into: PanelFixture.panel([]), opens: 3, latestRun: 1))
    }

    @Test("a superseded run is dropped when Format was pressed again")
    func droppedWhenSuperseded() {
        let panel = PanelFixture.panel()
        #expect(!Self.request(panel, run: 1).accepts(into: panel, opens: 3, latestRun: 2))
    }

    @Test("a late notice needs only the same open, whatever sheet is showing")
    func noticeNeedsSameOpen() {
        var panel = PanelFixture.panel()
        let owner = PanelLateRequest(opens: 3, sheet: nil)
        panel.sheet = .confirmingDelete(panel.clips[0].id)
        #expect(owner.isSameOpen(panel, opens: 3))
        #expect(!owner.isSameOpen(panel, opens: 4))
        #expect(!owner.isSameOpen(nil, opens: 3))
    }

    @Test("a sheet owner keeps the panel only while the same open shows the same sheet")
    func noticeOwnership() {
        var panel = PanelFixture.panel()
        let owner = PanelLateRequest(opens: 3, sheet: nil)
        #expect(owner.stillOwns(panel, opens: 3))
        #expect(!owner.stillOwns(panel, opens: 4))
        #expect(!owner.stillOwns(nil, opens: 3))
        panel.sheet = .confirmingDelete(panel.clips[0].id)
        #expect(!owner.stillOwns(panel, opens: 3))
    }
}
