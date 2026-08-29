import Foundation
import UttrflowClipboard
import Testing

@testable import UttrflowUX

/// The ring is the panel's answer to "what will Return paste". Searching is where that
/// question matters most — the list has just changed under the reader — so it is where
/// a list with nothing ringed is worst.
@Suite("What Return means after a search")
struct PanelResultsSelectionTests {
    @Test("the first match is selected as soon as the list narrows")
    func firstMatchIsSelected() {
        let panel = PanelFixture.panel(query: "second")
        let presentation = PanelPresenter.present(panel)

        #expect(presentation.rows.count == 1)
        #expect(presentation.rows.first?.isSelected == true)
        #expect(presentation.selectedRow?.summary == "The second thing")
    }

    /// The grouped reading of the list is the same rows in the same order, so the ring
    /// has to survive the grouping.
    @Test("the ring survives being grouped under a heading")
    func groupedRowsKeepTheRing() {
        let presentation = PanelPresenter.present(PanelFixture.panel(query: "second"))
        let grouped = presentation.groups.flatMap(\.rows)

        #expect(!presentation.groups.isEmpty, "a search is grouped")
        #expect(grouped.first?.isSelected == true)
    }

    /// The same thing through the keys the panel actually receives, rather than by
    /// setting the query on a snapshot: the state machine clears the selection on every
    /// keystroke, and it is the results that have to put it back.
    @Test("typing into the panel leaves the first match ringed")
    func typingSelectsTheFirstMatch() {
        let panel = PanelFixture.panel()
        let after = panel.applying(.search("second")).state
        let presentation = PanelPresenter.present(after)

        #expect(after.selection == nil, "the keystroke cleared it")
        #expect(presentation.rows.first?.isSelected == true, "and the results put it back")
    }

    /// A selection left over from before the search, naming a clip the search has
    /// filtered out, falls to the top rather than to nothing.
    @Test("a selection the search filtered away falls to the first match")
    func staleSelectionFallsToTheTop() {
        var panel = PanelFixture.panel(query: "second")
        panel.selection = PanelFixture.clips[2].id

        let presentation = PanelPresenter.present(panel)

        #expect(presentation.rows.first?.isSelected == true)
    }
}
