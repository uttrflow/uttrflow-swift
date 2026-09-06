// Tests for the two arrival tabs: what the user copied, what Uttrflow made, and the search across both.
import Foundation
import Testing
import UttrflowClipboard

@testable import UttrflowUX

/// Two tabs each in arrival order, so dictations never bury the clipboard, and a search reaches both.
@Suite("The clipboard, and the tab beside it")
struct PanelOriginTests {
    /// Two dictations and two copies, interleaved by age.
    static let clips = [
        PanelFixture.clip("said just now", minutesAgo: 1, origin: .uttrflow),
        PanelFixture.clip("copied a while back", minutesAgo: 20),
        PanelFixture.clip("said earlier", minutesAgo: 30, origin: .uttrflow),
        PanelFixture.clip("copied yesterday", minutesAgo: 900),
    ]

    /// The summaries a scope shows over these clips.
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

    /// A dictation a second ago cannot displace a copy from twenty minutes ago; they are in separate orders.
    @Test("a fresh dictation never takes the top of History")
    func aDictationCannotTakeTheTop() {
        let after = Self.rows(
            .history, clips: [PanelFixture.clip("said this instant", origin: .uttrflow)] + Self.clips
        )

        #expect(after.first == "copied a while back")
    }

    /// These two tabs are about what the user did with a clip, so its origin does not narrow them.
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

    /// A search that fell back to History would be blind to every dictation.
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

    /// True rather than alarming: in the only sense History speaks about, it is empty.
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

    /// On this tab every clause of the shared "nothing you have copied is filed here" would be false.
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

    /// A search spans both lists, so its empty sentence must not claim to have looked at copies only.
    @Test("a fruitless search does not say it only looked at what you copied")
    func theSearchSentenceCoversBothLists() {
        let snapshot = PanelFixture.panel(
            [PanelFixture.clip("said just now", origin: .uttrflow)], query: "absent")

        let empty = PanelPresenter.present(snapshot).emptyState

        #expect(empty?.message == "Nothing on your clipboard mentions “absent”.")
    }

    // MARK: - Coming back to where you were

    /// History does not show a dictation, so reopening must come back to the tab that does.
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

    /// A selection the reopened tab cannot show is let go rather than moved to the top row.
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
