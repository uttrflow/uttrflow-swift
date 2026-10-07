import Testing

@testable import UttrflowCore

@Suite("WordTokens")
struct WordTokensTests {
    @Test func displayKeepsPunctuationOnTheWord() {
        #expect(
            WordTokens.words("  don't stop, U.S.  team ", .display) == ["don't", "stop,", "U.S.", "team"])
    }

    @Test func comparisonCutsOnEveryMark() {
        #expect(
            WordTokens.words("don\u{2019}t well-known 1,000", .comparison) == [
                "don", "t", "well", "known", "1", "000",
            ])
    }

    @Test func eachTokenRangeCoversItsTextInTheSource() {
        let text = "  and/or  मेरा नाम."
        for profile in [WordTokens.Profile.display, .comparison] {
            for token in WordTokens.tokens(text, profile) { #expect(String(text[token.range]) == token.text) }
        }
    }

    @Test func aSubstringYieldsRangesInItsBaseString() {
        let text = "first line\nsecond word"
        let line = text.split(separator: "\n")[1]
        let tokens = WordTokens.tokens(line, .display)
        #expect(tokens.map { String(text[$0.range]) } == ["second", "word"])
    }

    @Test func blankTextHasNoWords() {
        #expect(WordTokens.tokens(" \t\n", .display).isEmpty)
        #expect(WordTokens.tokens("...", .comparison).isEmpty)
    }
}
