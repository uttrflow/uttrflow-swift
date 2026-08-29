import Foundation
import UttrflowClipboard
import Testing

@testable import UttrflowUX

/// D5, D6, D8. A formatter rewrites code the user did not ask it to touch, so almost all
/// of this is about when it is *not* offered and what has to happen before it is kept.
@Suite("D5, D6, D8 · formatting a clip")
struct PanelFormatTests {
    static let swiftCode = Clip(
        text: "func a(){\nlet x=1\n}", kind: .code, copiedAt: PanelFixture.now, language: .swift)
    static let prose = PanelFixture.clip("just some words", minutesAgo: 1)

    static func panel(
        installed: Set<CodeLanguage> = [.swift], clips: [Clip] = [swiftCode]
    )
        -> PanelSnapshot
    {
        var snapshot = PanelFixture.panel(clips)
        snapshot.formattableLanguages = installed
        return snapshot
    }

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

    /// A clip whose language was never confidently detected has no formatter to pick, and
    /// guessing one would run the wrong program over somebody's code.
    @Test("never offered on a clip with no confident language")
    func neverWithoutALanguage() {
        let unknown = Clip(text: "x = 1", kind: .code, copiedAt: PanelFixture.now, language: nil)

        #expect(!Self.actions(Self.panel(clips: [unknown])).contains("Format"))
    }

    @Test("and never on prose, whatever is installed")
    func neverOnProse() {
        #expect(!Self.actions(Self.panel(clips: [Self.prose])).contains("Format"))
    }

    /// The model runs nothing. Another program is the app's business, and a panel that
    /// spawned processes could not be tested without one.
    /// This is where the dead button hid. The old test asked the model what `.format`
    /// did to it and was satisfied by "nothing" — which is exactly what the bug looked
    /// like. Both the panel view and the app hand an intent to the model whenever the
    /// intent has a key, so a key on `.format` meant the request reached the one place
    /// that cannot run a formatter and stopped there. Pressing the wand did nothing at
    /// all, and the diff sheet was unreachable in a shipped build.
    ///
    /// The question worth asking is therefore not what the model does with it, but
    /// whether the model is asked at all.
    @Test("D5 · formatting is the app's to run, so it carries no key")
    func formattingIsNotTheModelsToAnswer() {
        #expect(PanelIntent.format(Self.swiftCode.id).key == nil)
    }

    /// The neighbours, so the line between the two groups is drawn rather than implied.
    /// Re-indenting really is the model's own work — it rewrites text with no help from
    /// outside — and it must keep its key.
    @Test("re-indenting, which needs nothing outside, does carry one")
    func reindentingIsTheModelsOwn() {
        #expect(PanelIntent.reindent(Self.swiftCode.id).key == .reindent(Self.swiftCode.id))
    }

    // MARK: D6 — nothing is kept without being shown

    static func sheet(_ formatted: String) -> PanelSheetPresentation? {
        var snapshot = Self.panel()
        snapshot.sheet = .formatting(Self.swiftCode.id, formatted: formatted)
        return PanelPresenter.present(snapshot).sheet
    }

    /// Seen on screen: an empty, focused text box sat above the diff, because the view
    /// drew a field for every sheet except the delete confirmation. A sheet that asks
    /// "format this code?" has nothing for anyone to type.
    @Test("D6 · the formatting sheet has nothing to type into")
    func nothingToTypeIntoAFormattingSheet() {
        #expect(Self.sheet("func a() {\n    let x = 1\n}")?.takesTyping == false)
    }

    /// The other side of the same rule, so it says which sheets a field belongs to
    /// rather than only which one it does not.
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

    /// A diff of nothing is not a decision, and offering one would ask the user to approve
    /// a change that does not exist.
    @Test("a formatter that changed nothing offers nothing to keep")
    func nothingToKeep() {
        #expect(Self.sheet(Self.swiftCode.text)?.isConfirmEnabled == false)
    }

    /// The result is carried on the sheet rather than recomputed on accept: running the
    /// formatter twice could answer differently, and the user agreed to *this* answer.
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

    /// D8 — both reachable. ⌘ already means "exactly what was copied" everywhere else in
    /// the panel, so formatting needed no second gesture for it.
    @Test("D8 · ⌘ still pastes exactly what was copied")
    func commandPastesTheOriginal() {
        let effect = Self.panel().applying(.returnPlain).outcome.effect

        #expect(effect == .closeAndInsert(Self.swiftCode.text, used: Self.swiftCode.id))
    }
}
