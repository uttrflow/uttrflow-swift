// Tests for editing a clip's tags from the rename sheet.
import Foundation
import UttrflowClipboard
import Testing

@testable import UttrflowUX

@Suite("Editing tags in the rename sheet")
struct PanelTagEditingTests {
    static let plain = PanelFixture.clip("postgres://prod", minutesAgo: 1)
    static let tagged = PanelFixture.clip(
        "other", minutesAgo: 2, alias: "pg", tags: ["db", "prod"])

    func saved(_ draft: String, on clip: Clip = plain) -> PanelOutcome {
        PanelFixture.panel([Self.plain, Self.tagged])
            .applying([.alias(clip.id), .draft(draft), .return]).outcome
    }

    @Test("words marked with a hash become tags, folded, in typed order, without repeats")
    func parsesTags() {
        let parsed = PanelTags.parse("PG Prod #DB, #próD #db #", locale: .current)

        #expect(parsed.name == "PG Prod")
        #expect(parsed.tags == ["db", "prod"])
        #expect(parsed.fitsLimits)
    }

    @Test("a comma joins tags in one word", arguments: ["#db,#prod", "#db, #prod", "#db #prod"])
    func commaSeparates(_ draft: String) {
        #expect(PanelTags.parse(draft, locale: .current).tags == ["db", "prod"])
    }

    @Test("more than eight tags, or one over 24 characters, does not fit")
    func limits() {
        let nine = (1...9).map { "#t\($0)" }.joined(separator: " ")
        let long = "#" + String(repeating: "a", count: 25)

        #expect(!PanelTags.parse(nine, locale: .current).fitsLimits)
        #expect(!PanelTags.parse(long, locale: .current).fitsLimits)
        #expect(PanelTags.parse("#" + String(repeating: "a", count: 24), locale: .current).fitsLimits)
    }

    @Test("the sheet opens showing the name and the tags")
    func opensWithTags() {
        let panel = PanelFixture.panel([Self.plain, Self.tagged])

        #expect(
            panel.applying(.alias(Self.tagged.id)).state.sheet
                == .aliasing(Self.tagged.id, draft: "pg #db #prod"))
    }

    @Test("adding tags saves the name and the tags together")
    func addsTags() {
        #expect(
            saved("pgprod #DB #prod")
                == .change(.setLabels(Self.plain.id, alias: "pgprod", tags: ["db", "prod"])))
    }

    @Test("tags alone save without a name")
    func tagsWithoutName() {
        #expect(
            saved("#db") == .change(.setLabels(Self.plain.id, alias: nil, tags: ["db"])))
    }

    @Test("emptying the field removes the name and the tags")
    func emptyingRemovesBoth() {
        #expect(
            saved("", on: Self.tagged)
                == .change(.setLabels(Self.tagged.id, alias: nil, tags: [])))
    }

    @Test("removing one tag keeps the other and the name")
    func removesOne() {
        #expect(
            saved("pg #db", on: Self.tagged)
                == .change(.setLabels(Self.tagged.id, alias: "pg", tags: ["db"])))
    }

    @Test("unchanged tags keep the name-only change")
    func renameOnly() {
        #expect(
            saved("pg2 #db #prod", on: Self.tagged) == .change(.setAlias(Self.tagged.id, "pg2")))
    }

    func sheet(_ draft: String) -> PanelSheetPresentation? {
        let state = PanelFixture.panel([Self.plain])
            .applying([.alias(Self.plain.id), .draft(draft)]).state
        return PanelPresenter.present(state).sheet
    }

    @Test("too many tags stay in the sheet and say why")
    func refusesTooMany() {
        let nine = (1...9).map { "#t\($0)" }.joined(separator: " ")
        let panel = PanelFixture.panel([Self.plain])
            .applying([.alias(Self.plain.id), .draft(nine), .return])

        #expect(panel.outcome == .open)
        #expect(sheet(nine)?.conflict == "Use at most 8 tags of 24 characters")
        #expect(sheet(nine)?.isConfirmEnabled == false)
    }

    @Test("a tag edit alone enables Save, and the row carries the tags")
    func presentsTags() {
        let rows = PanelPresenter.present(PanelFixture.panel([Self.tagged])).rows

        #expect(sheet("#db")?.isConfirmEnabled == true)
        #expect(sheet("#db")?.confirmTitle == "Save")
        #expect(rows.first?.tags == ["db", "prod"])
    }
}
