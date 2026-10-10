import Testing
import UttrflowCore

@testable import UttrflowAI

@Suite("The standard pipeline")
struct StandardPipelineTests {
    @Test("runs the passes in the shipped order")
    func order() {
        #expect(
            CleaningPipeline.standard.ids == [
                "fillers", "repeatedPhrase", "stammers", "selfCorrection", "spokenPunctuation",
                "spokenCasing",
                "layoutWords", "numberForms", "contractions", "spacing", "pauseStop", "spelledInitialism",
                "acronymCasing", "sentenceBoundary", "firstWord", "commentMarker", "terminalStop",
            ])
    }

    @Test("reads a recogniser stop and a pipeline stop as one stop, not a pause")
    func doubledStopEndsTheSentence() {
        #expect(
            CleaningPipeline.standard.run(Draft(text: "the build is done.. next we ship")).text
                == "The build is done. Next we ship.")
    }

    @Test("leaves casing and the full stop for after the model")
    func beforeModel() {
        #expect(
            CleaningPipeline.beforeModel(for: .standard(for: .plain), situation: .unknown).ids
                == Array(CleaningPipeline.standard.ids.dropLast(5)))
    }

    @Test("joins spoken initialisms after the whole message is assembled")
    func wholeTextInitialisms() {
        let pipeline = CleaningPipeline.message(for: .standard(for: .plain), situation: .unknown)
        #expect(
            pipeline.ids == [
                .spelledInitialism, .acronymCasing, SentenceBoundaryPass.id, .firstWord, CommentMarkerPass.id,
                .terminalStop,
            ])
        #expect(pipeline.run(Draft(text: "the a p i is down")).text == "The API is down.")
    }

    @Test("uses the formatter's list policy for piece clean-up")
    func pieceRespectsDestinationLists() {
        let spreadsheet = DestinationFormatter.standard(for: .spreadsheet)
        let spreadsheetPipeline = CleaningPipeline.beforeModel(
            for: spreadsheet, situation: .unknown)
        #expect(
            spreadsheetPipeline.run(Draft(text: "number one buy milk number two walk the dog")).text
                == "buy milk, walk the dog")

        let document = DestinationFormatter.standard(for: .document)
        let documentPipeline = CleaningPipeline.beforeModel(for: document, situation: .unknown)
        #expect(
            documentPipeline.run(Draft(text: "we need number one milk number two eggs")).text
                == "we need\n1. milk\n2. eggs")
    }

    @Test("uses the caret text for a leading paragraph command")
    func leadingParagraphAtCaret() {
        let formatter = DestinationFormatter.standard(for: .email)
        let existingText = AppContext(precedingText: "The numbers look fine. ")
        let existingSituation = Situation(
            app: existingText, insertion: existingText.insertionPoint, destination: .email)
        let existing = CleaningPipeline.beforeModel(for: formatter, situation: existingSituation)
        #expect(existing.run(Draft(text: "new paragraph thanks sam")).text == "\n\nthanks sam")

        let emptyField = AppContext(precedingText: "")
        let emptySituation = Situation(
            app: emptyField, insertion: emptyField.insertionPoint, destination: .email)
        let empty = CleaningPipeline.beforeModel(for: formatter, situation: emptySituation)
        #expect(empty.run(Draft(text: "new paragraph thanks sam")).text == "thanks sam")
    }

    @Test("is the plain formatter at a caret that says nothing")
    func plainByDefault() {
        let first = CleaningPipeline.standard.passes.compactMap { $0 as? FirstWordPass }.first
        let stop = CleaningPipeline.standard.passes.compactMap { $0 as? TerminalStopPass }.first
        #expect(first?.policy == .fromInsertionPoint)
        #expect(first?.state == .unknown)
        #expect(first?.onScreen == [])
        #expect(stop?.policy == .always)
    }

    @Test("configures the last two passes from the formatter, the caret and the screen")
    func builtForTheSituation() {
        let app = AppContext(documentName: "Forecast", selectedText: "Q3", precedingText: "because ")
        let situation = Situation(app: app, insertion: app.insertionPoint, destination: .spreadsheet)
        let pipeline = CleaningPipeline.standard(for: .standard(for: .spreadsheet), situation: situation)
        #expect(pipeline.ids == CleaningPipeline.standard.ids)
        let first = pipeline.passes.compactMap { $0 as? FirstWordPass }.first
        let stop = pipeline.passes.compactMap { $0 as? TerminalStopPass }.first
        #expect(first?.policy == .asSpoken)
        #expect(first?.state == .midSentence)
        #expect(first?.onScreen == ["Forecast", "Q3", "because "])
        #expect(first?.heard == nil)
        #expect(stop?.policy == .never)
        #expect(stop?.layout == .singleLine)
        #expect(pipeline.passes.contains { $0 is CaretEchoPass } == false)
    }

    @Test(
        "leaves a dictated list item open when the caret sits after its marker",
        arguments: ["- ", "* ", "\u{2022} ", "2. "])
    func listItemAtCaret(marker: String) {
        let app = AppContext(precedingText: "notes\n" + marker)
        let situation = Situation(app: app, insertion: app.insertionPoint, destination: .document)
        let pipeline = CleaningPipeline.standard(for: .standard(for: .document), situation: situation)

        #expect(pipeline.run(Draft(text: "buy milk")).text == "Buy milk")
        #expect(pipeline.run(Draft(text: "is it ready?")).text == "Is it ready?")
    }

    @Test("hands the caret's text to the echo pass after the model")
    func echoPassKnowsTheCaret() {
        let app = AppContext(documentName: "Notes", precedingText: "because ")
        let situation = Situation(app: app, insertion: app.insertionPoint, destination: .document)
        let echo = CleaningPipeline.afterModel(for: .standard(for: .document), situation: situation)
            .passes.compactMap { $0 as? CaretEchoPass }.first
        #expect(echo?.state == .midSentence)
        #expect(echo?.precedingText == "because ")
    }

    @Test("lays out a model's list answer with a capital on each item and no stop")
    func listAnswer() {
        let pages = AppContext(documentName: "Camping.pages")
        let situation = Situation(app: pages, insertion: pages.insertionPoint, destination: .document)
        let finishing = CleaningPipeline.afterModel(for: .standard(for: .document), situation: situation)
        let answer = Draft(
            keepingLineBreaks: "what's left to pack\n- the tent\n- the stove\n- the first aid kit")
        #expect(
            finishing.run(answer).text == "What's left to pack\n- The tent\n- The stove\n- The first aid kit")
    }

    @Test("ends both paragraphs of a model's email answer")
    func emailAnswer() {
        let mail = AppContext(documentName: "Re: Second floor quote")
        let situation = Situation(app: mail, insertion: mail.insertionPoint, destination: .email)
        let finishing = CleaningPipeline.afterModel(for: .standard(for: .email), situation: situation)
        let answer = Draft(
            keepingLineBreaks: "thanks for your note\n\nI've attached the revised quote for the second floor")
        #expect(
            finishing.run(answer).text
                == "Thanks for your note.\n\nI've attached the revised quote for the second floor.")
    }

    @Test("finishes a model's answer with the same two passes, copying the case the words were heard in")
    func afterModel() {
        let cell = CleaningPipeline.afterModel(
            for: .standard(for: .spreadsheet), situation: .unknown, heard: "uh total revenue")
        #expect(
            cell.ids == [
                "spokenPunctuation", "caretEcho", "caretCloser", "digitGrouping", "spelledInitialism",
                "acronymCasing", "sentenceBoundary", "firstWord", "commentMarker", "terminalStop",
            ])
        #expect(cell.run(Draft(text: "Total revenue.")).text == "total revenue")

        let app = AppContext(documentName: "Chat with John", precedingText: "because ")
        let chat = Situation(app: app, insertion: app.insertionPoint, destination: .messaging)
        let message = CleaningPipeline.afterModel(for: .standard(for: .messaging), situation: chat)
        #expect(message.run(Draft(text: "John said the build failed.")).text == "John said the build failed")
        #expect(message.run(Draft(text: "The build failed.")).text == "the build failed")
    }

    @Test(
        "cleans a whole utterance with the model switched off",
        arguments: [
            (
                "um so uh basically the the thing is we need more time",
                "So basically the thing is we need more time."
            ),
            ("let's meet at four no sorry at five on tuesday", "Let's meet at five on Tuesday."),
            ("we still need milk comma eggs comma and bread", "We still need milk, eggs, and bread."),
            ("we're on postgres sixteen point two right now", "We're on postgres 16.2 right now."),
            ("first line new line second line", "First line\nSecond line."),
            ("what do you think question mark new line thanks", "What do you think?\nThanks."),
            ("agenda new line one intro new line two demo", "Agenda\nOne intro\nTwo demo."),
            ("thanks new paragraph the second issue", "Thanks\n\nThe second issue."),
            ("is it ready question mark", "Is it ready?"),
            ("i think i'll take the earlier train", "I think I'll take the earlier train."),
            ("the dentist moved it to two thirty pm", "The dentist moved it to 2:30 pm."),
            ("", ""),
        ]
    )
    func endToEnd(input: String, expected: String) {
        #expect(CleaningPipeline.standard.run(Draft(text: input)).text == expected)
    }

    @Test(
        "removes an abandoned clause when the speaker restarts in different words",
        arguments: [
            ("I went to the I'll call you later", "I'll call you later."),
            ("can we we should just cancel", "We should just cancel."),
            ("let me I'll send it tomorrow", "I'll send it tomorrow."),
            ("she was going to she decided to stay", "She decided to stay."),
            (
                "the problem is what I wanted to say is the server is slow",
                "What I wanted to say is the server is slow."
            ),
        ]
    )
    func abandonedClauseRestarts(input: String, expected: String) {
        #expect(CleaningPipeline.standard.run(Draft(text: input)).text == expected)
    }

    @Test(
        "keeps the modal question when only the pronoun after it is stammered",
        arguments: [
            ("can you you help me with this", "Can you help me with this?"),
            ("could you you send me the file", "Could you send me the file?"),
            ("can i i borrow your pen", "Can I borrow your pen?"),
            ("can you you please check", "Can you please check?"),
            ("would we we need a visa", "Would we need a visa?"),
            ("could they they join us", "Could they join us?"),
        ]
    )
    func stammeredPronounAfterModal(input: String, expected: String) {
        #expect(CleaningPipeline.standard.run(Draft(text: input)).text == expected)
    }

    @Test(
        "keeps complete clauses that can resemble an abandoned start",
        arguments: [
            ("I said I'd go", "I said I'd go."),
            ("I went to the store; I'll call you later", "I went to the store; I'll call you later."),
            ("Let me know when you arrive", "Let me know when you arrive."),
            ("She was going to the store", "She was going to the store."),
            ("The problem is the server is slow", "The problem is the server is slow."),
        ]
    )
    func completeClausesStay(input: String, expected: String) {
        #expect(CleaningPipeline.standard.run(Draft(text: input)).text == expected)
    }

    @Test(
        "keeps repeated numbers after a digit cue through the rest of the sentence",
        arguments: [
            (
                "set the port to eighty eighty and the timeout to twenty one seconds",
                "Set the port to 8080 and the timeout to 21 seconds."
            ),
            ("set the port to eighty eighty and restart", "Set the port to 8080 and restart."),
            ("set the port to eighty eighty", "Set the port to 8080."),
            ("the server listens on port eighty eighty", "The server listens on port 8080."),
        ]
    )
    func repeatedNumberAfterCue(input: String, expected: String) {
        #expect(CleaningPipeline.standard.run(Draft(text: input)).text == expected)
    }

    @Test(
        "leaves a repeated number with no digit cue as it read before",
        arguments: [
            ("twenty twenty", "2020"),
            ("one one", "One one."),
            ("six six six", "666"),
        ]
    )
    func repeatedNumbersStay(input: String, expected: String) {
        #expect(CleaningPipeline.standard.run(Draft(text: input)).text == expected)
    }

    @Test("removes fillers glued to their neighbours by pause ellipses, keeping the ellipses between words")
    func removesGluedFillers() {
        #expect(
            CleaningPipeline.standard.run(
                Draft(text: "Ah...the...um...the invoice is...ah...overdue")
            ).text == "The...the invoice is...overdue."
        )
    }

    @Test("recognizes a layout command after spoken punctuation")
    func spokenPunctuationPrecedesLayoutWords() {
        let pipeline = CleaningPipeline.beforeModel(for: .standard(for: .plain), situation: .unknown)
        #expect(
            pipeline.run(Draft(text: "is it ready question mark new line yes")).text
                == "is it ready?\nyes")
    }

    @Test("keeps the record of every pass that touched a word")
    func provenance() {
        let draft = CleaningPipeline.standard.run(Draft(text: "um at four no sorry at five"))
        #expect(draft.text == "At five.")
        #expect(draft.removed.map(\.heard) == ["um", "at", "four", "no", "sorry"])
        #expect(draft.words[0].state == .removed(by: FillersPass.id))
        #expect(draft.words[1].state == .removed(by: SelfCorrectionPass.id))
        #expect(draft.words[5].state == .replaced(by: FirstWordPass.id, from: "at"))
        #expect(draft.words[6].state == .replaced(by: TerminalStopPass.id, from: "five"))
    }

    @Test(
        "keeps the comma the sentence needs when a filler between commas goes",
        arguments: [
            ("The deadline is, um, Friday.", "The deadline is Friday."),
            ("Well, um, I think so.", "Well, I think so."),
            ("I think, uh, that's right, uh, yeah.", "I think that's right, yeah."),
            ("Um, so, I think we should go.", "So, I think we should go."),
            ("Yes, um, I agree.", "Yes, I agree."),
            ("Okay, uh, let's start.", "Okay, let's start."),
            ("We should, uh, ship it.", "We should ship it."),
        ]
    )
    func fillerBetweenCommas(spoken: String, expected: String) {
        #expect(CleaningPipeline.standard.run(Draft(text: spoken)).text == expected)
    }

    @Test(
        "keeps a heard id or ill that opens a piece mid-sentence, and repairs it at a sentence start",
        arguments: [
            (InsertionPoint.SentenceState.midSentence, "Id is required", "id is required."),
            (.midSentence, "Ill health can follow", "ill health can follow."),
            (.midSentence, "I'd rather not", "I'd rather not."),
            (.startOfSentence, "Id rather not", "I'd rather not."),
        ]
    )
    func openingContraction(state: InsertionPoint.SentenceState, input: String, expected: String) {
        let plain = DestinationFormatter.standard(for: .plain)
        let pieces = CleaningPipeline.piece(numbers: plain.numbers, digits: plain.digits).passes
        let pipeline = CleaningPipeline(passes: pieces + [FirstWordPass(state: state), TerminalStopPass()])
        #expect(pipeline.run(Draft(text: input)).text == expected)
    }

    /// Measured on dictated hesitations: the filler's pause decided where the sentence broke. Issue #2243.
    @Test(
        "reads a hesitation's pause through, before the model and after it",
        arguments: [
            ("I think we should um... move the meeting.", "I think we should move the meeting."),
            ("The problem is um. We don't have enough time.", "The problem is we don't have enough time."),
            ("Let's um. Order pizza for the team.", "Let's order pizza for the team."),
            ("We are going to... Um. Ship it next week.", "We are going to... ship it next week."),
            ("we are done um. Next item", "We are done. Next item."),
        ]
    )
    func readsAHesitationThrough(input: String, expected: String) {
        #expect(CleaningPipeline.standard.run(Draft(text: input)).text == expected)
        let before = CleaningPipeline.beforeModel(for: .standard(for: .plain), situation: .unknown)
        let after = CleaningPipeline.afterModel(for: .standard(for: .plain), situation: .unknown)
        #expect(after.run(before.run(Draft(text: input))).text == expected)
    }
}
