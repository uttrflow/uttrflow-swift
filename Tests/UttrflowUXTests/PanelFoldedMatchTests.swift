// Tests that excerpts, whole-text rank and exact collections use the same folding as matching.
import Foundation
import Testing
import UttrflowClipboard

@testable import UttrflowUX

@Suite("Folded matches keep their excerpt and rank")
struct PanelFoldedMatchTests {
    let locale = PanelFixture.locale

    @Test("a curly apostrophe past line one is excerpted for a straight query")
    func curlyApostropheExcerpt() throws {
        let excerpt = try #require(
            PanelPresenter.excerpt(of: "Notes\nsecond\nI don\u{2019}t know", around: "don't", locale: locale))
        #expect(excerpt.contains("don\u{2019}t"))
    }

    @Test("a line break past line one is excerpted for a spaced query")
    func lineBreakExcerpt() throws {
        let excerpt = try #require(
            PanelPresenter.excerpt(of: "Notes\nfoo\nbar", around: "foo bar", locale: locale))
        #expect(excerpt.contains("foo"))
        #expect(excerpt.contains("bar"))
    }

    @Test("the folded range maps back to the original text")
    func rangeMapsBack() throws {
        let text = "a  b\u{2014}c don\u{2019}t"
        let found = try #require(text.range(of: "don't", ignoringCaseAndAccentsIn: locale))
        #expect(text[found] == "don\u{2019}t")
        let spaced = try #require(text.range(of: "a b-c", ignoringCaseAndAccentsIn: locale))
        #expect(text[spaced] == "a  b\u{2014}c")
    }

    @Test("a clip that is the query under folding counts as whole")
    func wholeUnderFolding() {
        #expect(PanelSnapshot.isWhole("don't", of: PanelFixture.clip("don\u{2019}t"), locale: locale))
        #expect(PanelSnapshot.isWhole("foo bar", of: PanelFixture.clip("foo\nbar"), locale: locale))
        #expect(!PanelSnapshot.isWhole("don't", of: PanelFixture.clip("don\u{2019}t go"), locale: locale))
    }

    @Test("a collection named the query under folding is exact")
    func exactCollectionUnderFolding() {
        #expect("Tom\u{2019}s".equals("Tom's", ignoringCaseAndAccentsIn: locale))
        #expect("to\ndo".equals("to do", ignoringCaseAndAccentsIn: locale))
        #expect(!"Tom\u{2019}s list".equals("Tom's", ignoringCaseAndAccentsIn: locale))
    }
}
