// Tests that search folds typographic punctuation and whitespace on both sides (#900).
import Foundation
import Testing
import UttrflowClipboard

@testable import UttrflowUX

@Suite("Search folds what a keyboard cannot type")
struct SearchFoldingTests {
    @Test(
        "a clip is found by what the person typed",
        arguments: [
            ("don\u{2019}t forget the keys", "don't"),
            ("don't forget the keys", "don\u{2019}t"),
            ("\u{201C}quoted\u{201D} text", "\"quoted\""),
            ("well\u{2014}known", "well-known"),
            ("deploy\nstaging now", "deploy staging"),
            ("deploy  staging", "deploy staging"),
            ("price 10\u{00A0}km away", "10 km"),
        ])
    func found(clip: String, query: String) {
        #expect(clip.contains(query, ignoringCaseAndAccentsIn: Locale(identifier: "en_US")))
        let panel = PanelFixture.panel([PanelFixture.clip(clip, minutesAgo: 1)], query: query)
        #expect(!PanelPresenter.present(panel).groups.isEmpty)
    }

    @Test("search ignores zero-width characters in both the clip and the query")
    func ignoresZeroWidthCharacters() {
        let panel = PanelFixture.panel(
            [PanelFixture.clip("pa\u{200B}ypal")], query: "pay\u{200B}pal")

        #expect("pa\u{200B}ypal".contains("paypal", ignoringCaseAndAccentsIn: PanelFixture.locale))
        #expect("paypal".contains("pa\u{200B}ypal", ignoringCaseAndAccentsIn: PanelFixture.locale))
        #expect(PanelPresenter.present(panel).rows.map(\.summary) == ["pa⟦U+200B ZERO WIDTH SPACE⟧ypal"])
    }

    @Test("a query containing only zero-width characters becomes blank")
    func zeroWidthOnlyQueryIsBlank() {
        #expect(SearchQuery.needle(in: "\u{200B}\u{2060}").isEmpty)
        #expect(PanelPresenter.present(PanelFixture.panel(query: "\u{200B}")).rows.count == 3)
    }

    @Test("control whitespace keeps matching as a space in clip text and query")
    func controlWhitespaceMatchesAsSpace() {
        let panel = PanelFixture.panel(
            [PanelFixture.clip("deploy\u{000B}staging")], query: "deploy\u{000B}staging")

        #expect(PanelPresenter.present(panel).rows.count == 1)
    }

    /// The marks folding straightens, which are rewritten without being whitespace.
    static let straightened: Set<Unicode.Scalar> = [
        "\u{2018}", "\u{2019}", "\u{201B}", "\u{2032}", "\u{201C}", "\u{201D}", "\u{201E}",
        "\u{2033}", "\u{2010}", "\u{2011}", "\u{2012}", "\u{2013}", "\u{2014}", "\u{2212}",
    ]

    @Test("exactly the scalars Unicode calls whitespace are folded as whitespace")
    func whitespaceIsUnicodes() {
        for value in 0...0xFFFF {
            guard let scalar = Unicode.Scalar(UInt32(value)), !Self.straightened.contains(scalar)
            else { continue }

            // A run of two is what folding collapses, so one scalar decides the answer.
            #expect(
                (SearchFolding.folded("\(scalar)\(scalar)x") == " x")
                    == scalar.properties.isWhitespace,
                "U+\(String(value, radix: 16, uppercase: true))")
        }
    }

    @Test("text with nothing to fold is not copied")
    func plainTextIsLeftAlone() {
        #expect(SearchFolding.folded("plain words here") == nil)
        #expect(SearchFolding.folded("a\u{2013}b") == "a-b")
    }
}
