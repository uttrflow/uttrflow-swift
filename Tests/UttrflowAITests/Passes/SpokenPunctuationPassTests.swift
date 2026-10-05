import Testing
import Foundation
import UttrflowCore

@testable import UttrflowAI

@Suite("SpokenPunctuationPass")
struct SpokenPunctuationPassTests {
    private let sut = SpokenPunctuationPass()

    @Test(
        "turns a mark said by name into the mark on the word before it",
        arguments: [
            ("add milk comma eggs comma and bread", "add milk, eggs, and bread"),
            ("is it ready question mark", "is it ready?"),
            ("ship it full stop", "ship it."),
            ("ship it period", "ship it."),
            ("that is it period", "that is it."),
            ("this is final period", "this is final."),
            ("wow exclamation mark", "wow!"),
            ("wow exclamation point", "wow!"),
            ("two things colon the milk", "two things: the milk"),
            ("milk semicolon eggs", "milk; eggs"),
            ("milk semi colon eggs", "milk; eggs"),
            ("ready. question mark", "ready?"),
            ("milk, comma eggs", "milk, eggs"),
            ("done comma we move on", "done, we move on"),
            ("call me tomorrow comma okay", "call me tomorrow, okay"),
            ("hi john comma how are you question mark", "hi john, how are you?"),
            ("here is the list colon apples and pears", "here is the list: apples and pears"),
            ("note colon bring snacks", "note: bring snacks"),
            ("chai comma aur biscuit", "chai, aur biscuit"),
            ("note colon kal chutti hai", "note: kal chutti hai"),
            ("we discussed colon cancer", "we discussed colon cancer"),
            ("export comma separated values", "export comma separated values"),
            ("we checked dash cam footage", "we checked dash cam footage"),
            ("meet at five colon thirty", "meet at five: 30"),
            ("the build passed period the tests passed period", "the build passed. the tests passed."),
            ("that was amazing exclamation point", "that was amazing!"),
        ]
    )
    func attachesMarks(input: String, expected: String) {
        #expect(cleaned(input, by: sut) == expected)
    }

    @Test(
        "sets off what a lead-in introduces with a colon and keeps the case after it",
        arguments: [
            ("the steps are as follows build the app", "the steps are as follows: build the app"),
            ("the steps are as follows First build", "the steps are as follows: First build"),
            ("the steps are as follows colon build", "the steps are as follows: build"),
            ("the steps are as follows", "the steps are as follows"),
            ("the steps are as follows. build it", "the steps are as follows. build it"),
            ("the steps are first second", "the steps are first second"),
            ("note the build failed", "note the build failed"),
        ]
    )
    func marksLeadIns(input: String, expected: String) {
        #expect(cleaned(input, by: sut) == expected)
    }

    @Test(
        "writes a spoken bracket pair around the words it encloses and leaves an unpaired or named one as words",
        arguments: [
            ("the report open paren draft two close paren is attached", "the report (draft two) is attached"),
            ("bring a jacket open bracket it gets cold close bracket", "bring a jacket [it gets cold]"),
            ("see open parenthesis below close parenthesis", "see (below)"),
            ("it ends open paren soon close paren full stop", "it ends (soon)."),
            ("open paren close paren", "open paren close paren"),
            ("the parentheses are wrong", "the parentheses are wrong"),
            (
                "her letter has an open paren that never closes",
                "her letter has an open paren that never closes"
            ),
            ("a close paren was missing from the note", "a close paren was missing from the note"),
            ("the judges open bracket play on friday", "the judges open bracket play on friday"),
            ("it was a close bracket race", "it was a close bracket race"),
        ]
    )
    func pairsBrackets(input: String, expected: String) {
        #expect(cleaned(input, by: sut) == expected)
    }

    @Test("converts a final spoken period after a noun object")
    func finalSpokenPeriodAfterNounObject() {
        #expect(cleaned("i finished the draft period", by: sut) == "i finished the draft.")
    }

    @Test(
        "keeps supported period compounds at the end without treating every noun as a modifier",
        arguments: [
            ("what is the waiting period", "what is the waiting period"),
            ("the policy has a cooling off period", "the policy has a cooling off period"),
            ("you have a six month period", "you have a six month period"),
            ("over a ten year period", "over a ten year period"),
            ("a two week period", "a two week period"),
            ("the holding period", "the holding period"),
            ("the following period", "the following period"),
            ("one hundred day period", "one hundred day period"),
            ("call the office period", "call the office."),
            ("have a nice day period", "have a nice day."),
            ("it was a long day period", "it was a long day."),
            ("that is all for this week period", "that is all for this week."),
            ("i will be away for a year period", "i will be away for a year."),
            ("the project took a week period", "the project took a week."),
            ("we are done for the day period", "we are done for the day."),
            ("turn the light off period", "turn the light off."),
            ("i took the day off period", "i took the day off."),
        ]
    )
    func finalPeriodCompounds(input: String, expected: String) {
        #expect(cleaned(input, by: sut) == expected)
    }

    @Test(
        "keeps abbreviation full stops when the standard pipeline adds a clause mark",
        arguments: [
            ("Is it 5 p.m. question mark", "Is it 5 p.m.?"),
            ("We left at 5 p.m. comma then ate.", "We left at 5 p.m., then ate."),
            ("Bring apples, pears, etc. exclamation mark", "Bring apples, pears, etc.!"),
            ("Meet at 5 p.m. exclamation mark", "Meet at 5 p.m.!"),
        ]
    )
    func keepsAbbreviationStops(input: String, expected: String) {
        #expect(CleaningPipeline.standard.run(Draft(text: input)).text == expected)
    }

    /// A two-word mark name cannot straddle a sentence end, because the halves were said in different sentences.
    @Test(
        "leaves a mark name whose two words sit in different sentences",
        arguments: [
            "She is full. Stop.",
            "the glass was full. Stop worrying about it",
            "ask the question. Mark it as done",
        ]
    )
    func leavesANameAcrossASentenceEnd(input: String) {
        #expect(cleaned(input, by: sut) == input)
    }

    /// A noun phrase cannot begin in the sentence before, so a determiner there does not make the mark a mention.
    @Test(
        "takes a mark whose only determiner sits in the sentence before",
        arguments: [
            ("hand me a pen. Comma then go", "hand me a pen, then go"),
            ("hand me the red pen. Comma then go", "hand me the red pen, then go"),
            ("this is the plan. Full stop", "this is the plan."),
        ]
    )
    func takesAMarkWhoseDeterminerIsInTheSentenceBefore(input: String, expected: String) {
        #expect(cleaned(input, by: sut) == expected)
    }

    @Test(
        "ends a sentence with a spoken full stop only where the text closes",
        arguments: [
            ("ship it period new line next", "ship it. new line next"),
            ("ship it full stop new paragraph next", "ship it. new paragraph next"),
            ("he said open quote ship it period close quote", "he said \"ship it.\""),
            ("did you finish the trial period question mark", "did you finish the trial period?"),
            ("the trial period comma which ended", "the trial period, which ended"),
        ]
    )
    func fullStopsOnlyWhereTheTextCloses(input: String, expected: String) {
        #expect(cleaned(input, by: sut) == expected)
    }

    @Test("ends a sentence with a spoken full stop before a layout mark already placed")
    func fullStopBeforeLayoutMark() {
        let draft = Draft(words: ["ship", "it", "period", "\n", "next"].map { Draft.Word($0) })
        #expect(sut.apply(draft).text == "ship it.\nnext")
    }

    @Test("wraps the words between open quote and close quote")
    func quotes() {
        #expect(cleaned("he said open quote hello there close quote", by: sut) == "he said \"hello there\"")
    }

    /// "quote" opens a quotation only when "unquote", "end quote" or "close quote" closes it later in the sentence.
    @Test(
        "reads quote with its closing as a quotation and keeps every other quote a word",
        arguments: [
            ("she said quote ready unquote and left", "she said \"ready\" and left"),
            ("she said quote see you at noon end quote", "she said \"see you at noon\""),
            ("he wrote quote done close quote", "he wrote \"done\""),
            ("can you quote me a price", "can you quote me a price"),
            ("the quote was too high", "the quote was too high"),
            ("the so called quote unquote expert", "the so called quote unquote expert"),
            ("call the unquote function", "call the unquote function"),
        ]
    )
    func quoteUnquote(spoken: String, expected: String) {
        #expect(cleaned(spoken, by: sut) == expected)
    }

    @Test(
        "writes open and close parentheses as brackets and keeps a mentioned parenthesis",
        arguments: [
            ("add the flag open parentheses optional close parentheses", "add the flag (optional)"),
            ("add the flag open parenthesis optional close parenthesis", "add the flag (optional)"),
            ("a parenthesis is a curved mark", "a parenthesis is a curved mark"),
        ]
    )
    func parentheses(spoken: String, expected: String) {
        #expect(cleaned(spoken, by: sut) == expected)
    }

    /// A quotation inside a quotation takes the other quote, and each close goes with the quote still open.
    @Test(
        "wraps single and nested quotations to depth two",
        arguments: [
            ("he said open single quote hello close single quote", "he said 'hello'"),
            (
                "she said open quote he told me open quote ship it close quote today close quote",
                "she said \"he told me 'ship it' today\""
            ),
            (
                "she said open quote he wrote open single quote done close single quote close quote",
                "she said \"he wrote 'done'\""
            ),
            (
                "she said open quote he said open quote ship it period close quote close quote",
                "she said \"he said 'ship it.'\""
            ),
            (
                "open quote one close quote and open quote two close quote",
                "\"one\" and \"two\""
            ),
        ]
    )
    func nestedQuotations(input: String, expected: String) {
        #expect(cleaned(input, by: sut) == expected)
    }

    /// The first word inside a quotation keeps its spoken case; the pass never recases it.
    @Test(
        "keeps the case of the first quoted word",
        arguments: [
            ("he said open quote hello there close quote", "he said \"hello there\""),
            ("he said open quote Hello there close quote", "he said \"Hello there\""),
            ("she said open single quote iPhone close single quote", "she said 'iPhone'"),
        ]
    )
    func quotedCase(input: String, expected: String) {
        #expect(cleaned(input, by: sut) == expected)
    }

    @Test("joins the words around a hyphen, and spaces a dash")
    func hyphenAndDash() {
        #expect(cleaned("a well hyphen known bug", by: sut) == "a well-known bug")
        #expect(cleaned("we went home dash it was late", by: sut) == "we went home \u{2014} it was late")
    }

    /// "Dash" and "hyphen" are verbs too, and the particle after them is what says which was meant.
    @Test(
        "leaves dash and hyphen as words when a particle follows them",
        arguments: [
            "we should dash off a quick note to the client",
            "she had to dash out before the standup",
            "let me dash over to the other building",
            "hyphen in the name is fine",
        ]
    )
    func leavesTheVerb(input: String) {
        #expect(cleaned(input, by: sut) == input)
    }

    /// An opening quote goes on the word after it, so a dictation may perfectly well begin with one.
    @Test(
        "wraps a quotation that opens the text",
        arguments: [
            (
                "open quote the build is green close quote that is what he said",
                "\"the build is green\" that is what he said"
            ),
            ("open quote ship it close quote", "\"ship it\""),
        ]
    )
    func wrapsAQuotationThatOpensTheText(input: String, expected: String) {
        #expect(cleaned(input, by: sut) == expected)
    }

    /// The opening half still needs a word to go on, and the closing half still needs one before it.
    @Test(
        "leaves a half quotation with nothing to attach to as words",
        arguments: ["open quote", "close quote he said"])
    func leavesAHalfQuotation(input: String) {
        #expect(cleaned(input, by: sut) == input)
    }

    @Test(
        "leaves a mark that is mentioned rather than used",
        arguments: [
            "put a comma after the greeting",
            "the period of time",
            "add a period",
            "with no comma",
            "comma",
            "comma first",
            "a long period of time",
            "this period was hard",
            "these comma separated values are easy to read",
            "those question mark icons are confusing",
            "which comma should I use here",
            "whose comma is this",
            "both commas are wrong here",
            "either comma works",
            "neither comma belongs here",
            "all commas look the same",
            "insert a colon",
            "say open quote",
            "a well hyphen",
            "the Dash app crashed",
            "a dash of salt",
        ]
    )
    func leavesMentions(input: String) {
        #expect(cleaned(input, by: sut) == input)
    }

    @Test("keeps words that mention mark names literally")
    func keepsLiteralVocabulary() {
        for input in [
            "the colon is an organ", "the period of time was long", "a new line of products",
            "question mark over his future", "a comma splice",
        ] {
            #expect(cleaned(input, by: sut) == input)
        }
    }

    /// "Period", "comma" and "dash" are nouns too, and a modifier hides the determiner that says so.
    @Test(
        "leaves the noun a determiner opens even when a modifier stands between them",
        arguments: [
            "during the trial period", "that trial period", "this period of time",
            "I love the Victorian period",
            "the 100 metre dash was close", "a short grace period follows",
            "a grace period applies", "the notice period expires tomorrow",
            "the grace period", "notice period",
            "a waiting period applies", "the time period was short",
            "a cooling off period applies", "the six month period ended",
        ]
    )
    func leavesTheHeadOfANounPhrase(input: String) {
        #expect(cleaned(input, by: sut) == input)
    }

    @Test("keeps a noun period while converting a separately used period")
    func keepsNounPeriodAndConvertsUsedPeriod() {
        #expect(cleaned("the grace period, ship it period", by: sut) == "the grace period, ship it.")
    }

    /// The lookback stops at a mark name, so the phrase before one does not reach past it.
    @Test(
        "still converts a mark the speaker used, determiner or not",
        arguments: [
            ("ship it period", "ship it."),
            ("milk comma eggs comma and bread", "milk, eggs, and bread"),
            ("did you finish the trial period question mark", "did you finish the trial period?"),
        ]
    )
    func convertsWhatWasUsed(input: String, expected: String) {
        #expect(cleaned(input, by: sut) == expected)
    }

    /// Issue 237: "comma", "colon" and "dash" are nouns that modify the word after them, so a mid-sentence one needs evidence.
    @Test(
        "leaves an everyday mark name with no evidence that it stands at a seam",
        arguments: [
            "suffering from colon cancer", "he has colon trouble again",
            "screened for colon cancer last year", "write comma separated values please",
            "reduce comma usage in prose", "sprint dash training starts monday",
            "we checked dash cam footage", "he keeps writing comma splices",
            "the main road is closed", "turn left at the main gate",
            "done comma next", "two things colon milk", "milk comma eggs and bread",
        ]
    )
    func leavesAnOrdinaryNameWithoutEvidence(input: String) {
        #expect(cleaned(input, by: sut) == input)
    }

    @Test(
        "takes an everyday mark name where the text closes, a mark precedes it, a small word follows, or it is said again",
        arguments: [
            ("the steps are as follows colon", "the steps are as follows:"),
            ("hi team comma", "hi team,"),
            ("hi team comma new line thanks", "hi team, new line thanks"),
            ("milk, comma eggs", "milk, eggs"),
            ("however comma the build passed", "however, the build passed"),
            ("the reason is simple colon we ran out", "the reason is simple: we ran out"),
            ("we left early dash it was raining", "we left early \u{2014} it was raining"),
            ("chai comma aur biscuit", "chai, aur biscuit"),
            ("note colon kal chutti hai", "note: kal chutti hai"),
            ("chai dash phir biscuit", "chai \u{2014} phir biscuit"),
            ("apples comma pears comma plums", "apples, pears, plums"),
            ("red comma green. blue comma white", "red comma green. blue comma white"),
            ("we have colon trouble. the colon comma and more", "we have colon trouble. the colon, and more"),
        ]
    )
    func takesAnOrdinaryNameOnEvidence(input: String, expected: String) {
        #expect(cleaned(input, by: sut) == expected)
    }

    @Test("recognises each requested romanised Hindi evidence word")
    func romanisedHindiEvidenceWords() {
        for word in [
            "aur", "ya", "toh", "phir", "lekin", "par", "ki", "ke", "ka", "ko", "main", "hum", "tum",
            "aap", "yeh", "woh",
        ] {
            #expect(cleaned("chai comma \(word) biscuit", by: sut) == "chai, \(word) biscuit")
        }
    }

    @Test("rules-only cleaner applies the Hinglish spoken punctuation examples")
    func rulesOnlyHinglishExamples() async throws {
        let cleaner = RuleBasedTransformer()
        for (spoken, expected) in [
            ("chai comma aur biscuit", "Chai, aur biscuit."),
            ("note colon kal chutti hai", "Note: kal chutti hai."),
        ] {
            let request = TransformationRequest(transcription: Transcription(text: spoken))
            #expect(try await cleaner.transform(request).text == expected)
        }
    }

    @Test(
        "leaves a full stop or period that is not at the end, and a hyphen or dash that is",
        arguments: [
            "the trial period ended last week",
            "ship it period next thing",
            "done full stop next",
            "we made it home dash",
            "well hyphen new line known",
            "we went home dash new line late",
        ]
    )
    func leavesMisplacedMarks(input: String) {
        #expect(cleaned(input, by: sut) == input)
    }

    @Test("records the mark on the word before and the name as removed")
    func provenance() {
        let draft = sut.apply(Draft(text: "milk comma and eggs"))
        #expect(draft.words[0].state == .replaced(by: SpokenPunctuationPass.id, from: "milk"))
        #expect(draft.words[1].state == .removed(by: SpokenPunctuationPass.id))
        #expect(draft.words[2].state == .kept)
    }

    @Test("a long unpunctuated rules-only transcript finishes inside the rules budget, keeping every word")
    func longUnpunctuatedTranscript() throws {
        let text = String(
            repeating: "so i was thinking about the garden and the tomatoes are growing well this year ",
            count: 200)
        let request = TransformationRequest(transcription: Transcription(text: text))
        let pipeline = CleaningPipeline.standard(
            for: DestinationFormatter.standard(for: request.situation), situation: request.situation,
            steps: .default, vocabulary: request.vocabulary)
        // The work is the CPU time of this thread, which other processes on a loaded machine do not add to.
        let start = clock_gettime_nsec_np(CLOCK_THREAD_CPUTIME_ID)
        let (draft, _) = RuleBasedTransformer.audited(
            pipeline, over: Draft(romanising: request.transcription))
        let spent = Duration.nanoseconds(Int64(clock_gettime_nsec_np(CLOCK_THREAD_CPUTIME_ID) - start))
        #expect(spent < StageTimeout.rules)
        #expect(draft.text.split(whereSeparator: \.isWhitespace).count == 3_000)
    }
}
