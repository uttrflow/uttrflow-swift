// Tests for which row is ringed after a search.
import Foundation
import UttrflowClipboard
import Testing

@testable import UttrflowUX

/// The ring answers "what will Return paste", and it matters most just after the list has changed.
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

    /// The grouped reading is the same rows in the same order, so the ring survives grouping.
    @Test("the ring survives being grouped under a heading")
    func groupedRowsKeepTheRing() {
        let presentation = PanelPresenter.present(PanelFixture.panel(query: "second"))
        let grouped = presentation.groups.flatMap(\.rows)

        #expect(!presentation.groups.isEmpty, "a search is grouped")
        #expect(grouped.first?.isSelected == true)
    }

    /// Through the keys the panel receives: a keystroke clears the selection and the results put it back.
    @Test("typing into the panel leaves the first match ringed")
    func typingSelectsTheFirstMatch() {
        let panel = PanelFixture.panel()
        let after = panel.applying(.search("second")).state
        let presentation = PanelPresenter.present(after)

        #expect(after.selection == nil, "the keystroke cleared it")
        #expect(presentation.rows.first?.isSelected == true, "and the results put it back")
    }

    /// A selection naming a clip the search filtered out falls to the top rather than to nothing.
    @Test("a selection the search filtered away falls to the first match")
    func staleSelectionFallsToTheTop() {
        var panel = PanelFixture.panel(query: "second")
        panel.selection = PanelFixture.clips[2].id

        let presentation = PanelPresenter.present(panel)

        #expect(presentation.rows.first?.isSelected == true)
    }
}
