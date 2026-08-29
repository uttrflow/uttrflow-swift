import Foundation
import UttrflowClipboard
import UttrflowUX
import Testing

@testable import Uttrflow

private func row(
    _ text: String = "a clip", kind: ClipKind = .text, isSelected: Bool = false,
    isMasked: Bool = false, alias: String? = nil
) -> PanelRow {
    PanelRow(
        id: UUID(), summary: text, kind: kind, symbolName: "doc", when: "2 minutes ago",
        alias: alias, category: nil, isPinned: false, isMasked: isMasked,
        isSelected: isSelected, matched: nil, isMonospaced: false, actions: [])
}

/// Hover is the one thing about the panel the presentation cannot know, so the rule for
/// reconciling it with the selection lives in the app target. It is a decision, not
/// layout, which is why it is tested here rather than excluded with the view around it.
@Suite("How a row is drawn")
struct QuickPanelRowAppearanceTests {
    @Test("the ring goes on the row the presenter selected, and only that one")
    func ringFollowsSelection() {
        let selected = row(isSelected: true)

        #expect(QuickPanelRowAppearance.of(selected, hovered: nil, hasSelection: true).isSelected)
        #expect(!QuickPanelRowAppearance.of(row(), hovered: nil, hasSelection: true).isSelected)
    }

    /// The ring is the answer to "what will Return do". A hovered row that filled as
    /// brightly as the ringed one would make the pointer look like the answer instead.
    @Test("a hovered row is dimmed while the ring is somewhere else")
    func hoverYieldsToTheRing() {
        let hovered = row()
        let appearance = QuickPanelRowAppearance.of(
            hovered, hovered: hovered.id, hasSelection: true)

        #expect(appearance.isFilled)
        #expect(appearance.isSubdued)
        #expect(!appearance.isSelected)
    }

    @Test("pointing at the ringed row fills it once, and does not dim it")
    func selectionBeatsHoverOnTheSameRow() {
        let both = row(isSelected: true)
        let appearance = QuickPanelRowAppearance.of(both, hovered: both.id, hasSelection: true)

        #expect(appearance.isFilled)
        #expect(!appearance.isSubdued, "it is the answer, not a competitor to it")
    }

    /// Nothing to be dimmed against.
    @Test("with no ring anywhere, a hovered row is not dimmed")
    func nothingToYieldTo() {
        let hovered = row()

        #expect(
            !QuickPanelRowAppearance.of(hovered, hovered: hovered.id, hasSelection: false)
                .isSubdued)
    }

    @Test("buttons replace the timestamp on the ringed row and the hovered one")
    func actionsAppearWhereTheyCanBeUsed() {
        let plain = row()
        let selected = row(isSelected: true)

        #expect(QuickPanelRowAppearance.of(selected, hovered: nil, hasSelection: true).showsActions)
        #expect(
            QuickPanelRowAppearance.of(plain, hovered: plain.id, hasSelection: false)
                .showsActions)
        #expect(!QuickPanelRowAppearance.of(plain, hovered: nil, hasSelection: false).showsActions)
    }
}

/// A masked row exists because somebody may be looking over the user's shoulder — or
/// watching a shared screen. A screen reader announcing the token out loud defeats it in
/// the room the masking was for.
@Suite("What a row reads as out loud")
struct QuickPanelSpeechTests {
    @Test("a masked row never has its text in the spoken label")
    func maskedRowsSayNothing() {
        let secret = row("••••••••••••", kind: .secret, isMasked: true)

        let spoken = QuickPanelSpeech.label(for: secret)

        #expect(spoken.contains("hidden"))
        #expect(!spoken.contains("•"), "not even the bullets, which say how long it is")
    }

    /// The presenter masks before the panel ever sees the row, so this is belt and
    /// braces — and it is the brace that would still hold if a future presenter stopped.
    @Test("a masked row would stay silent even if the summary still held the secret")
    func maskingIsNotTrustedToThePresenter() {
        let leaky = row("sk-live-abcdef123456", kind: .secret, isMasked: true)

        #expect(!QuickPanelSpeech.label(for: leaky).contains("sk-live"))
    }

    @Test("an ordinary row reads its kind, its alias, its text and its age")
    func ordinaryRowsReadInFull() {
        let clip = row("the second thing", alias: "/second")

        let spoken = QuickPanelSpeech.label(for: clip)

        #expect(spoken == "Text, /second, the second thing, 2 minutes ago")
    }

    @Test("every kind has a word, so no row is announced as nothing")
    func everyKindSpeaks() {
        for kind in ClipKind.allCases {
            #expect(!QuickPanelSpeech.noun(for: kind).isEmpty)
        }
    }

    /// The two nobody may paste by accident.
    @Test("code and credentials are the kinds the eye is meant to find first")
    func tilesMarkTheDangerousOnes() {
        #expect(QuickPanelSpeech.hasTile(.code))
        #expect(QuickPanelSpeech.hasTile(.secret))
        for kind in [ClipKind.text, .link, .colour, .image] {
            #expect(!QuickPanelSpeech.hasTile(kind))
        }
    }
}

/// The list is drawn as runs — one unnamed run while browsing, one per heading while
/// searching — and a row's identity has to name the run as well as the clip.
///
/// Tested because the alternative was invisible: with the clip's id alone, SwiftUI took
/// a row moving from the flat list into a heading as the same view and left its drawing
/// untouched, so after a search the row Return would paste was drawn as though it were
/// not selected. Nothing failed; the panel just quietly stopped saying what Return meant.
@MainActor
@Suite("How the list is cut into runs")
struct QuickPanelSectionTests {
    private func row(_ text: String) -> PanelRow {
        PanelRow(
            id: UUID(), summary: text, kind: .text, symbolName: "doc", when: "just now",
            alias: nil, category: nil, isPinned: false, isMasked: false, isSelected: false,
            matched: nil, isMonospaced: false, actions: [])
    }

    @Test("a row's key names the run it is drawn in as well as the clip")
    func keysIncludeTheRun() {
        let clip = row("a clip")
        let browsing = QuickPanelSection(id: "all", title: nil, rows: [clip], more: 0)
        let searching = QuickPanelSection(id: "content", title: "Contents", rows: [clip], more: 0)

        #expect(browsing.key(for: clip) != searching.key(for: clip))
        #expect(browsing.key(for: clip).contains(clip.id.uuidString))
    }

    /// Two clips in the same run must not collide, or one of them would inherit the
    /// other's drawing.
    @Test("two rows in one run keep separate keys")
    func rowsInARunAreDistinct() {
        let section = QuickPanelSection(
            id: "all", title: nil, rows: [row("first"), row("second")], more: 0)

        #expect(section.key(for: section.rows[0]) != section.key(for: section.rows[1]))
    }
}
