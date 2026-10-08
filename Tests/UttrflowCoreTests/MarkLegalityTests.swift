import Testing
import UttrflowCore

@Suite("Mark legality")
struct MarkLegalityTests {
    @Test(
        "a word that leaves its clause open takes no stop, question or colon",
        arguments: ["the", "and", "of", "my", "because", "Dr.", "e.g."])
    func open(token: String) {
        for mark in [MarkLegality.Mark.stop, .question, .exclamation, .colon] {
            #expect(MarkLegality.verdict(mark, after: token) == .illegal)
        }
    }

    @Test(
        "a word that can close a clause takes a stop or a comma",
        arguments: ["done", "Friday", "42", "etc.", "(today)", "\u{201C}yes\u{201D}"])
    func closed(token: String) {
        #expect(MarkLegality.verdict(.stop, after: token) == .legal)
        #expect(MarkLegality.verdict(.comma, after: token) == .legal)
    }

    @Test("each token is read into the state its row is keyed on")
    func states() {
        #expect(MarkLegality.state(of: "the") == .leadsOn)
        #expect(MarkLegality.state(of: "Mr.") == .leadingAbbreviation)
        #expect(MarkLegality.state(of: "p.m.") == .abbreviation)
        #expect(MarkLegality.state(of: "3.5") == .number)
        #expect(MarkLegality.state(of: "example.com") == .technical)
        #expect(MarkLegality.state(of: "(soon)") == .closer)
        #expect(MarkLegality.state(of: "--") == .symbol)
        #expect(MarkLegality.state(of: "report") == .word)
    }

    @Test("a pair the table has no row for is unknown, so the existing mark stays")
    func unknown() {
        #expect(MarkLegality.verdict(.stop, after: "example.com") == .unknown)
        #expect(MarkLegality.verdict(.comma, after: "&") == .unknown)
        #expect(MarkLegality.verdict(.colon, after: "note") == .unknown)
        #expect(MarkLegality.verdict(.comma, after: "the") == .unknown)
    }

    @Test("a sentence is complete when its last word can end it and a verb was said")
    func completeness() {
        let words = { (text: String) in text.split(separator: " ").map(String.init) }
        #expect(MarkLegality.sentenceCompleteness(words("we sent the report")) == .legal)
        #expect(MarkLegality.sentenceCompleteness(words("we sent the")) == .illegal)
        #expect(MarkLegality.sentenceCompleteness(words("i will call you because")) == .illegal)
        #expect(MarkLegality.sentenceCompleteness(words("the blue report")) == .unknown)
        #expect(MarkLegality.sentenceCompleteness([]) == .unknown)
    }
}
