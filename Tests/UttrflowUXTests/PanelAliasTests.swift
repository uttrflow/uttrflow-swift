// Tests for alias correction, conflicts, and the round trip from saving a name to finding it.
import Foundation
import UttrflowClipboard
import Testing

@testable import UttrflowUX

/// An alias is typed under pressure into somebody else's application and must never fail to match.
@Suite("Correcting an alias as it is typed")
struct PanelAliasCorrectionTests {
    /// The fixed region.
    static let locale = PanelFixture.locale

    @Test(
        "the same name, typed six ways, reduces to one handle",
        arguments: ["pgprod", "/pgprod", "PGProd", "pg prod", "/PG Prod", "  pgprod  "]
    )
    func everySpellingAgrees(typed: String) {
        #expect(PanelAlias.handle(typed, locale: Self.locale) == "pgprod")
    }

    /// An alias saved as "pg prod" must be found by typing "pgprod"; nobody remembers which spelling.
    @Test("whitespace anywhere is removed, not just at the ends")
    func whitespaceGoes() {
        #expect(PanelAlias.handle("pg prod db", locale: Self.locale) == "pgproddb")
        #expect(PanelAlias.handle("\tpg\nprod ", locale: Self.locale) == "pgprod")
    }

    @Test("nukta and accent variants resolve to the same alias")
    func diacriticVariantsAgree() {
        let hindi = PanelFixture.clip("zindagi", alias: "ज़िंदगी")
        let cafe = PanelFixture.clip("coffee", minutesAgo: 1, alias: "Café")

        #expect(
            PanelAlias.propose("जिंदगी", for: UUID(), among: [hindi], locale: Self.locale).takenBy == hindi.id)
        #expect(
            PanelAlias.propose("cafe", for: UUID(), among: [cafe], locale: Self.locale).takenBy == cafe.id)
    }

    @Test("Arabic hamza forms remain distinct aliases")
    func arabicHamzaRemainsSignificant() {
        let clip = PanelFixture.clip("Ahmed", alias: "أحمد")
        let proposal = PanelAlias.propose("احمد", for: UUID(), among: [clip], locale: Self.locale)

        #expect(proposal.takenBy == nil)
        #expect(proposal.isUsable)
    }

    @Test("Latin and Cyrillic lookalikes share a comparison skeleton")
    func cyrillicLookalikeConflicts() {
        let clip = PanelFixture.clip("first", alias: "paypal")
        let proposal = PanelAlias.propose("раураl", for: UUID(), among: [clip], locale: Self.locale)

        #expect(proposal.canCompareUnicodeNames)
        #expect(proposal.takenBy == clip.id)
        #expect(!proposal.isUsable)
    }

    @Test("Greek lookalikes collide with Latin names")
    func greekLookalikeConflicts() {
        let clip = PanelFixture.clip("first", alias: "po")
        let proposal = PanelAlias.propose("ρο", for: UUID(), among: [clip], locale: Self.locale)

        #expect(proposal.takenBy == clip.id)
    }

    @Test("ASCII names that share a Unicode confusable skeleton remain distinct")
    func asciiConfusableNamesRemainDistinct() {
        for (existing, typed) in [("m1", "ml"), ("a1", "al"), ("rn", "m")] {
            let clip = PanelFixture.clip("first", alias: existing)
            let proposal = PanelAlias.propose(typed, for: UUID(), among: [clip], locale: Self.locale)

            #expect(proposal.takenBy == nil, "\(existing) and \(typed) are distinct ASCII names")
            #expect(proposal.isUsable)
            #expect(!PanelAlias.matches(existing, typed, locale: Self.locale))
        }
    }

    @Test("mixed Latin and Cyrillic letters are rejected")
    func mixedLookalikeScriptsAreRejected() {
        let proposal = PanelAlias.propose("pаypal", for: UUID(), among: [], locale: Self.locale)

        #expect(proposal.mixesScripts)
        #expect(!proposal.isUsable)
    }

    @Test("Latin names mixed with another alphabet are refused")
    func arabicLettersDoNotMixWithLatin() {
        let proposal = PanelAlias.propose("aم", for: UUID(), among: [], locale: Self.locale)

        #expect(proposal.mixesScripts)
        #expect(!proposal.isUsable)
    }

    @Test(
        "Japanese aliases may combine Han with Hiragana and Katakana",
        arguments: ["日本語ひらがな", "漢字かな", "東京タワー"])
    func japaneseScriptsAreUsable(name: String) {
        let proposal = PanelAlias.propose(name, for: UUID(), among: [], locale: Self.locale)

        #expect(!proposal.mixesScripts)
        #expect(proposal.isUsable)
    }

    @Test("Korean aliases may combine Han and Hangul")
    func koreanScriptsAreUsable() {
        let proposal = PanelAlias.propose("한글漢字", for: UUID(), among: [], locale: Self.locale)

        #expect(!proposal.mixesScripts)
        #expect(proposal.isUsable)
    }

    @Test("Han mixed with Latin remains rejected")
    func hanAndLatinAreRejected() {
        let proposal = PanelAlias.propose("漢字a", for: UUID(), among: [], locale: Self.locale)

        #expect(proposal.mixesScripts)
        #expect(!proposal.isUsable)
    }

    @Test("script extensions keep a character shared by Latin names usable")
    func scriptExtensionsResolveWithLatin() {
        let proposal = PanelAlias.propose("aʼ", for: UUID(), among: [], locale: Self.locale)

        #expect(!proposal.mixesScripts)
        #expect(proposal.isUsable)
    }

    /// The interface prints the slash, so typing it follows instructions and is not a correction.
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

/// The conflict has to name which clip holds the alias, since "taken" without "by what" is a guess.
@Suite("An alias somebody else already has")
struct PanelAliasConflictTests {
    /// The fixed region.
    static let locale = PanelFixture.locale

    /// A clip that holds "pgprod".
    static let existing = PanelFixture.clip("postgres://prod", minutesAgo: 1, alias: "pgprod")
    /// A clip with no alias.
    static let other = PanelFixture.clip("something else", minutesAgo: 2)

    @Test("names the clip that holds it")
    func namesTheHolder() {
        let proposal = PanelAlias.propose(
            "pgprod", for: Self.other.id, among: [Self.existing, Self.other],
            locale: Self.locale)

        #expect(proposal.takenBy == Self.existing.id)
        #expect(!proposal.isUsable)
    }

    /// The conflict is on the handle, not the spelling, or two clips could answer to the same typing.
    @Test("whitespace before a slash cannot bypass a taken alias")
    func whitespaceBeforeSlashConflicts() {
        let proposal = PanelAlias.propose(
            " /PG Prod", for: Self.other.id, among: [Self.existing, Self.other],
            locale: Self.locale)

        #expect(proposal.corrected == "pgprod")
        #expect(proposal.takenBy == Self.existing.id)
        #expect(!proposal.isUsable)
    }

    @Test("a differently spelt version of a taken alias still conflicts")
    func conflictIsOnTheHandle() {
        let proposal = PanelAlias.propose(
            "/PG Prod", for: Self.other.id, among: [Self.existing, Self.other],
            locale: Self.locale)

        #expect(proposal.takenBy == Self.existing.id)
    }

    @Test("a normalized handle is idempotent")
    func normalizationIsIdempotent() {
        let once = PanelAlias.handle(" /PG Prod", locale: Self.locale)
        #expect(PanelAlias.handle(once, locale: Self.locale) == once)
    }

    @Test("a clip does not conflict with itself")
    func noSelfConflict() {
        let proposal = PanelAlias.propose(
            "pgprod", for: Self.existing.id, among: [Self.existing], locale: Self.locale)

        #expect(proposal.takenBy == nil)
        #expect(proposal.isUsable, "re-saving your own alias unchanged must be allowed")
    }
}

/// Creation and matching must reduce the same way, or an alias saves cleanly and then finds nothing.
@Suite("Creating an alias and finding it are the same rule")
struct PanelAliasRoundTripTests {
    /// The fixed region.
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

    /// The slash and spaces are part of how an alias is typed, so every keystroke on the way keeps the clip.
    @Test(
        "a partly typed alias finds its clip with or without the slash",
        arguments: [
            "/p", "/pg", "/pgpro", "pg pr", "pgp", "/PG Pr",
        ])
    func partlyTypedIsFound(typed: String) {
        var aliased = PanelFixture.clip("postgres://example.invalid/main", minutesAgo: 1)
        aliased.alias = "pgprod"
        let panel = PanelFixture.panel([aliased], query: typed)
        #expect(panel.results.rows.map(\.clip.id) == [aliased.id], "“\(typed)” hid the clip")
    }
}
