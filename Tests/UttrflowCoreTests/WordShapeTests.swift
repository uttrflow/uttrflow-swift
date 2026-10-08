import Testing

@testable import UttrflowCore

@Suite("WordShape")
struct WordShapeTests {
    @Test(
        "casing a word keeps internal capitals and still cases ordinary words",
        arguments: [
            ("iPhone", "iPhone", "iPhone"), ("eBay", "eBay", "eBay"),
            ("macOS", "macOS", "macOS"), ("iOS", "iOS", "iOS"),
            ("WiFi", "WiFi", "WiFi"), ("YouTube", "YouTube", "YouTube"),
            ("hello", "Hello", "hello"), ("Hello", "Hello", "hello"),
        ]
    )
    func casing(text: String, capitalised: String, lowercased: String) {
        #expect(WordShape.capitalised(text) == capitalised)
        #expect(WordShape.lowercased(text) == lowercased)
    }

    @Test(
        "an ellipsis with no question or exclamation mark trails off",
        arguments: [
            ("...", true), ("\u{2026}", true), ("...\"", true), ("..", false), ("..,", false), (".", false),
            ("...?", false), ("", false),
        ]
    )
    func trailsOff(marks: String, expected: Bool) {
        #expect(WordShape.trailsOff(marks) == expected)
    }

    @Test(
        "settles each run of marks after a word to its one legal form",
        arguments: [
            ("done", "done"), ("done.", "done."), ("done,", "done,"), ("done?", "done?"), ("done!", "done!"),
            ("done..", "done."), ("done...", "done..."), ("done....", "done..."), ("done.....", "done..."),
            ("done\u{2026}", "done\u{2026}"), ("done\u{2026}.", "done\u{2026}"),
            ("done\u{2026}\u{2026}", "done\u{2026}"),
            ("done,.", "done."), ("done.,", "done."), ("done?.", "done?"), ("done!.", "done!"),
            ("done;.", "done."), ("done:.", "done."), ("done,,", "done,"), ("done;,", "done;"),
            ("done:,", "done:"), ("done??", "done?"), ("done!!!", "done!"), ("done?!", "done?!"),
            ("done!?", "done!?"), ("done?!?", "done?!"), ("done...?", "done?"), ("done...,", "done..."),
            ("U.S..", "U.S."), ("etc..", "etc."), ("done.\"", "done.\""), ("done..\".", "done.\"."),
            ("(done),.", "(done)."), (",,", ",,"),
        ]
    )
    func settlingMarks(text: String, expected: String) {
        #expect(WordShape.settlingMarks(text) == expected)
    }

    @Test(
        "recognizes danda and double danda as sentence endings",
        arguments: ["है।", "है॥"])
    func devanagariSentenceEndings(text: String) {
        let shape = WordShape(text)
        #expect(shape.endsSentence)
        #expect(WordShape.finished(text) == text)
    }

    @Test(
        "a closing bracket takes the stop after it, unless the brackets hold the whole sentence",
        arguments: [
            ("days)", "i called him twice (on different", "days)."),
            ("client)", "Send it to the team (not the", "client)."),
            ("appendix)", "Done. (see the", "appendix.)"),
            ("appendix)", "(see the", "appendix.)"),
            ("(appendix)", "", "(appendix.)"),
            ("appendix.)", "(see the", "appendix.)"),
            ("days).", "twice (on different", "days)."),
            ("days)\"", "\"twice (on different", "days).\""),
            ("appendix)\"", "\"(see the", "appendix.)\""),
            ("b))", "x (a (", "b))."),
            ("b))", "(a (", "b.))"),
            ("later)", "Fine.\n(we talk", "later.)"),
        ]
    )
    func finishesAfterABracket(word: String, preceding: String, expected: String) {
        #expect(WordShape.finished(word, after: preceding) == expected)
    }

    @Test(
        "a quoted term mid-sentence takes the stop after its quote; a quotation that is the sentence or a clause takes it inside",
        arguments: [
            ("queue\"", "we call it \"dead letter", "queue\"."),
            ("done\"", "she said \"we are", "done.\""),
            ("done\"", "\"we are", "done.\""),
            ("it\"", "he replied \"ship", "it.\""),
            ("it\"", "I named the branch \"ship", "it\"."),
            ("now\"", "Fine. \"call me", "now.\""),
            ("\"queue\"", "we call it", "\"queue\""),
            ("queue\u{201D}", "we call it \u{201C}dead letter", "queue\u{201D}."),
        ]
    )
    func finishesAfterAQuote(word: String, preceding: String, expected: String) {
        #expect(WordShape.finished(word, after: preceding) == expected)
    }

    @Test("adds a full stop to an unmarked Devanagari sentence")
    func finishesUnmarkedDevanagariSentence() {
        #expect(WordShape.finished("है") == "है.")
    }

    @Test(
        "a sentence cannot end on an article, a conjunction, the copula or a contracted subject",
        arguments: [
            ("the", true), ("And", true), ("is", true), ("let's", true), ("we're", true),
            ("he\u{2019}s", true),
            ("done", false), ("should", false), ("it", false), ("that", false),
        ]
    )
    func leadsOn(word: String, expected: Bool) {
        #expect(FunctionWords.leadsOn(word) == expected)
    }

    @Test(
        "puts a mark on the end of a word, replacing a clause mark already there",
        arguments: [
            ("today", "?", "today?"),
            ("today,", "?", "today?"),
            ("today.", "!", "today!"),
            ("example.com.", "?", "example.com?"),
            ("p.m.", "?", "p.m.?"),
            ("p.m.", ",", "p.m.,"),
            ("p.m.", "!", "p.m.!"),
            ("p.m.", ":", "p.m.:"),
            ("p.m.", ";", "p.m.;"),
            ("p.m.", ".", "p.m."),
            ("done.", "?", "done?"),
            ("today", "\"", "today\""),
            ("today\"", ".", "today\"."),
            ("today", "\u{2014}", "today \u{2014}"),
        ]
    )
    func marked(text: String, mark: String, expected: String) {
        #expect(WordShape.marked(text, with: mark) == expected)
    }

    @Test(
        "folds several marks on in turn, under the same rule",
        arguments: [
            ("today", "?\"", "today?\""),
            ("today,", "?", "today?"),
            // An ellipsis is three clause marks, so it ends as the one mark they collapse to.
            ("today", "...", "today."),
            ("today", "", "today"),
        ]
    )
    func markedWithSeveral(text: String, marks: String, expected: String) {
        #expect(WordShape.marked(text, withAll: marks) == expected)
    }
}
