// Tests for how a quick panel row is drawn, spoken and keyed.

import Foundation
import UttrflowClipboard
import UttrflowUX
import Testing

@testable import Uttrflow

private func row(
    _ text: String = "a clip", kind: ClipKind = .text, isSelected: Bool = false,
    isMasked: Bool = false, alias: String? = nil, isPinned: Bool = false,
    measurements: String? = nil, checklist: String? = nil, language: String? = nil,
    category: String? = nil, containsDisplayHazards: Bool = false
) -> PanelRow {
    PanelRow(
        id: UUID(), summary: text, kind: kind, symbolName: "doc", when: "2 minutes ago",
        alias: alias, category: category, isPinned: isPinned, isMasked: isMasked,
        isSelected: isSelected, matched: nil, measurements: measurements, checklist: checklist,
        language: language, isMonospaced: false,
        containsDisplayHazards: containsDisplayHazards, actions: [])
}

/// Hover is the one thing the presentation cannot know, so the rule is a decision tested here.
@Suite("How a row is drawn")
struct QuickPanelRowAppearanceTests {
    @Test("the ring goes on the row the presenter selected, and only that one")
    func ringFollowsSelection() {
        let selected = row(isSelected: true)

        #expect(QuickPanelRowAppearance.of(selected, hovered: nil, hasSelection: true).isSelected)
        #expect(!QuickPanelRowAppearance.of(row(), hovered: nil, hasSelection: true).isSelected)
    }

    /// The ring answers "what will Return do"; a bright hovered row would make the pointer look like it.
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

/// A masked row exists because somebody may be watching; a screen reader must not defeat it.
@Suite("What a row reads as out loud")
struct QuickPanelSpeechTests {
    @Test("a masked row never has its text in the spoken label")
    func maskedRowsSayNothing() {
        let secret = row("••••••••••••", kind: .secret, isMasked: true)

        let spoken = QuickPanelSpeech.label(for: secret)

        #expect(spoken.contains("hidden"))
        #expect(!spoken.contains("•"), "not even the bullets, which say how long it is")
    }

    /// The presenter masks before the panel sees the row; this is the brace that holds if it stops.
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

    @Test("a pinned picture reads its measurements and collection")
    func pinnedPicturesReadTheirDetails() {
        let picture = row(
            "", kind: .image, isPinned: true, measurements: "2880 × 1800 · 1 MB",
            category: "Receipts")

        #expect(
            QuickPanelSpeech.label(for: picture)
                == "Image, Pinned, 2880 × 1800 · 1 MB, Collection Receipts, 2 minutes ago")
    }

    @Test("a missing picture reads the reason its file cannot be opened")
    func missingPicturesReadTheirMeasurements() {
        let picture = row("", kind: .image, measurements: "The picture is no longer on this Mac")

        #expect(QuickPanelSpeech.label(for: picture).contains("The picture is no longer on this Mac"))
    }

    @Test("a note reads checklist progress")
    func notesReadChecklistProgress() {
        let note = row("Shopping list", checklist: "2 of 5")

        #expect(QuickPanelSpeech.label(for: note).contains("2 of 5"))
    }

    @Test("code reads its language")
    func codeReadsItsLanguage() {
        let code = row("let value = 1", kind: .code, language: "swift")

        #expect(QuickPanelSpeech.label(for: code).contains("swift code"))
    }

    @Test("a row with hidden characters announces the warning")
    func hazardousRowsAnnounceWarning() {
        let hazardous = row("file⟦U+202E RIGHT-TO-LEFT OVERRIDE⟧name", containsDisplayHazards: true)

        #expect(QuickPanelSpeech.label(for: hazardous).contains("contains invisible or control characters"))
    }

    @Test("a masked row omits checklist and language details")
    func maskedRowsOmitSensitiveDetails() {
        let secret = row(
            "sk-live-secret", kind: .secret, isMasked: true, checklist: "2 of 5",
            language: "swift")

        let spoken = QuickPanelSpeech.label(for: secret)

        #expect(spoken.contains("hidden"))
        #expect(!spoken.contains("2 of 5"))
        #expect(!spoken.contains("swift"))
        #expect(!spoken.contains("sk-live-secret"))
    }

    @Test("an arriving copy's refreshed age is spoken to VoiceOver")
    func refreshedAgeIsSpoken() {
        let openedAt = Date(timeIntervalSince1970: 1_000_000)
        let copiedAt = openedAt.addingTimeInterval(90)
        let refreshedAt = copiedAt.addingTimeInterval(1)
        let clip = Clip(text: "just copied", kind: .text, copiedAt: copiedAt)
        var snapshot = PanelSnapshot(clips: [], now: openedAt, locale: Locale(identifier: "en_US"))
        snapshot.install([clip], missingImages: [], formattableLanguages: [], now: refreshedAt)

        let row = PanelPresenter.present(snapshot).rows[0]
        let spoken = QuickPanelSpeech.label(for: row)

        #expect(spoken.contains(row.when))
        #expect(!spoken.contains("in "))
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

/// A row's identity names the run as well as the clip, or SwiftUI keeps the old drawing after a search.
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
        let browsing = QuickPanelSection(id: "all", title: nil, rows: [clip], moreLine: nil)
        let searching = QuickPanelSection(id: "content", title: "Contents", rows: [clip], moreLine: nil)

        #expect(browsing.key(for: clip) != searching.key(for: clip))
        #expect(browsing.key(for: clip).contains(clip.id.uuidString))
    }

    /// Two clips in the same run must not collide.
    @Test("two rows in one run keep separate keys")
    func rowsInARunAreDistinct() {
        let section = QuickPanelSection(
            id: "all", title: nil, rows: [row("first"), row("second")], moreLine: nil)

        #expect(section.key(for: section.rows[0]) != section.key(for: section.rows[1]))
    }
}
