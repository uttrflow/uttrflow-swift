import Foundation
import Testing
import UttrflowClipboard

@testable import UttrflowUX

/// What the ⋯ menu is given to draw.
///
/// The menu took over two jobs the row used to do — saying when a clip arrived, and
/// offering everything that can be done to it — so both of those are decided here rather
/// than in the view. The view draws a header and a list; it works out nothing.
@Suite("The row's menu")
struct PanelRowMenuTests {
    private func row(_ clip: Clip) -> PanelRow {
        let snapshot = PanelFixture.panel([clip])
        return PanelPresenter.present(snapshot).rows[0]
    }

    // MARK: - The header line

    /// Where the row's timestamp went. Taking it off sixteen rows only works if it lands
    /// somewhere, and this is the somewhere.
    @Test("the header says what it is, when it arrived and where from")
    func detailNamesAllThree() {
        let clip = Clip(
            text: "lru budget check", kind: .text,
            copiedAt: PanelFixture.now.addingTimeInterval(-41 * 60), source: "Claude")

        #expect(row(clip).detail == "Text · 41 minutes ago · Claude")
    }

    /// A clip old enough to predate the source being recorded has no "where from", and a
    /// header that printed the separator anyway would end on a dangling middle dot.
    @Test("and drops the source rather than dangling a separator")
    func detailWithoutASource() {
        let clip = Clip(
            text: "from nowhere", kind: .text,
            copiedAt: PanelFixture.now.addingTimeInterval(-120), source: nil)

        let detail = row(clip).detail

        #expect(detail == "Text · 2 minutes ago")
        #expect(!detail.hasSuffix("·"))
        #expect(!detail.contains("· ·"))
    }

    /// Blank is the same as absent. A source of spaces would otherwise pass the `nil`
    /// test and print a separator with nothing after it.
    @Test("a blank source counts as no source")
    func blankSourceIsNoSource() {
        let clip = Clip(
            text: "spaces", kind: .text, copiedAt: PanelFixture.now.addingTimeInterval(-60),
            source: "   ")

        #expect(row(clip).detail == "Text · 1 minute ago")
    }

    /// Named as somebody would say it, not as the enum spells it: a row for a copied path
    /// says "File path", not "filePath".
    @Test("every kind has a word a person would use")
    func everyKindIsNamed() {
        for kind in ClipKind.allCases {
            let noun = PanelPresenter.noun(for: kind)
            #expect(!noun.isEmpty)
            #expect(noun == noun.lowercased(), "\(kind) is capitalised by the header, not here")
            #expect(!noun.contains { $0.isUppercase }, "\(kind) reads as an identifier")
        }
        #expect(PanelPresenter.noun(for: .filePath) == "file path")
    }

    @Test("and the header capitalises it")
    func theHeaderCapitalisesTheKind() {
        let clip = Clip(
            text: "https://example.com", kind: .link,
            copiedAt: PanelFixture.now.addingTimeInterval(-60), source: "Safari")

        #expect(row(clip).detail.hasPrefix("Link · "))
    }

    // MARK: - What takes something away

    /// The view used to be able to guess this from the trash symbol or the last position
    /// in the list, and both are true of Delete only by coincidence — an action added
    /// after it would silently stop being marked.
    @Test("Delete is the destructive one, and it is the only one")
    func onlyDeleteIsDestructive() {
        let clip = Clip(
            text: "let x = 1", kind: .code, copiedAt: PanelFixture.now, source: "Cursor",
            language: .swift)
        let actions = row(clip).actions

        let destructive = actions.filter(\.isDestructive)

        #expect(destructive.map(\.title) == ["Delete"])
        #expect(actions.count > 1, "a menu of one action is not a menu")
    }

    /// It is drawn last and separated from the rest, so it being last is load-bearing on
    /// screen even though nothing infers destructiveness from the position any more.
    @Test("and it is offered last")
    func deleteComesLast() {
        #expect(
            row(PanelFixture.clip("something")).actions.last?.title == "Delete")
    }

    /// Everything the menu draws comes from here, so an action with no icon or no words
    /// would be a blank line nobody could press with any confidence.
    @Test("every action has words and an icon")
    func everyActionIsDrawable() {
        for clip in [
            PanelFixture.clip("plain words"),
            PanelFixture.clip("https://example.com", kind: .link),
            PanelFixture.clip("secret", kind: .secret),
        ] {
            for action in row(clip).actions {
                #expect(!action.title.isEmpty)
                #expect(!action.symbolName.isEmpty)
            }
        }
    }
}
