// Tests for reopening the panel after an accidental dismissal.
import Foundation
import UttrflowClipboard
import Testing

@testable import UttrflowUX

/// The panel is dismissed constantly by design, so an accident must not cost the user their place.
@Suite("A3, A7 · reopening after an accident")
struct PanelResumeTests {
    /// Two filed clips and one loose one.
    static let clips = [
        PanelFixture.clip("one", minutesAgo: 1, category: "Work"),
        PanelFixture.clip("two", minutesAgo: 2, category: "Work"),
        PanelFixture.clip("three", minutesAgo: 3),
    ]
    /// The fixed clock.
    static let now = PanelFixture.now

    /// A resume point closed this many seconds ago.
    static func resume(
        category: String? = "Work", selection: Clip.ID? = nil, sheet: PanelSheet? = nil,
        secondsAgo: TimeInterval = 3
    ) -> PanelResume {
        PanelResume(
            category: category, selection: selection, sheet: sheet,
            closedAt: now.addingTimeInterval(-secondsAgo))
    }

    @Test("A3 · the tab comes back, not Home")
    func theTabComesBack() {
        let panel = PanelSnapshot.opening(
            clips: Self.clips, now: Self.now, resuming: Self.resume())

        #expect(panel.category == "Work")
    }

    @Test("A3 · and so does the row that was highlighted")
    func thePlaceComesBack() {
        let panel = PanelSnapshot.opening(
            clips: Self.clips, now: Self.now,
            resuming: Self.resume(selection: Self.clips[1].id))

        #expect(panel.results.selected?.id == Self.clips[1].id)
    }

    @Test("A7 · a half-typed alias is still there")
    func theDraftSurvives() {
        let sheet = PanelSheet.aliasing(Self.clips[0].id, draft: "pgpr")
        let panel = PanelSnapshot.opening(
            clips: Self.clips, now: Self.now, resuming: Self.resume(sheet: sheet))

        #expect(panel.sheet == sheet)
    }

    /// A panel that remembered for an hour would open in a collection the user had forgotten choosing.
    @Test("but only for as long as a dismissal counts as an accident")
    func theWindowExpires() {
        let panel = PanelSnapshot.opening(
            clips: Self.clips, now: Self.now, resuming: Self.resume(secondsAgo: 120))

        #expect(panel.category == nil)
        #expect(panel.sheet == nil)
    }

    @Test("a first open, with nothing to resume, is Home")
    func firstOpenIsHome() {
        let panel = PanelSnapshot.opening(clips: Self.clips, now: Self.now)

        #expect(panel.category == nil)
        #expect(panel.query.isEmpty)
    }

    /// Restoring a collection whose last clip has aged out would open on an empty list under a chip.
    @Test("a collection that no longer exists is not restored")
    func vanishedCollection() {
        let panel = PanelSnapshot.opening(
            clips: [Self.clips[2]], now: Self.now, resuming: Self.resume())

        #expect(panel.category == nil)
    }

    @Test("nor a question about a clip that has gone")
    func vanishedSubject() {
        let sheet = PanelSheet.confirmingDelete(Self.clips[0].id)
        let panel = PanelSnapshot.opening(
            clips: [Self.clips[2]], now: Self.now, resuming: Self.resume(sheet: sheet))

        #expect(panel.sheet == nil)
    }

    /// The room may have changed between dismissal and reopening, so a revealed secret is masked again.
    @Test("a secret revealed before the dismissal is masked again")
    func revealsDoNotSurvive() {
        let secret = PanelFixture.clip("sk-live-abcdef", kind: .secret, minutesAgo: 1)
        let panel = PanelSnapshot.opening(
            clips: [secret], now: Self.now, resuming: Self.resume(category: nil))

        #expect(panel.revealed.isEmpty)
        #expect(PanelPresenter.present(panel).rows[0].isMasked)
    }

    /// Resuming is about where the user was, not what they were looking for, so the query is dropped.
    @Test("the search field always starts empty")
    func searchDoesNotSurvive() {
        let panel = PanelSnapshot.opening(
            clips: Self.clips, now: Self.now, resuming: Self.resume())

        #expect(panel.query.isEmpty)
    }
}
