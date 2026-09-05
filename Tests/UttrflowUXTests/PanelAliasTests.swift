import Foundation
import UttrflowClipboard
import Testing

@testable import UttrflowUX

/// F4 — an alias is typed under pressure, into somebody else's application, and must
/// never fail to match. Every correction here exists because some spelling of the same
/// name would otherwise find nothing.
@Suite("Correcting an alias as it is typed")
struct PanelAliasCorrectionTests {
    static let locale = PanelFixture.locale

    @Test(
        "the same name, typed six ways, reduces to one handle",
        arguments: ["pgprod", "/pgprod", "PGProd", "pg prod", "/PG Prod", "  pgprod  "]
    )
    func everySpellingAgrees(typed: String) {
        #expect(PanelAlias.handle(typed, locale: Self.locale) == "pgprod")
    }

    /// The reduction that was missing. An alias saved as "pg prod" could not be found by
    /// typing "pgprod", and months later nobody remembers which spelling they used.
    @Test("whitespace anywhere is removed, not just at the ends")
    func whitespaceGoes() {
        #expect(PanelAlias.handle("pg prod db", locale: Self.locale) == "pgproddb")
        #expect(PanelAlias.handle("\tpg\nprod ", locale: Self.locale) == "pgprod")
    }

    /// The interface prints the slash, so typing it is following instructions rather than
    /// making a mistake, and being told it was corrected would be noise.
    @Test("dropping the convention's slash is not reported as a correction")
    func theSlashIsNotACorrection() {
        let proposal = PanelAlias.propose(
            "/pgprod", for: UUID(), among: [], locale: Self.locale)

        #expect(proposal.corrected == "pgprod")
        #expect(!proposal.wasCorrected)
    }

    @Test("a space is reported, because the user should know what was stored")
    func aSpaceIsACorrection() {
        let proposal = PanelAlias.propose(
            "pg prod", for: UUID(), among: [], locale: Self.locale)

        #expect(proposal.corrected == "pgprod")
        #expect(proposal.wasCorrected)
        #expect(proposal.isUsable, "corrected, not rejected")
    }

    @Test("an empty alias is nothing to save, not a conflict")
    func emptyIsNotAConflict() {
        let proposal = PanelAlias.propose("   ", for: UUID(), among: [], locale: Self.locale)

        #expect(proposal.corrected.isEmpty)
        #expect(proposal.takenBy == nil)
        #expect(!proposal.isUsable)
    }
}

/// F3 — the conflict has to name which clip holds the alias, because "taken" without
/// "by what" leaves the user guessing at a name they cannot see.
@Suite("An alias somebody else already has")
struct PanelAliasConflictTests {
    static let locale = PanelFixture.locale

    static let existing = PanelFixture.clip("postgres://prod", minutesAgo: 1, alias: "pgprod")
    static let other = PanelFixture.clip("something else", minutesAgo: 2)

    @Test("names the clip that holds it")
    func namesTheHolder() {
        let proposal = PanelAlias.propose(
            "pgprod", for: Self.other.id, among: [Self.existing, Self.other],
            locale: Self.locale)

        #expect(proposal.takenBy == Self.existing.id)
        #expect(!proposal.isUsable)
    }

    /// The conflict is on the handle, not the spelling — otherwise two clips could hold
    /// "pg prod" and "pgprod" and both would answer to the same typing.
    @Test("a differently spelt version of a taken alias still conflicts")
    func conflictIsOnTheHandle() {
        let proposal = PanelAlias.propose(
            "/PG Prod", for: Self.other.id, among: [Self.existing, Self.other],
            locale: Self.locale)

        #expect(proposal.takenBy == Self.existing.id)
    }

    @Test("a clip does not conflict with itself")
    func noSelfConflict() {
        let proposal = PanelAlias.propose(
            "pgprod", for: Self.existing.id, among: [Self.existing], locale: Self.locale)

        #expect(proposal.takenBy == nil)
        #expect(proposal.isUsable, "re-saving your own alias unchanged must be allowed")
    }
}

/// The guarantee the split into two functions could break. Creation reduces one way and
/// matching the other, and the day they part is the day an alias saves cleanly and then
/// finds nothing.
@Suite("Creating an alias and finding it are the same rule")
struct PanelAliasRoundTripTests {
    static let locale = PanelFixture.locale

    @Test(
        "whatever is saved is found by typing any spelling of it",
        arguments: ["pg prod", "/PGProd", "  pgprod", "Pg Prod  "]
    )
    func savedIsFound(typed: String) {
        let clip = PanelFixture.clip("postgres://prod", minutesAgo: 1)
        let saved = PanelAlias.propose(typed, for: clip.id, among: [], locale: Self.locale)

        var aliased = clip
        aliased.alias = saved.corrected

        // Every spelling of the same name must resolve to this clip on Return.
        for spelling in ["pgprod", "/pgprod", "PG PROD", "pg prod"] {
            let panel = PanelFixture.panel([aliased], query: spelling)
            #expect(
                panel.results.rows.first?.clip.id == aliased.id,
                "“\(spelling)” did not find an alias saved from “\(typed)”")
            #expect(panel.results.rows.first?.isExactAlias == true)
        }
    }
}
