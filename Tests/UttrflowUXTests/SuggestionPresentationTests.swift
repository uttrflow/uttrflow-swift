import CoreGraphics
import Testing
import UttrflowPredict

@testable import UttrflowUX

/// Increase Contrast on its own, which is one of the two settings that forbid grey text.
private let highContrast = SuggestionAppearance(increasesContrast: true)

/// Reduce Transparency on its own, which is the other.
private let opaque = SuggestionAppearance(reducesTransparency: true)

@Suite("Suggestion presentation")
struct SuggestionPresentationTests {

    // MARK: - The four states

    @Test("A silent suggestion draws nothing at all")
    func silentDrawsNothing() {
        let presentation = SuggestionPresentation(.silent)
        #expect(presentation.style == .hidden)
        #expect(presentation.rows.isEmpty)
        #expect(presentation.accessibilityLabel.isEmpty)
    }

    @Test("A minimised suggestion is one dot and no text")
    func minimisedIsADot() {
        let presentation = SuggestionPresentation(.minimised)
        #expect(presentation.style == .dot)
        #expect(presentation.rows.isEmpty)
        #expect(SuggestionPresentation.dotDiameter == 7)
    }

    @Test("A certain suggestion is grey text with a Tab marker and no mark")
    func certainIsGhostText() {
        let presentation = SuggestionPresentation(.certain("hello@example.com"))
        #expect(presentation.style == .ghost)
        #expect(presentation.rows.count == 1)
        #expect(presentation.rows[0].text == "hello@example.com")
        #expect(presentation.rows[0].isSelected)
        #expect(!presentation.rows[0].showsMark)
        #expect(SuggestionPresentation.ghostOpacity == 0.45)
    }

    @Test("A choice lists the leader first and the alternatives under it")
    func choiceListsTheLeaderFirst() {
        let presentation = SuggestionPresentation(
            .choice(leader: "Sydney", others: ["Sydenham", "Sydney Road"]))
        #expect(presentation.rows.map(\.text) == ["Sydney", "Sydenham", "Sydney Road"])
        #expect(presentation.rows.map(\.isSelected) == [true, false, false])
    }

    @Test("Only the selected row of a choice carries the mark")
    func onlyTheLeaderCarriesTheMark() {
        let presentation = SuggestionPresentation(
            .choice(leader: "Sydney", others: ["Sydenham"]))
        #expect(presentation.rows.map(\.showsMark) == [true, false])
    }

    // MARK: - Nothing worth drawing

    @Test("A suggestion of empty text is drawn as nothing rather than as an empty chip")
    func emptyTextIsHidden() {
        #expect(SuggestionPresentation(.certain("")).style == .hidden)
        #expect(SuggestionPresentation(.certain("   ")).style == .hidden)
    }

    @Test("An empty alternative is dropped rather than listed as a blank row")
    func emptyAlternativesAreDropped() {
        let presentation = SuggestionPresentation(.choice(leader: "Sydney", others: ["", "  "]))
        #expect(presentation.rows.map(\.text) == ["Sydney"])
        #expect(!presentation.rows[0].showsMark)
    }

    @Test("A choice whose leader is empty falls back to its first real alternative")
    func anEmptyLeaderIsDropped() {
        let presentation = SuggestionPresentation(.choice(leader: "", others: ["Sydenham"]))
        #expect(presentation.rows.map(\.text) == ["Sydenham"])
        #expect(presentation.rows[0].isSelected)
    }

    // MARK: - Accessibility

    @Test(
        "Grey text becomes a solid bordered chip where a display setting forbids it",
        arguments: [highContrast, opaque])
    func ghostBecomesAChip(appearance: SuggestionAppearance) {
        #expect(SuggestionPresentation(.certain("Sydney"), appearance: appearance).style == .chip)
        #expect(
            SuggestionPresentation(
                .choice(leader: "Sydney", others: ["Sydenham"]), appearance: appearance
            ).style
                == .chip)
    }

    @Test("Neither setting turns a silent suggestion into a chip")
    func nothingIsStillNothingUnderTheSettings() {
        #expect(SuggestionPresentation(.silent, appearance: highContrast).style == .hidden)
        #expect(SuggestionPresentation(.minimised, appearance: opaque).style == .dot)
    }

    @Test("Reduce Motion is the whole of whether the surface animates")
    func reduceMotionStopsEverythingMoving() {
        #expect(SuggestionPresentation(.certain("Sydney")).animates)
        #expect(
            !SuggestionPresentation(
                .certain("Sydney"), appearance: SuggestionAppearance(reducesMotion: true)
            ).animates)
    }

    @Test("Reduce Motion does not change what is drawn, only whether it moves")
    func reduceMotionLeavesTheStyleAlone() {
        let still = SuggestionPresentation(
            .certain("Sydney"), appearance: SuggestionAppearance(reducesMotion: true))
        #expect(still.style == .ghost)
    }

    @Test("A Mac with nothing turned on reports the standard appearance")
    func standardAppearanceIsNothingTurnedOn() {
        #expect(!SuggestionAppearance.standard.increasesContrast)
        #expect(!SuggestionAppearance.standard.reducesTransparency)
        #expect(!SuggestionAppearance.standard.reducesMotion)
        #expect(!SuggestionAppearance.standard.demandsChip)
        #expect(highContrast.demandsChip)
        #expect(opaque.demandsChip)
    }

    // MARK: - Type

    @Test("The type follows the field it is anchored to")
    func typeFollowsTheField() {
        #expect(SuggestionPresentation(.certain("Sydney"), fieldPointSize: 24).pointSize == 24)
        #expect(SuggestionPresentation(.certain("Sydney"), fieldPointSize: 11).pointSize == 11)
    }

    @Test("A field that will not say what its type is gets the default rather than nothing")
    func typeFallsBackToTheDefault() {
        #expect(
            SuggestionPresentation(.certain("Sydney")).pointSize
                == SuggestionPresentation.defaultPointSize)
        #expect(
            SuggestionPresentation(.certain("Sydney"), fieldPointSize: .nan).pointSize
                == SuggestionPresentation.defaultPointSize)
    }

    @Test("A type size no text is ever set in is clamped rather than followed")
    func absurdTypeIsClamped() {
        let range = SuggestionPresentation.pointSizeRange
        #expect(
            SuggestionPresentation(.certain("Sydney"), fieldPointSize: 2).pointSize
                == range.lowerBound)
        #expect(
            SuggestionPresentation(.certain("Sydney"), fieldPointSize: 900).pointSize
                == range.upperBound)
    }

    // MARK: - VoiceOver

    @Test("A certain suggestion says what it offers and which key takes it")
    func labelForACertainSuggestion() {
        #expect(
            SuggestionPresentation(.certain("Sydney")).accessibilityLabel
                == "Suggestion: Sydney. Tab to accept.")
    }

    @Test("A choice names its alternatives after the leader")
    func labelForAChoice() {
        #expect(
            SuggestionPresentation(.choice(leader: "Sydney", others: ["Sydenham", "Soho"]))
                .accessibilityLabel
                == "Suggestion: Sydney. Tab to accept. Alternatives: Sydenham, Soho.")
    }

    // MARK: - Equality

    @Test("Two presentations of the same suggestion are the same presentation")
    func presentationsCompareByValue() {
        #expect(SuggestionPresentation(.certain("Sydney")) == SuggestionPresentation(.certain("Sydney")))
        #expect(SuggestionPresentation(.certain("Sydney")) != SuggestionPresentation(.certain("Soho")))
        #expect(SuggestionAppearance.standard != highContrast)
    }
}
