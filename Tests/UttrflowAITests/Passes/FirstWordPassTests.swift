import Testing
import UttrflowCore

@testable import UttrflowAI

@Suite("FirstWordPass")
struct FirstWordPassTests {
    private let sut = FirstWordPass()

    private func fromCaret(
        _ text: String, state: InsertionPoint.SentenceState, onScreen: [String] = []
    ) -> String {
        cleaned(text, by: FirstWordPass(policy: .fromInsertionPoint, state: state, onScreen: onScreen))
    }

    private func asSpoken(_ text: String, heard: String) -> String {
        cleaned(text, by: FirstWordPass(policy: .asSpoken, heard: heard))
    }

    /// An ellipsis is a pause inside the sentence, so the word after it keeps the case it was heard in.
    @Test(
        "leaves the word after an ellipsis as it was heard",
        arguments: [
            ("we should... move the meeting", "We should... move the meeting"),
            ("we should\u{2026} move it", "We should\u{2026} move it"),
            ("wait... What happened", "Wait... What happened"),
            ("really...? yes", "Really...? Yes"),
        ]
    )
    func leavesTheWordAfterAnEllipsis(input: String, expected: String) {
        #expect(cleaned(input, by: sut) == expected)
    }

    /// A sampled fallback decode can hear a whole sentence in capitals; it reaches the field in sentence case.
    @Test(
        "sets a transcript heard wholly in capitals in sentence case",
        arguments: [
            ("KAL MEETING HAI, PLEASE SLIDES READY RAKHNA.", "Kal meeting hai, please slides ready rakhna."),
            ("THE BUILD IS GREEN. I WILL SHIP IT", "The build is green. I will ship it"),
            ("SHIP THE API TODAY", "Ship the API today"),
        ]
    )
    func lowersAShoutedTranscript(input: String, expected: String) {
        #expect(cleaned(input, by: FirstWordPass(policy: .fromInsertionPoint, state: .unknown)) == expected)
    }

    /// Two capitalised words are as likely an acronym pair as a shout, and a capital a pass wrote was asked for.
    @Test(
        "keeps capitals that are not the decoder's shout",
        arguments: ["ship the API to AWS", "AWS API", "OK"]
    )
    func keepsCapitalsThatAreNotAShout(input: String) {
        #expect(
            cleaned(input, by: FirstWordPass(policy: .fromInsertionPoint, state: .unknown)).dropFirst()
                == input.dropFirst())
    }

    @Test("keeps capitals a spoken casing command wrote")
    func keepsSpokenCapitals() {
        var draft = Draft(text: "say hello world now")
        for index in draft.presentIndices.dropFirst() {
            draft.replace(at: index, with: draft.words[index].text.uppercased(), by: SpokenCasingPass.id)
        }
        let result = FirstWordPass(policy: .fromInsertionPoint, state: .unknown).apply(draft)
        #expect(result.text == "Say HELLO WORLD NOW")
    }

    /// A word whose dictionary form is capitalised is a name, so a capital after the first word stays on every run.
    @Test(
        "keeps a capitalised name after the first word, and a second run changes nothing",
        arguments: [
            ("at Delhi", "At Delhi"), ("the Delhi", "The Delhi"), ("we met in Paris", "We met in Paris"),
        ]
    )
    func keepsANameAfterTheFirstWord(input: String, expected: String) {
        let once = cleaned(input, by: sut)
        #expect(once == expected)
        #expect(cleaned(once, by: sut) == once)
    }

    @Test(
        "capitalises the start of every sentence",
        arguments: [
            ("hello there", "Hello there"),
            ("hello. there", "Hello. There"),
            ("hello! there? okay", "Hello! There? Okay"),
            ("42 things", "42 things"),
            ("\"hello\" there", "\"Hello\" there"),
            ("", ""),
        ]
    )
    func capitalisesSentences(input: String, expected: String) {
        #expect(cleaned(input, by: sut) == expected)
    }

    /// A file name, path, URL, version or identifier the recogniser wrote keeps its case at any sentence start.
    @Test(
        "keeps a technical token's case at a sentence start",
        arguments: [
            ("config.yaml is missing.", "config.yaml is missing."),
            ("src/app/main.swift fails to compile.", "src/app/main.swift fails to compile."),
            ("user_id is null.", "user_id is null."), ("v2.3.1 is out.", "v2.3.1 is out."),
            ("k8s is down again.", "k8s is down again."), ("x86_64 builds fail.", "x86_64 builds fail."),
            ("https://example.com/docs is the link.", "https://example.com/docs is the link."),
            ("ok. node_modules is huge.", "Ok. node_modules is huge."),
            ("done. example.com is up", "Done. example.com is up"),
            ("and/or works. e.g. this", "And/or works. E.g. this"),
            ("okay.thanks for that", "Okay.thanks for that"),
        ]
    )
    func keepsTechnicalTokenCase(input: String, expected: String) {
        #expect(cleaned(input, by: sut) == expected)
        #expect(cleaned(input, by: FirstWordPass(policy: .alwaysCapital)) == expected)
    }

    @Test("lower-cases no technical token after a mid-sentence caret")
    func keepsTechnicalTokenMidSentence() {
        #expect(fromCaret("README.md is stale", state: .midSentence) == "README.md is stale")
        #expect(fromCaret("Hello there", state: .midSentence) == "hello there")
    }

    @Test(
        "keeps mixed-case product names at sentence starts and insertion points",
        arguments: ["iPhone", "eBay", "macOS", "iOS", "WiFi", "YouTube"]
    )
    func keepsMixedCaseProductNames(text: String) {
        #expect(cleaned(text, by: sut) == text)
        #expect(fromCaret(text, state: .midSentence) == text)
        #expect(asSpoken(text, heard: text) == text)
    }

    /// An abbreviation carries a stop of its own, and the word after it is still inside the sentence.
    @Test(
        "does not start a sentence after a dotted abbreviation",
        arguments: [
            ("call me at 5 p.m. tomorrow", "Call me at 5 p.m. tomorrow"),
            ("we meet at 9 a.m. sharp", "We meet at 9 a.m. sharp"),
            ("bring a laptop e.g. the old one", "Bring a laptop e.g. the old one"),
            ("etc. and drinks", "Etc. and drinks"),
            ("apples vs. oranges", "Apples vs. oranges"),
            ("dr. lee is here", "Dr. lee is here"),
            ("mr. smith left", "Mr. smith left"),
            ("mrs. jones left", "Mrs. jones left"),
            ("ms. singh left", "Ms. singh left"),
            ("st. paul is nearby", "St. paul is nearby"),
            ("see dr. lee tomorrow", "See Dr. lee tomorrow"),
            ("we finished etc. And then left", "We finished etc. And then left"),
        ]
    )
    func abbreviationsDoNotEndASentence(input: String, expected: String) {
        #expect(cleaned(input, by: sut) == expected)
    }

    @Test("a capitalized word after a terminal abbreviation starts a new sentence")
    func terminalAbbreviationCanEndSentence() {
        #expect(
            cleaned("we brought snacks, etc. And then we left", by: sut)
                == "We brought snacks, etc. And then we left")
        #expect(cleaned("we met Dr. Lee. Then we left", by: sut) == "We met Dr. Lee. Then we left")
    }

    @Test("a spoken comma replaces a recognizer stop and leaves the next continuation lower-case")
    func spokenCommaDoesNotLeaveAFalseSentenceCapital() {
        let afterPunctuation = SpokenPunctuationPass().apply(
            Draft(text: "we shipped comma. Of course it broke"))

        #expect(FirstWordPass().apply(afterPunctuation).text == "We shipped, of course it broke")
    }

    @Test(
        "capitalises the pronoun I, alone or contracted",
        arguments: [
            ("i think so", "I think so"),
            ("well i think", "Well I think"),
            ("i e the main one", "I e the main one"),
            ("i", "I"),
            ("i, therefore", "I, therefore"),
            ("well i'll go", "Well I'll go"),
            ("well i\u{2019}m late", "Well I\u{2019}m late"),
            ("it is fine", "It is fine"),
            ("i18n is hard", "i18n is hard"),
            ("the i18n work", "The i18n work"),
        ]
    )
    func capitalisesPronoun(input: String, expected: String) {
        #expect(cleaned(input, by: sut) == expected)
    }

    @Test("capitalises unambiguous weekday and month names without changing May or March")
    func capitalisesCalendarWords() {
        #expect(cleaned("we meet on tuesday in august", by: sut) == "We meet on Tuesday in August")
        #expect(cleaned("it may happen in march", by: sut) == "It may happen in march")
        #expect(cleaned("sat and sun are short", by: sut) == "Sat and sun are short")
    }

    @Test(
        "capitalises May and March only where the clause dates them",
        arguments: [
            ("the third of march", "The third of March"),
            ("we leave on the third of may", "We leave on the third of May"),
            ("we meet march fifth", "We meet March fifth"),
            ("it is may twelfth", "It is May twelfth"),
            ("we march on friday", "We march on Friday"),
            ("you may go", "You may go"),
            ("we may first ask", "We may first ask"),
            ("the second march was long", "The second march was long"),
        ]
    )
    func capitalisesDatedMonths(input: String, expected: String) {
        #expect(cleaned(input, by: sut) == expected)
    }

    @Test("capitalises unambiguous place, language and nationality names")
    func capitalisesProperNames() {
        #expect(cleaned("we went to london and tokyo", by: sut) == "We went to London and Tokyo")
        #expect(cleaned("he lives in new york", by: sut) == "He lives in New York")
        #expect(cleaned("she speaks french and spanish", by: sut) == "She speaks French and Spanish")
        #expect(cleaned("she moved to india", by: sut) == "She moved to India")
        #expect(cleaned("we speak hindi at home", by: sut) == "We speak Hindi at home")
        #expect(cleaned("we drove through texas", by: sut) == "We drove through Texas")
        #expect(cleaned("the germans won", by: sut) == "The Germans won")
        #expect(cleaned("we flew to paris last june", by: sut) == "We flew to Paris last June")
    }

    @Test("leaves ambiguous common nouns and ordinary uses of new and york alone")
    func leavesAmbiguousWordsAlone() {
        #expect(cleaned("we ate turkey in china", by: sut) == "We ate turkey in china")
        #expect(cleaned("this is a new idea about york", by: sut) == "This is a new idea about york")
    }

    @Test(
        "leaves locale names that are everyday words in lower case",
        arguments: [
            ("i need to polish the table", "I need to polish the table"),
            ("the best in the world", "The best in the world"),
            ("the world cup final is tonight", "The world cup final is tonight"),
            ("print hello world", "Print hello world"),
            ("she wore a wool jersey", "She wore a wool jersey"),
            ("she wore a guernsey", "She wore a guernsey"),
            ("the guinea pig escaped", "The guinea pig escaped"),
            ("the lamb is a ewe", "The lamb is a ewe"),
            ("we saw it from afar", "We saw it from afar"),
            ("the slave trade was abolished", "The slave trade was abolished"),
            ("the snake bared a fang", "The snake bared a fang"),
            ("a hanging chad", "A hanging chad"),
        ])
    func leavesOrdinaryWordNamesAlone(spoken: String, written: String) {
        #expect(cleaned(spoken, by: sut) == written)
    }

    @Test("keeps a known proper name capital at a mid-sentence caret")
    func properNameAtCaret() {
        #expect(fromCaret("london is lovely", state: .midSentence) == "London is lovely")
        #expect(fromCaret("new york is crowded", state: .midSentence) == "New York is crowded")
    }

    @Test("keeps weekdays and unambiguous months capitalised at a mid-sentence caret")
    func calendarWordsAtMidSentenceCaret() {
        #expect(fromCaret("Friday is good", state: .midSentence) == "Friday is good")
        #expect(fromCaret("March is busy", state: .midSentence) == "March is busy")
        #expect(fromCaret("May is busy", state: .midSentence) == "may is busy")
    }

    @Test("calendar casing follows prose destinations and leaves terminal and code case spoken")
    func calendarWordsRespectDestination() {
        let situation = Situation.unknown
        for destination: Destination in [.plain, .document, .email, .messaging, .sqlEditor] {
            let pipeline = CleaningPipeline.standard(
                for: .standard(for: destination), situation: situation)
            #expect(
                pipeline.run(Draft(text: "we meet on tuesday in august")).text
                    .hasPrefix("We meet on Tuesday in August"))
        }
        for destination: Destination in [.terminal, .codeEditor, .spreadsheet] {
            let pipeline = CleaningPipeline.standard(
                for: .standard(for: destination), situation: situation)
            #expect(
                pipeline.run(Draft(text: "we meet on tuesday in august")).text
                    .hasSuffix("e meet on tuesday in august"))
        }
    }

    @Test("starts a sentence after every line break, paragraph, or bullet")
    func layout() {
        let paragraph = Draft(
            words: ["hello", "\n\n", "there", "\n- ", "milk", "\n", "eggs"].map {
                Draft.Word($0, evidence: .unknown)
            })
        #expect(sut.apply(paragraph).text == "Hello\n\nThere\n- Milk\nEggs")
    }

    @Test("a line starts a sentence even when no punctuation precedes it")
    func lineStartsSentenceWithoutPunctuation() {
        let line = Draft(
            words: ["first", "line", "\n", "second", "line"].map { Draft.Word($0, evidence: .unknown) })
        let paragraph = Draft(
            words: ["first", "line", "\n\n", "second", "line"].map { Draft.Word($0, evidence: .unknown) })
        #expect(sut.apply(line).text == "First line\nSecond line")
        #expect(sut.apply(paragraph).text == "First line\n\nSecond line")
    }

    @Test(
        "an abbreviation's stop does not open a sentence unless the abbreviation table says it may",
        arguments: [
            ("call Dr. rao at 5 p.m. today", "Call Dr. rao at 5 p.m. today"),
            ("fruit e.g. apples", "Fruit e.g. apples"),
            ("meet at 5 p.m. Sharp", "Meet at 5 p.m. Sharp"),
            ("see fig. three", "See fig. three"),
            ("it was done. then home", "It was done. Then home"),
        ])
    func abbreviationsKeepTheSentenceOpen(input: String, expected: String) {
        #expect(cleaned(input, by: sut) == expected)
    }

    @Test(
        "lower-cases the first word for a caret mid-sentence, and a later sentence still starts with a capital",
        arguments: [
            ("Hello there. Again", "hello there. Again"),
            ("The build failed.", "the build failed."),
            ("\"Hello\"", "\"hello\""),
            ("\"Quoted\" words.", "\"quoted\" words."),
            ("42 things", "42 things"),
            ("", ""),
        ]
    )
    func lowersMidSentence(input: String, expected: String) {
        #expect(fromCaret(input, state: .midSentence) == expected)
    }

    @Test(
        "gives the first word a capital anywhere but mid-sentence",
        arguments: [InsertionPoint.SentenceState.startOfText, .startOfSentence, .unknown]
    )
    func capitalElsewhere(state: InsertionPoint.SentenceState) {
        #expect(fromCaret("the build failed.", state: state) == "The build failed.")
        #expect(fromCaret("The build failed.", state: state) == "The build failed.")
    }

    /// A terminal's caret is reported as `.unknown`; with `.asSpoken` the heard case is what survives.
    @Test(
        "as spoken keeps the heard case of a terminal command at an unknown caret",
        arguments: [
            ("ls dash la", "ls dash la"),
            ("npm run build", "npm run build"),
            ("git commit dash m fix the login bug", "git commit dash m fix the login bug"),
        ]
    )
    func asSpokenForTerminalAtUnknownCaret(text: String, expected: String) {
        let pass = FirstWordPass(policy: .asSpoken, state: .unknown, heard: text)
        #expect(cleaned(text, by: pass) == expected)
    }

    @Test(
        "keeps the capital of I, its contractions and an acronym mid-sentence",
        arguments: [
            "I think so.", "I'll be there.", "I\u{2019}m late.", "API returns JSON.", "NASA said so.",
            "USB-C only.",
        ]
    )
    func exemptions(text: String) {
        #expect(fromCaret(text, state: .midSentence) == text)
    }

    @Test("always capital gives the first word a capital whatever the caret says")
    func alwaysCapital() {
        let pass = FirstWordPass(policy: .alwaysCapital, state: .midSentence)
        #expect(cleaned("hello there", by: pass) == "Hello there")
        #expect(cleaned("42 things", by: pass) == "42 things")
        #expect(cleaned("", by: pass) == "")
    }

    @Test("as spoken copies the case the first word was heard in, past any filler before it")
    func asSpoken() {
        #expect(asSpoken("Total revenue", heard: "um total revenue") == "total revenue")
        #expect(asSpoken("Total revenue", heard: "total revenue") == "total revenue")
        #expect(asSpoken("total revenue", heard: "Total revenue") == "Total revenue")
        #expect(asSpoken("Total, revenue", heard: "total revenue") == "total, revenue")
        #expect(asSpoken("\"Total\" revenue", heard: "total revenue") == "\"total\" revenue")
    }

    @Test("as spoken leaves a first word the model changed, or that has no letters, alone")
    func asSpokenOnlyForTheSameWord() {
        #expect(asSpoken("Sum of revenue", heard: "total revenue") == "Sum of revenue")
        #expect(asSpoken("42 things", heard: "42 things") == "42 things")
        #expect(asSpoken("", heard: "total") == "")
    }

    @Test("as spoken reads the draft's own heard words when no transcript is given")
    func asSpokenFromTheDraft() {
        let pass = FirstWordPass(policy: .asSpoken)
        var draft = Draft(text: "um total revenue")
        draft.remove(at: 0, by: FillersPass.id)
        draft.replace(at: 1, with: "Total", by: "test")
        #expect(pass.apply(draft).text == "total revenue")
        #expect(cleaned("Total revenue", by: pass) == "Total revenue")
    }

    @Test("keeps a first word that reappears capitalised later in the output, off a sentence start")
    func keepsNameSeenAgainInOutput() {
        #expect(
            fromCaret("John said the build failed, so John fixed it.", state: .midSentence)
                == "John said the build failed, so John fixed it.")
        #expect(
            fromCaret("Because the build failed. Because of that.", state: .midSentence)
                == "because the build failed. Because of that.")
    }

    @Test("keeps a first word that the screen shows capitalised, in the title or around the caret")
    func keepsNameSeenOnScreen() {
        let text = "John said the build failed."
        #expect(fromCaret(text, state: .midSentence, onScreen: ["Chat with John"]) == text)
        #expect(fromCaret(text, state: .midSentence, onScreen: ["", "Ask (John) tomorrow."]) == text)
        #expect(
            fromCaret(text, state: .midSentence, onScreen: ["Notes"]) == "john said the build failed.")
    }

    @Test(
        "lowers a common first word mid-sentence, and keeps I and an acronym, whatever the screen shows",
        arguments: [
            ("Because the build failed.", "because the build failed."),
            ("I'll fix it.", "I'll fix it."), ("API returns JSON.", "API returns JSON."),
        ]
    )
    func lowersOrKeepsWithScreen(text: String, expected: String) {
        let screen = ["Because - Notes", "ok. Because"]
        #expect(fromCaret(text, state: .midSentence, onScreen: screen) == expected)
    }

    @Test("sights a name off a sentence start only, and not in a text capitalised throughout")
    func looksLikeName() {
        #expect(FirstWordPass.looksLikeName("John", in: ["so John said"]))
        #expect(FirstWordPass.looksLikeName("john", in: ["so \"John\" said"]))
        #expect(!FirstWordPass.looksLikeName("John", in: ["so john said"]))
        #expect(!FirstWordPass.looksLikeName("John", in: ["John said", "ok. John said", "ok\nJohn said"]))
        #expect(!FirstWordPass.looksLikeName("John", in: ["Mail - John Smith"]))
        #expect(!FirstWordPass.looksLikeName("...", in: ["so ... said"]))
        #expect(!FirstWordPass.looksLikeName("John", in: []))
    }

    @Test("names an exemption exactly: a lone capital or a run of two or more")
    func keepsCapital() {
        #expect(FirstWordPass.keepsCapital("I"))
        #expect(FirstWordPass.keepsCapital("I'd"))
        #expect(FirstWordPass.keepsCapital("\"I'd\""))
        #expect(FirstWordPass.keepsCapital("USB-C"))
        #expect(!FirstWordPass.keepsCapital("A"))
        #expect(!FirstWordPass.keepsCapital("It"))
        #expect(!FirstWordPass.keepsCapital("Ice"))
    }

    @Test(
        "keeps the capital of a letter-and-digit code, which no sentence start explains",
        arguments: ["A4", "Q3", "M2", "S3", "B12", "I-95", "H2", "A4,", "\"Q3\""])
    func keepsCodeCapital(code: String) {
        #expect(FirstWordPass.keepsCapital(code))
        #expect(FirstWordPass.lowercasedAtRunOnSeam(code, in: "") == nil)
    }

    @Test(
        "still lowers an ordinary word with no digit in it",
        arguments: ["Be", "After", "Again", "Bring", "Quarter", "Model", "So", "Highway"])
    func lowersOrdinaryWord(word: String) {
        #expect(!FirstWordPass.keepsCapital(word))
    }

    /// The first "total" was dropped by a pass, so the case comes from the "Total" that is still there.
    @Test("as spoken reads the case from where the first word stands, not from a copy a pass dropped")
    func asSpokenReadsItsOwnPlace() {
        var draft = Draft(
            words: ["total", "um", "Total", "Revenue"].map { Draft.Word($0, evidence: .unknown) })
        draft.remove(at: 0, by: .repeatedPhrase)
        draft.remove(at: 1, by: .fillers)
        let cased = FirstWordPass(policy: .asSpoken).apply(draft)
        #expect(cased.text == "Total Revenue")
    }

    @Test(
        "lowers a capital the recogniser put on an ordinary word mid-sentence",
        arguments: [
            ("The train leaves at 7.15 from Platform 4.", "The train leaves at 7.15 from platform 4."),
            (
                "Tamsin will present the Zephyrix Roadmap on Monday.",
                "Tamsin will present the Zephyrix roadmap on Monday."
            ),
            (
                "Please Rebase your branch on Main and Push again.",
                "Please rebase your branch on main and push again."
            ),
            ("The Database Index reduced the query time.", "The database index reduced the query time."),
            ("I said API and Q4 to London.", "I said API and Q4 to London."),
        ]
    )
    func lowersAStrayCapital(input: String, expected: String) {
        #expect(cleaned(input, by: sut) == expected)
    }

    @Test("keeps a mid-sentence capital the dictionary or the screen holds")
    func keepsAStrayCapitalWithEvidence() {
        let text = "I bought an Apple and a Bill."
        #expect(
            cleaned(text, by: FirstWordPass(vocabulary: ["Apple Music"])) == "I bought an Apple and a bill.")
        #expect(
            cleaned(text, by: FirstWordPass(onScreen: ["ask Bill about it"]))
                == "I bought an apple and a Bill.")
    }

    @Test("leaves mid-sentence capitals alone where the policy copies the heard case")
    func leavesStrayCapitalsAsSpoken() {
        #expect(asSpoken("we merged to Main", heard: "we merged to Main") == "we merged to Main")
    }

    @Test("records a changed word against this pass, once")
    func provenance() {
        let draft = sut.apply(Draft(text: "hello there"))
        #expect(draft.words[0].state == .replaced(by: FirstWordPass.id, from: "hello"))
        #expect(draft.words[1].state == .kept)
        let unchanged = FirstWordPass(policy: .fromInsertionPoint, state: .midSentence).apply(
            Draft(text: "hello"))
        #expect(unchanged.words[0].state == .kept)
    }

    /// A dictionary entry in lower case keeps that case at any sentence start, under every policy.
    @Test(
        "keeps a lower-case dictionary spelling at a sentence start",
        arguments: [
            (FirstWordPolicy.fromInsertionPoint, "kubectl apply the file", "kubectl apply the file"),
            (.fromInsertionPoint, "it failed. kubectl apply again", "It failed. kubectl apply again"),
            (.fromInsertionPoint, "npm install. zorbix runs it", "npm install. zorbix runs it"),
            (.alwaysCapital, "kubectl apply the file", "kubectl apply the file"),
            (.alwaysCapital, "done. npm test next", "Done. npm test next"),
        ]
    )
    func keepsAPinnedLowerCaseSpelling(policy: FirstWordPolicy, input: String, expected: String) {
        let pass = FirstWordPass(policy: policy, vocabulary: ["kubectl", "npm", "zorbix"])
        #expect(cleaned(input, by: pass) == expected)
    }

    @Test("still capitalises an ordinary lower-case entry and keeps a capitalised one")
    func pinsOnlyUnusualLowerCaseEntries() {
        let pass = FirstWordPass(vocabulary: ["okay", "Zorbix"])
        #expect(cleaned("okay then. zorbix is up", by: pass) == "Okay then. Zorbix is up")
    }
}
