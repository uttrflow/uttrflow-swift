// Tests for formatting a clip: when it is offered, that the app runs it, and the diff sheet.
import Foundation
import UttrflowClipboard
import Testing

@testable import UttrflowUX

/// A formatter rewrites code nobody asked it to touch, so most of this is about when it is not offered.
@Suite("D5, D6, D8 · formatting a clip")
struct PanelFormatTests {
    /// A Swift clip with a confident language.
    static let swiftCode = Clip(
        text: "func a(){\nlet x=1\n}", kind: .code, copiedAt: PanelFixture.now, language: .swift)
    /// Words, which no formatter touches.
    static let prose = PanelFixture.clip("just some words", minutesAgo: 1)

    /// A panel over these clips with these formatters installed.
    static func panel(
        installed: Set<CodeLanguage> = [.swift], clips: [Clip] = [swiftCode]
    )
        -> PanelSnapshot
    {
        var snapshot = PanelFixture.panel(clips)
        snapshot.formattableLanguages = installed
        return snapshot
    }

    /// The first row's action titles.
    static func actions(_ snapshot: PanelSnapshot) -> [String] {
        PanelPresenter.present(snapshot).rows[0].actions.map(\.title)
    }

    /// An offer that fails when pressed is worse than no offer.
    @Test("D5 · offered only where a formatter is actually installed")
    func offeredWhenInstalled() {
        #expect(Self.actions(Self.panel(installed: [.swift])).contains("Format"))
        #expect(!Self.actions(Self.panel(installed: [])).contains("Format"))
        #expect(!Self.actions(Self.panel(installed: [.python])).contains("Format"))
    }

    /// A clip with no confident language has no formatter, and guessing would run the wrong program.
    @Test("never offered on a clip with no confident language")
    func neverWithoutALanguage() {
        let unknown = Clip(text: "x = 1", kind: .code, copiedAt: PanelFixture.now, language: nil)

        #expect(!Self.actions(Self.panel(clips: [unknown])).contains("Format"))
    }

    @Test("and never on prose, whatever is installed")
    func neverOnProse() {
        #expect(!Self.actions(Self.panel(clips: [Self.prose])).contains("Format"))
    }

    /// The model runs nothing; a key on `.format` would send the request where it cannot run and stop there.
    @Test("D5 · formatting is the app's to run, so it carries no key")
    func formattingIsNotTheModelsToAnswer() {
        #expect(PanelIntent.format(Self.swiftCode.id).key == nil)
    }

    /// Re-indenting is the model's own work, so it keeps its key; the line between the two is drawn here.
    @Test("re-indenting, which needs nothing outside, does carry one")
    func reindentingIsTheModelsOwn() {
        #expect(PanelIntent.reindent(Self.swiftCode.id).key == .reindent(Self.swiftCode.id))
    }

    // MARK: D6 — nothing is kept without being shown

    /// The formatting sheet over the Swift clip.
    static func sheet(_ formatted: String) -> PanelSheetPresentation? {
        var snapshot = Self.panel()
        snapshot.sheet = .formatting(Self.swiftCode.id, formatted: formatted)
        return PanelPresenter.present(snapshot).sheet
    }

    /// A sheet that asks "format this code?" has nothing for anyone to type.
    @Test("D6 · the formatting sheet has nothing to type into")
    func nothingToTypeIntoAFormattingSheet() {
        #expect(Self.sheet("func a() {\n    let x = 1\n}")?.takesTyping == false)
    }

    /// The other side of the rule, saying which sheets a field belongs to.
    @Test("and naming a clip still does")
    func namingTakesTyping() {
        var snapshot = Self.panel()
        snapshot.sheet = .aliasing(Self.swiftCode.id, draft: "")
        #expect(PanelPresenter.present(snapshot).sheet?.takesTyping == true)
    }

    @Test("D6 · the sheet says how many lines would change, and shows them")
    func showsTheDiff() {
        let sheet = Self.sheet("func a() {\n    let x = 1\n}")

        #expect(sheet?.kind == .formatting)
        #expect(sheet?.note?.contains("lines would change") == true)
        #expect(sheet?.diff.contains { $0.kind == .added } == true)
        #expect(sheet?.diff.contains { $0.kind == .removed } == true)
        #expect(sheet?.confirmTitle == "Keep it")
    }

    /// A diff of nothing is not a decision, so there is nothing to keep.
    @Test("a formatter that changed nothing offers nothing to keep")
    func nothingToKeep() {
        #expect(Self.sheet(Self.swiftCode.text)?.isConfirmEnabled == false)
    }

    /// The result is carried on the sheet, since running the formatter twice could answer differently.
    @Test("keeping it writes exactly what was shown")
    func keepsWhatWasShown() {
        let formatted = "func a() {\n    let x = 1\n}"
        var snapshot = Self.panel()
        snapshot.sheet = .formatting(Self.swiftCode.id, formatted: formatted)

        let response = snapshot.applying(.return)

        #expect(response.outcome == .change(.rewriteText(Self.swiftCode.id, formatted)))
    }

    @Test("and escaping discards it, leaving the clip alone")
    func discarding() {
        var snapshot = Self.panel()
        snapshot.sheet = .formatting(Self.swiftCode.id, formatted: "anything")

        let response = snapshot.applying(.escape)

        #expect(response.outcome == .open, "not dismissed — the list is still wanted")
        #expect(response.state.sheet == nil)
    }

    // MARK: D8

    /// ⌘ means "exactly what was copied" everywhere in the panel, so formatting needs no second gesture.
    @Test("D8 · ⌘ still pastes exactly what was copied")
    func commandPastesTheOriginal() {
        let effect = Self.panel().applying(.returnPlain).outcome.effect

        #expect(effect == .closeAndInsert(Self.swiftCode.text, used: Self.swiftCode.id))
    }
}
