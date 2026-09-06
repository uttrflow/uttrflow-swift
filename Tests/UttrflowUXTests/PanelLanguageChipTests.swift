// Tests for the language chip on a row, and for the language being decided when a clip arrives.
import Foundation
import UttrflowClipboard
import Testing

@testable import UttrflowUX

/// The detector refuses to guess, and these prove the refusal reaches the screen as nothing at all.
@Suite("The language chip on a row")
struct PanelLanguageChipTests {
    /// The row for one clip.
    static func row(_ clip: Clip) -> PanelRow {
        PanelPresenter.present(PanelFixture.panel([clip])).rows[0]
    }

    @Test("D1 · a confidently detected language is drawn, short")
    func detectedIsDrawn() {
        let code = Clip(
            text: "struct A {}", kind: .code, copiedAt: PanelFixture.now, language: .typescript)

        #expect(Self.row(code).language == "ts", "the chip is the short form, not the name")
    }

    /// Nothing detected means nothing drawn; an empty chip would say the app looked and failed.
    @Test("D2, D3 · nothing is drawn when there was no confident answer")
    func undetectedDrawsNothing() {
        let ambiguous = Clip(
            text: "let x = 1", kind: .code, copiedAt: PanelFixture.now, language: nil)
        let prose = PanelFixture.clip("just some words", minutesAgo: 1)

        #expect(Self.row(ambiguous).language == nil)
        #expect(Self.row(prose).language == nil)
    }

    /// A masked row says as little as possible until asked, and a chip is one more thing on it.
    @Test("a masked row carries no chip")
    func maskedRowsCarryNothing() {
        let secret = Clip(
            text: "sk-live-abcdef123456", kind: .secret, copiedAt: PanelFixture.now,
            language: .swift)

        let row = Self.row(secret)
        #expect(row.isMasked)
        #expect(row.language == nil)
    }

    /// Revealing is what the user asking looks like.
    @Test("and carries one again once it has been revealed")
    func revealedRowsShowIt() {
        let secret = Clip(
            text: "let key = \"x\"", kind: .secret, copiedAt: PanelFixture.now, language: .swift)
        let panel = PanelFixture.panel([secret], revealed: [secret.id])

        #expect(PanelPresenter.present(panel).rows[0].language == "swift")
    }
}

/// The detector runs once, when the clip arrives, not on every keystroke while the panel is drawn.
@Suite("Where the language is decided")
struct ClipLanguageStorageTests {
    @Test("a clip carries its own language, and drawing does not recompute it")
    func theClipCarriesIt() {
        // Deliberately contradictory: a row detecting for itself would answer Swift.
        let mislabelled = Clip(
            text: "struct A: Sendable { let x: Int }", kind: .code,
            copiedAt: PanelFixture.now, language: .sql)

        #expect(PanelPresenter.present(PanelFixture.panel([mislabelled])).rows[0].language == "sql")
    }

    @Test("a clip that predates the field decodes with no language rather than failing")
    func oldClipsStillDecode() throws {
        let old = """
            {"id":"1E30555C-3E63-4D24-837A-DF251ADC876E","text":"x",
             "kind":"code","copiedAt":1,"isPinned":false}
            """

        let clip = try JSONDecoder().decode(Clip.self, from: Data(old.utf8))

        #expect(clip.language == nil)
        #expect(clip.text == "x")
    }
}
