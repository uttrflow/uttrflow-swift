import Foundation
import Testing
import UttrflowClipboard

@testable import UttrflowUX

/// The two lists, on the panel side.
///
/// History used to be everything, and everything included every finished dictation — one
/// every minute or two against a ⌘C whenever a ⌘C happens. The dictations were therefore
/// always the newest rows and always at the top, and the clipboard the panel exists to be
/// was underneath them. These tests are the arrangement that fixes it: two tabs, each in
/// its own arrival order, and a search that still reaches both.
@Suite("The clipboard, and the tab beside it")
struct PanelOriginTests {
    static let clips = [
        PanelFixture.clip("said just now", minutesAgo: 1, origin: .uttrflow),
        PanelFixture.clip("copied a while back", minutesAgo: 20),
        PanelFixture.clip("said earlier", minutesAgo: 30, origin: .uttrflow),
        PanelFixture.clip("copied yesterday", minutesAgo: 900),
    ]

    static func rows(
        _ scope: PanelScope, clips: [Clip] = PanelOriginTests.clips, query: String = ""
    ) -> [String] {
        var snapshot = PanelFixture.panel(clips, query: query)
        snapshot.scope = scope
        return PanelPresenter.present(snapshot).rows.map(\.summary)
    }

    /// The whole point: what the user copied is not pushed down by what Uttrflow made.
    @Test("History is what you copied, in the order you copied it")
    func historyIsOnlyCopies() {
        #expect(Self.rows(.history) == ["copied a while back", "copied yesterday"])
    }

    @Test("and the tab beside it is what Uttrflow made")
    func uttrflowTabIsOnlyItsOwn() {
        #expect(Self.rows(.uttrflow) == ["said just now", "said earlier"])
    }

    /// Which is the property the split exists for, said as the thing that used to fail:
    /// a dictation a second ago cannot displace a copy from twenty minutes ago, because
    /// they are no longer in the same order.
    @Test("a fresh dictation never takes the top of History")
    func aDictationCannotTakeTheTop() {
        let after = Self.rows(
            .history, clips: [PanelFixture.clip("said this instant", origin: .uttrflow)] + Self.clips
        )

        #expect(after.first == "copied a while back")
    }

    /// A different axis, the same argument the kind filter and the bar already make:
    /// these two tabs are about what the user *did* with a clip, so where it came from
    /// has no business narrowing them.
    @Test("Pinned and Collections hold both, because they are about what you kept")
    func keepingSpansBothLists() {
        let kept = [
            PanelFixture.clip("pinned dictation", minutesAgo: 1, isPinned: true, origin: .uttrflow),
            PanelFixture.clip("pinned copy", minutesAgo: 2, isPinned: true),
            PanelFixture.clip("filed dictation", minutesAgo: 3, category: "Work", origin: .uttrflow),
            PanelFixture.clip("filed copy", minutesAgo: 4, category: "Work"),
        ]

        #expect(Self.rows(.pinned, clips: kept) == ["pinned dictation", "pinned copy"])
        #expect(Self.rows(.collections, clips: kept) == ["filed dictation", "filed copy"])
    }

    /// The failure this nearly shipped as. History no longer means everything, so a
    /// search that fell back to it would have been blind to every dictation — and the tab
    /// built so that dictations are not buried would have made them unfindable instead.
    @Test("a search reaches both lists, whichever tab is open")
    func searchingSpansBothLists() {
        #expect(Self.rows(.history, query: "said") == ["said just now", "said earlier"])
        #expect(Self.rows(.uttrflow, query: "copied") == ["copied a while back", "copied yesterday"])
    }

    // MARK: - What each empty tab says

    @Test("an empty Uttrflow tab says what would fill it")
    func emptyUttrflowTab() {
        var snapshot = PanelFixture.panel([PanelFixture.clip("something copied")])
        snapshot.scope = .uttrflow

        let empty = PanelPresenter.present(snapshot).emptyState

        #expect(empty?.title == "Nothing from Uttrflow")
        #expect(empty?.message.contains("Dictate something") == true)
    }

    /// True rather than alarming: the clipboard has clips in it, and not one of them was
    /// copied. The sentence a full-of-dictations History gets is the one an empty
    /// clipboard gets, because in the only sense History speaks about, it is empty.
    @Test("a History with only dictations behind it says nothing was copied")
    func emptyHistoryOverDictations() {
        var snapshot = PanelFixture.panel([
            PanelFixture.clip("said just now", minutesAgo: 1, origin: .uttrflow)
        ])
        snapshot.scope = .history

        let empty = PanelPresenter.present(snapshot).emptyState

        #expect(empty?.title == "Nothing copied yet")
        #expect(empty?.message.contains("Whatever you copy") == true)
    }

    @Test("and a kind filter over an empty Uttrflow tab names both")
    func kindAndTheUttrflowTab() {
        var snapshot = PanelFixture.panel(Self.clips, filter: .code)
        snapshot.scope = .uttrflow

        let empty = PanelPresenter.present(snapshot).emptyState

        #expect(empty?.title == "No Code from Uttrflow")
        #expect(empty?.message == "Nothing Uttrflow has made is code.")
    }

    /// The sentence this table was corrected for once before, arriving on a new axis: the
    /// shared arm said "Nothing in db — nothing you have copied is filed here", and on
    /// this tab every clause of it is false.
    @Test("an empty Uttrflow tab inside a collection names both, and blames neither wrongly")
    func theUttrflowTabInsideACollection() {
        var snapshot = PanelFixture.panel(
            [
                PanelFixture.clip("copied and filed", minutesAgo: 1, category: "db"),
                PanelFixture.clip("said, unfiled", minutesAgo: 2, origin: .uttrflow),
            ], category: "db")
        snapshot.scope = .uttrflow

        let empty = PanelPresenter.present(snapshot).emptyState

        #expect(empty?.title == "Nothing from Uttrflow in db")
        #expect(empty?.message == "Nothing filed in db came from Uttrflow.")
    }

    /// A search spans both lists by design, so its empty sentence must not claim to have
    /// looked only at what was copied.
    @Test("a fruitless search does not say it only looked at what you copied")
    func theSearchSentenceCoversBothLists() {
        let snapshot = PanelFixture.panel(
            [PanelFixture.clip("said just now", origin: .uttrflow)], query: "absent")

        let empty = PanelPresenter.present(snapshot).emptyState

        #expect(empty?.message == "Nothing on your clipboard mentions “absent”.")
    }

    // MARK: - Coming back to where you were

    /// The panel is dismissed constantly and by design. While History admitted
    /// everything, reopening on History still showed the remembered clip whatever tab it
    /// was found under; now it does not, and the aim would silently move to the top row.
    @Test("reopening comes back to the tab you were on, with your clip still selected")
    func resumingKeepsTheTab() {
        let dictation = PanelFixture.clip("said just now", minutesAgo: 1, origin: .uttrflow)
        let clips = [dictation, PanelFixture.clip("copied a while back", minutesAgo: 20)]

        let panel = PanelSnapshot.opening(
            clips: clips, now: PanelFixture.now, locale: PanelFixture.locale,
            resuming: PanelResume(
                scope: .uttrflow, category: nil, selection: dictation.id, sheet: nil,
                closedAt: PanelFixture.now.addingTimeInterval(-3)))

        #expect(panel.scope == .uttrflow)
        #expect(panel.results.selected?.id == dictation.id)
    }

    /// And a selection the reopened tab cannot show is not restored at all, rather than
    /// falling back to the top — which reads as the panel having moved the user's aim.
    @Test("but a selection the tab cannot show is let go rather than quietly moved")
    func resumingDropsASelectionTheTabHides() {
        let dictation = PanelFixture.clip("said just now", minutesAgo: 1, origin: .uttrflow)
        let clips = [dictation, PanelFixture.clip("copied a while back", minutesAgo: 20)]

        let panel = PanelSnapshot.opening(
            clips: clips, now: PanelFixture.now, locale: PanelFixture.locale,
            resuming: PanelResume(
                scope: .history, category: nil, selection: dictation.id, sheet: nil,
                closedAt: PanelFixture.now.addingTimeInterval(-3)))

        #expect(panel.selection == nil)
        #expect(panel.results.selected?.summary == "copied a while back")
    }

    // MARK: - Getting there

    @Test("the tab is reachable by the same key the others are")
    func theTabIsAKey() {
        let panel = PanelFixture.panel(Self.clips)

        let response = panel.applying(.scope(.uttrflow))

        #expect(response.outcome == .open)
        #expect(response.state.scope == .uttrflow)
        #expect(PanelPresenter.present(response.state).rows.count == 2)
    }
}
