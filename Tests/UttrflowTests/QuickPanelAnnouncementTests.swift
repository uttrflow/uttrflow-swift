// Tests that the panel speaks notices on each opening without repeating them on redraws.

import Testing
import UttrflowUX

@testable import Uttrflow

@MainActor
@Suite("Quick panel announcement lifecycle", .serialized)
struct QuickPanelAnnouncementTests {
    private func presentation(_ notice: PanelNotice, query: String = "") -> PanelPresentation {
        PanelPresentation(
            rows: [], filters: [], categories: [], query: query,
            searchPlaceholder: PanelPresenter.searchPlaceholder,
            emptyState: nil, hint: PanelPresenter.undoHint,
            notice: notice,
            announcements: [notice.message, PanelPresenter.undoAnnouncement])
    }

    @Test("a notice and undo offer are spoken on every opening, not on unrelated redraws")
    func repeatsOnlyAfterReopening() {
        let notice = PanelNotice.writeFailed("The clipboard could not be saved.")
        let panel = QuickPanelController()
        var heard: [String] = []
        panel.announce = { heard.append($0) }
        defer { panel.hide() }

        let first = presentation(notice)
        panel.show(first)
        #expect(heard == [notice.message, PanelPresenter.undoAnnouncement])

        panel.update(first)
        panel.update(presentation(notice, query: "clip"))
        #expect(heard == [notice.message, PanelPresenter.undoAnnouncement])

        panel.hide()
        panel.show(first)
        #expect(
            heard == [
                notice.message, PanelPresenter.undoAnnouncement,
                notice.message, PanelPresenter.undoAnnouncement,
            ])

        let replacement = PanelNotice.writeFailed("A different notice.")
        panel.update(presentation(replacement))
        #expect(heard.last == replacement.message)
        #expect(heard.count == 5)

        panel.hide()
        panel.update(presentation(notice))
        #expect(heard.count == 5)
    }

    @Test("repeated delete and copy events speak again when their wording is unchanged")
    func repeatedEventsAreSpoken() {
        let panel = QuickPanelController()
        var heard: [String] = []
        panel.announce = { heard.append($0) }
        defer { panel.hide() }

        func event(_ line: String, id: UUID) -> PanelPresentation {
            PanelPresentation(
                rows: [], filters: [], categories: [], query: "",
                searchPlaceholder: PanelPresenter.searchPlaceholder,
                emptyState: nil, hint: PanelPresenter.undoHint, notice: nil,
                announcements: [line], announcementIDs: [id])
        }

        let deleted = PanelPresenter.undoAnnouncement
        let firstDelete = UUID()
        panel.show(event(deleted, id: firstDelete))
        panel.update(event(deleted, id: firstDelete))
        panel.update(event(deleted, id: UUID()))

        let opening = "Turn on Accessibility and Uttrflow can paste for you."
        panel.update(event(opening, id: UUID()))
        #expect(!opening.contains("Copied"))
        let copied = "Copied — press ⌘V. Turn on Accessibility and Uttrflow can paste for you."
        let firstCopy = UUID()
        panel.update(event(copied, id: firstCopy))
        panel.update(event(copied, id: firstCopy))
        panel.update(event(copied, id: UUID()))

        #expect(heard == [deleted, deleted, opening, copied, copied])
    }
}
