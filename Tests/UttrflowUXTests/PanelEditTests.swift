// Tests for editing a clip's text from the panel: when Edit is offered, and what Save sends the store.
import Foundation
import UttrflowClipboard
import Testing

@testable import UttrflowUX

/// Edit replaces what was copied, so most of these are about when Save must not send anything.
@Suite("Editing a clip's text")
struct PanelEditTests {
    /// Named, tagged, filed and pinned, the clip whose choices an edit must not cost.
    static let kept = PanelFixture.clip(
        "ssh deploy@build.example.com", minutesAgo: 1, alias: "deploy", tags: ["ops"],
        category: "Work", isPinned: true)
    /// Nothing kept about it.
    static let ordinary = PanelFixture.clip("just some text", minutesAgo: 2)
    /// Text the detector takes for a credential.
    static let secretText = "api_key = ff00aa11ff00aa11ff00aa11"

    /// The row's action titles for one clip.
    static func actions(_ clip: Clip, revealed: Set<Clip.ID> = []) -> [String] {
        PanelPresenter.present(PanelFixture.panel([clip], revealed: revealed)).rows[0].actions
            .map(\.title)
    }

    /// The panel with the Edit sheet open over `clip` and `draft` typed into it.
    static func editing(_ clip: Clip, typing draft: String) -> PanelSnapshot {
        PanelFixture.panel([clip, ordinary]).applying(.edit(clip.id)).state
            .applying(.draft(draft)).state
    }

    @Test("offered on every kind of clip that is text", arguments: ClipKind.allCases.filter { $0 != .image })
    func offeredOnText(kind: ClipKind) {
        let clip = PanelFixture.clip("some words", kind: kind)
        let revealed: Set<Clip.ID> = kind == .secret ? [clip.id] : []

        #expect(Self.actions(clip, revealed: revealed).contains("Edit"), "\(kind)")
    }

    @Test("not offered on a picture, which has no text")
    func notOnAPicture() {
        let picture = Clip(
            text: "", kind: .image, copiedAt: PanelFixture.now,
            image: ClipImage(file: "a.png", width: 4, height: 4, bytes: 64, sha: "00"))

        #expect(!Self.actions(picture).contains("Edit"))
    }

    /// Editing a masked secret would put the text it hides on screen without the user asking to see it.
    @Test("not offered on a secret until it is revealed")
    func notOnAMaskedSecret() {
        let secret = PanelFixture.clip(Self.secretText, kind: .secret)

        #expect(!Self.actions(secret).contains("Edit"))
        #expect(PanelFixture.panel([secret]).applying(.edit(secret.id)).state.sheet == nil)
    }

    /// A formatted clip, a note included, is edited with its formatting; see `Docs/panel.md`.
    @Test("not offered on a clip with a formatted form, which plain editing would discard")
    func notOnAFormattedClip() {
        var note = PanelFixture.clip("Groceries")
        note = Clip(
            id: note.id, text: note.text, kind: .text, copiedAt: note.copiedAt,
            richText: "<ul><li>[ ] Milk</li></ul>")

        #expect(!Self.actions(note).contains("Edit"))
        #expect(PanelFixture.panel([note]).applying(.edit(note.id)).state.sheet == nil)
    }

    @Test("opens on the clip's whole text, worded as the issue's Edit and Save")
    func opensOnTheText() {
        let response = PanelFixture.panel([Self.kept]).applying(.edit(Self.kept.id))

        #expect(response.outcome == .open)
        #expect(response.state.sheet == .editing(Self.kept.id, draft: Self.kept.text))
        let sheet = PanelPresenter.present(response.state).sheet
        #expect(sheet?.kind == .editing)
        #expect(sheet?.title == "Edit")
        #expect(sheet?.confirmTitle == "Save")
        #expect(sheet?.draft == Self.kept.text)
        #expect(sheet?.takesTyping == true)
    }

    @Test("Save sends the edited text for the same clip and closes the sheet")
    func savingSendsTheText() {
        let edited = "ssh deploy@staging.example.com"

        let response = Self.editing(Self.kept, typing: edited).applying(.return)

        #expect(response.outcome == .change(.editText(Self.kept.id, edited)))
        #expect(response.state.sheet == nil)
    }

    @Test("Cancel sends nothing and leaves the clip as it was")
    func cancellingSendsNothing() {
        let response = Self.editing(Self.kept, typing: "something else").applying(.escape)

        #expect(response.outcome == .open)
        #expect(response.state.sheet == nil)
        #expect(response.state.clip(Self.kept.id) == Self.kept)
    }

    @Test("Save does nothing while the text is unchanged or blank", arguments: ["", "  \n\t"])
    func blankOrUnchangedStaysOpen(draft: String) {
        for typed in [draft, Self.kept.text] {
            let panel = Self.editing(Self.kept, typing: typed)

            #expect(PanelPresenter.present(panel).sheet?.isConfirmEnabled == false, "\(typed)")
            #expect(panel.applying(.return).outcome == .open, "\(typed)")
        }
    }

    /// The store would refuse it anyway; refusing here keeps what was typed on screen.
    @Test("Save does nothing for text over the largest clip the store keeps")
    func overTheBoundStaysOpen() {
        let bound = ClipboardBudget.standard.largestClip
        let atBound = String(repeating: "a", count: bound)
        let overBound = atBound + "a"

        let fits = Self.editing(Self.ordinary, typing: atBound)
        let tooLarge = Self.editing(Self.ordinary, typing: overBound)

        #expect(PanelPresenter.present(fits).sheet?.isConfirmEnabled == true)
        #expect(PanelPresenter.present(tooLarge).sheet?.isConfirmEnabled == false)
        #expect(tooLarge.applying(.return).outcome == .open)
        #expect(tooLarge.applying(.return).state.sheet == .editing(Self.ordinary.id, draft: overBound))
    }

    /// A secret is never written to disk, so a kept clip edited into one would be gone after a relaunch.
    @Test("a kept clip edited into a secret warns before saving, then saves")
    func keptIntoSecretWarnsFirst() {
        let panel = Self.editing(Self.kept, typing: Self.secretText)
        #expect(PanelPresenter.present(panel).sheet?.conflict == nil, "nothing is said before Save")

        let warned = panel.applying(.return)
        #expect(warned.outcome == .open, "the first Save only warns")
        #expect(
            PanelPresenter.present(warned.state).sheet?.conflict
                == "This will no longer be saved between launches")

        let saved = warned.state.applying(.return)
        #expect(saved.outcome == .change(.editText(Self.kept.id, Self.secretText)))
        #expect(saved.state.sheet == nil)
    }

    @Test("typing after the warning asks again for the new text")
    func typingAfterTheWarningResetsIt() {
        let warned = Self.editing(Self.kept, typing: Self.secretText).applying(.return).state

        let retyped = warned.applying(.draft(Self.secretText + "0")).state

        #expect(PanelPresenter.present(retyped).sheet?.conflict == nil)
        #expect(retyped.applying(.return).outcome == .open)
    }

    /// An unkept clip ages out anyway, and a kept secret is already held in memory only.
    @Test("a clip with nothing to lose saves a secret at once", arguments: [false, true])
    func nothingToLoseSavesAtOnce(isAlreadySecret: Bool) {
        let clip =
            isAlreadySecret
            ? PanelFixture.clip("tok-example-9f3k", kind: .secret, alias: "token")
            : Self.ordinary
        let panel = PanelFixture.panel([clip], revealed: [clip.id]).applying(.edit(clip.id)).state
            .applying(.draft(Self.secretText)).state

        #expect(panel.applying(.return).outcome == .change(.editText(clip.id, Self.secretText)))
    }

    @Test("the row's Edit and the edit key are one path")
    func intentIsTheKey() {
        #expect(PanelIntent.edit(Self.ordinary.id).key == .edit(Self.ordinary.id))
        let row = PanelPresenter.present(PanelFixture.panel([Self.ordinary])).rows[0]
        #expect(row.actions.first { $0.title == "Edit" }?.intent == .edit(Self.ordinary.id))
    }
}

/// Edit played through a real store, where what survives a relaunch is decided.
@Suite("Editing a clip's text, against a store on disk")
struct PanelEditEndToEndTests {
    /// The kept clip, recorded first so a newer clip sits above it.
    static func seedKept(_ harness: PanelEndToEndTests.Harness, text: String) async throws -> Clip {
        let kept = Clip(
            text: text, kind: .text, copiedAt: Date(), alias: "deploy", tags: ["ops"],
            category: "Work", isPinned: true)
        _ = try await harness.store.record(kept, keeping: harness.retention)
        try await harness.seed(["copied later"])
        return kept
    }

    /// The same files, opened by a store that has read nothing yet, as the next launch opens them.
    static func relaunched(_ harness: PanelEndToEndTests.Harness) async -> [Clip] {
        let file = harness.folder.appending(path: "clipboard.json", directoryHint: .notDirectory)
        return await ClipboardStore(file: file).clips(keeping: harness.retention)
    }

    @Test("an edit keeps the name, tags, collection and pin across a relaunch, and moves the clip up")
    func editSurvivesARelaunch() async throws {
        let harness = try PanelEndToEndTests.Harness()
        defer { harness.cleanUp() }
        let kept = try await Self.seedKept(harness, text: "ssh deploy@build.example.com")
        let edited = "ssh deploy@staging.example.com"

        let outcome = try await harness.perform([.edit(kept.id), .draft(edited), .return])

        #expect(outcome == .change(.editText(kept.id, edited)))
        let now = await harness.store.clips(keeping: harness.retention)
        #expect(now.first?.id == kept.id, "an edit is a use, so the clip is the newest")
        let after = try #require(await Self.relaunched(harness).first { $0.id == kept.id })
        #expect(after.text == edited)
        #expect(after.alias == "deploy")
        #expect(after.tags == ["ops"])
        #expect(after.category == "Work")
        #expect(after.isPinned)
        #expect(after.richText == nil)
    }

    /// The warning's promise, kept: the detector runs again on the new text through the store's one path.
    @Test("a kept clip saved as a secret after the warning is masked and not saved between launches")
    func secretAfterWarningIsNotSaved() async throws {
        let harness = try PanelEndToEndTests.Harness()
        defer { harness.cleanUp() }
        let kept = try await Self.seedKept(harness, text: "Deployment notes for Friday")
        let secret = PanelEditTests.secretText

        let warned = try await harness.perform([.edit(kept.id), .draft(secret), .return])
        #expect(warned == .open)
        let saved = try await harness.perform([.edit(kept.id), .draft(secret), .return, .return])

        #expect(saved == .change(.editText(kept.id, secret)))
        let now = await harness.store.clips(keeping: harness.retention)
        #expect(now.first { $0.id == kept.id }?.kind == .secret)
        #expect(await Self.relaunched(harness).contains { $0.id == kept.id } == false)
    }
}
