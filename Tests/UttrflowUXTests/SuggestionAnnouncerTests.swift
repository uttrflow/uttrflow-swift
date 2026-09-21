// Tests that VoiceOver hears each AI suggestion once, as it appears, with the key that takes it.

import Testing
import UttrflowPredict

@testable import UttrflowUX

@Suite("Suggestion announcer")
struct SuggestionAnnouncerTests {
    @Test("A single completion is announced with its accept key")
    func aCompletionIsAnnounced() {
        var announcer = SuggestionAnnouncer()
        #expect(
            announcer.announcement(for: SuggestionPresentation(.certain("Sydney")))
                == "AI suggestion: Sydney. Tab to accept.")
    }

    @Test("A replacement is announced with how much of the user's typing it takes back")
    func aReplacementIsAnnounced() {
        var announcer = SuggestionAnnouncer()
        #expect(
            announcer.announcement(for: SuggestionPresentation(.certain("git commit -m"), typed: "gti c"))
                == "AI suggestion: git commit -m. Tab to accept, replacing 4 characters.")
    }

    @Test("A list is announced with its alternatives")
    func aListIsAnnounced() {
        var announcer = SuggestionAnnouncer()
        #expect(
            announcer.announcement(
                for: SuggestionPresentation(.choice(leader: "Sydney", others: ["Sydenham", "Soho"])))
                == "AI suggestion: Sydney. Tab to accept. Alternatives: Sydenham, Soho.")
    }

    @Test("The field's own accept key is the one announced")
    func theFieldsAcceptKeyIsAnnounced() {
        var announcer = SuggestionAnnouncer()
        #expect(
            announcer.announcement(
                for: SuggestionPresentation(.certain("ls -l"), typed: "ls ", acceptKey: .rightArrow))
                == "AI suggestion: ls -l. Right Arrow to accept.")
    }

    @Test("A redraw of the same offer, or typing into it, is not announced again")
    func aRedrawIsSilent() {
        var announcer = SuggestionAnnouncer()
        #expect(announcer.announcement(for: SuggestionPresentation(.certain("Sydney"))) != nil)
        #expect(announcer.announcement(for: SuggestionPresentation(.certain("Sydney"))) == nil)
        #expect(announcer.announcement(for: SuggestionPresentation(.certain("Sydney"), typed: "Syd")) == nil)
        #expect(
            announcer.announcement(for: SuggestionPresentation(.certain("git commit -m"), typed: "gti c"))
                != nil)
        #expect(
            announcer.announcement(for: SuggestionPresentation(.certain("git commit -m"), typed: "gti co"))
                == nil)
    }

    @Test("A different offer is announced")
    func aNewOfferIsAnnounced() {
        var announcer = SuggestionAnnouncer()
        _ = announcer.announcement(for: SuggestionPresentation(.certain("Sydney")))
        #expect(
            announcer.announcement(for: SuggestionPresentation(.certain("Soho")))
                == "AI suggestion: Soho. Tab to accept.")
    }

    @Test("Moving the highlight announces the row Tab now takes")
    func movingTheHighlightIsAnnounced() {
        var announcer = SuggestionAnnouncer()
        let choice = Suggestion.choice(leader: "Sydney", others: ["Sydenham", "Soho"])
        _ = announcer.announcement(for: SuggestionPresentation(choice))
        #expect(
            announcer.announcement(
                for: SuggestionPresentation(choice, selection: SuggestionSelection(index: 2, hasMoved: true)))
                == "AI suggestion: Soho. Tab to accept. Alternatives: Sydney, Sydenham.")
    }

    @Test("Nothing, or the dot left after Escape, is never announced and lets the next offer be heard")
    func nothingIsSilentAndResets() {
        var announcer = SuggestionAnnouncer()
        _ = announcer.announcement(for: SuggestionPresentation(.certain("Sydney")))
        #expect(announcer.announcement(for: SuggestionPresentation(.minimised)) == nil)
        #expect(announcer.announcement(for: SuggestionPresentation(.certain("Sydney"))) != nil)
        #expect(announcer.announcement(for: SuggestionPresentation(.silent)) == nil)
        #expect(announcer.announcement(for: SuggestionPresentation(.certain("Sydney"))) != nil)
    }

    @Test("A withdrawn surface lets the same offer be announced when it comes back")
    func withdrawalResets() {
        var announcer = SuggestionAnnouncer()
        _ = announcer.announcement(for: SuggestionPresentation(.certain("Sydney")))
        announcer.surfaceWithdrawn()
        #expect(announcer.announcement(for: SuggestionPresentation(.certain("Sydney"))) != nil)
    }
}
