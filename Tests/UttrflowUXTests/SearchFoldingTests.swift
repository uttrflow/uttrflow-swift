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

    @Test("text with nothing to fold is not copied")
    func plainTextIsLeftAlone() {
        #expect(SearchFolding.folded("plain words here") == nil)
        #expect(SearchFolding.folded("a\u{2013}b") == "a-b")
    }
}
