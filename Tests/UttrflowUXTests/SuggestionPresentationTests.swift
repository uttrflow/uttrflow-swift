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
        #expect(presentation.rows[0].ghost == "hello@example.com")
        #expect(presentation.rows[0].isSelected)
        #expect(!presentation.rows[0].showsMark)
        #expect(SuggestionPresentation.ghostOpacity == 0.45)
    }

    @Test("A choice lists the leader first and the alternatives under it")
    func choiceListsTheLeaderFirst() {
        let presentation = SuggestionPresentation(
            .choice(leader: "Sydney", others: ["Sydenham", "Sydney Road"]))
        #expect(presentation.rows.map(\.ghost) == ["Sydney", "Sydenham", "Sydney Road"])
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
        #expect(presentation.rows.map(\.ghost) == ["Sydney"])
        #expect(!presentation.rows[0].showsMark)
    }

    @Test("A choice whose leader is empty falls back to its first real alternative")
    func anEmptyLeaderIsDropped() {
        let presentation = SuggestionPresentation(.choice(leader: "", others: ["Sydenham"]))
        #expect(presentation.rows.map(\.ghost) == ["Sydenham"])
        #expect(presentation.rows[0].isSelected)
    }

    // MARK: - What is left to type

    @Test("The ghost offers only what is still to come, never a repeat of what is on screen")
    func theGhostIsTheTailAndNotTheWholeCandidate() {
        let presentation = SuggestionPresentation(.certain("git commit"), typed: "git com")
        #expect(presentation.rows.map(\.ghost) == ["mit"])
        #expect(presentation.rows[0].candidate == "git commit")
        #expect(presentation.rows[0].consumed.isEmpty)
        #expect(!presentation.rows[0].isReplacement)
    }

    @Test("A line the user has already finished typing is drawn as nothing")
    func nothingLeftToOfferIsHidden() {
        let presentation = SuggestionPresentation(.certain("git commit"), typed: "git commit")
        #expect(presentation.style == .hidden)
        #expect(presentation.rows.isEmpty)
    }

    @Test("Every alternative is trimmed against what is typed, not only the leader")
    func alternativesAreTrimmedToo() {
        let presentation = SuggestionPresentation(
            .choice(leader: "Sydney", others: ["Sydenham", "Sydney Road"]), typed: "Syd")
        #expect(presentation.rows.map(\.ghost) == ["ney", "enham", "ney Road"])
        #expect(presentation.rows.map(\.candidate) == ["Sydney", "Sydenham", "Sydney Road"])
        #expect(presentation.rows.map(\.isSelected) == [true, false, false])
    }

    @Test("An alternative the user has finished typing leaves the rest of the list alone")
    func aFinishedAlternativeIsDropped() {
        let presentation = SuggestionPresentation(
            .choice(leader: "Sydney", others: ["Sydenham"]), typed: "Sydney")
        #expect(presentation.rows.map(\.candidate) == ["Sydenham"])
        #expect(presentation.rows[0].isSelected)
    }

    // MARK: - What a replacement costs

    @Test("A replacement shows the typed characters Tab consumes as well as what it adds")
    func aReplacementShowsWhatItConsumes() {
        let presentation = SuggestionPresentation(.certain("git commit -m"), typed: "gti c")
        let row = presentation.rows[0]
        #expect(row.consumed == "ti c")
        #expect(row.ghost == "it commit -m")
        #expect(row.isReplacement)
    }

    @Test("An append is marked as costing nothing, so only a replacement draws a strike")
    func anAppendConsumesNothing() {
        let presentation = SuggestionPresentation(.certain("Sydney"), typed: "Syd")
        #expect(!presentation.rows[0].isReplacement)
        #expect(presentation.rows[0].consumed.isEmpty)
    }

    @Test("A rejected alternative carries its own cost rather than the leader's")
    func eachRowCarriesItsOwnCost() {
        let presentation = SuggestionPresentation(
            .choice(leader: "Sydney", others: ["Sydenham"]), typed: "Sydn")
        #expect(presentation.rows.map(\.consumed) == ["", "n"])
        #expect(presentation.rows.map(\.isReplacement) == [false, true])
    }

    // MARK: - Drawing and doing cannot disagree

    @Test(
        "What is drawn on top of what is typed is exactly what acceptance leaves behind",
        arguments: [
            ("git commit", "git com"), ("git commit -m", "gti c"), ("Sydney", ""),
            ("Sydney", "Sydney Roa"), ("🚀 launch now", "🚀 launch"), ("git", "git commit"),
        ])
    func whatIsDrawnAgreesWithWhatAcceptanceDoes(candidate: String, typed: String) throws {
        let presentation = SuggestionPresentation(.certain(candidate), typed: typed)
        let row = try #require(presentation.rows.first)
        #expect(row.edit.applied(to: typed) == candidate)
        #expect(String(typed.dropLast(row.consumed.count)) + row.ghost == candidate)
    }

    @Test("The leader is drawn from the very edit acceptance will apply")
    func theLeaderDrawsTheAcceptedEdit() throws {
        let suggestion = Suggestion.choice(leader: "git commit -m", others: ["git checkout"])
        let presentation = SuggestionPresentation(suggestion, typed: "gti c")
        let row = try #require(presentation.rows.first)
        #expect(row.edit == suggestion.edit(after: "gti c"))
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

    @Test("A replacement says out loud how much of the user's own typing it takes back")
    func labelForAReplacement() {
        #expect(
            SuggestionPresentation(.certain("git commit -m"), typed: "gti c").accessibilityLabel
                == "Suggestion: git commit -m. Tab to accept, replacing 4 characters.")
    }

    @Test("A one-character replacement is counted in the singular")
    func labelForASingleCharacterReplacement() {
        #expect(
            SuggestionPresentation(.certain("git y"), typed: "git x").accessibilityLabel
                == "Suggestion: git y. Tab to accept, replacing 1 character.")
    }

    @Test("VoiceOver hears the whole line on offer, not the part still to be typed")
    func labelNamesTheWholeCandidate() {
        #expect(
            SuggestionPresentation(
                .choice(leader: "Sydney", others: ["Sydenham"]), typed: "Syd"
            ).accessibilityLabel
                == "Suggestion: Sydney. Tab to accept. Alternatives: Sydenham.")
    }

    // MARK: - Equality

    @Test("Two presentations of the same suggestion are the same presentation")
    func presentationsCompareByValue() {
        #expect(SuggestionPresentation(.certain("Sydney")) == SuggestionPresentation(.certain("Sydney")))
        #expect(SuggestionPresentation(.certain("Sydney")) != SuggestionPresentation(.certain("Soho")))
        #expect(SuggestionAppearance.standard != highContrast)
    }
}
