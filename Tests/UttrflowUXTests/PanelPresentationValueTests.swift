import Testing

@testable import UttrflowUX

@Suite("The public panel presentation value")
struct PanelPresentationValueTests {
    @Test(
        "public construction infers the row and group ring and compares values rather than cache identities"
    )
    func publicConstructionPreservesSelectionAndEquality() {
        let original = PanelPresenter.present(PanelFixture.panel(query: "second"))
        func reconstruct() -> PanelPresentation {
            PanelPresentation(
                rows: original.rows, filters: original.filters, categories: original.categories,
                query: original.query, searchPlaceholder: original.searchPlaceholder,
                emptyState: original.emptyState, hint: original.hint, groups: original.listGroups)
        }
        let first = reconstruct()
        let second = reconstruct()

        #expect(first.selectedRow?.id == PanelFixture.clips[1].id)
        #expect(
            first.groups.flatMap(\.rows).filter(\.isSelected).map(\.id)
                == [PanelFixture.clips[1].id])
        #expect(first.rowCacheID != second.rowCacheID)
        #expect(first == second)
    }
}
