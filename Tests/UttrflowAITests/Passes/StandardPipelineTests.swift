import Testing
import UttrflowCore

@testable import UttrflowAI

@Suite("The standard pipeline")
struct StandardPipelineTests {
    @Test("runs the passes in the shipped order")
    func order() {
        #expect(
            CleaningPipeline.standard.ids == [
                "fillers", "stammers", "repeatedPhrase", "selfCorrection", "spokenPunctuation", "layoutWords",
                "numberForms", "contractions", "spacing", "firstWord", "terminalStop",
            ])
    }

    @Test("leaves casing and the full stop for after the model")
    func beforeModel() {
        #expect(CleaningPipeline.beforeModel.ids == Array(CleaningPipeline.standard.ids.dropLast(2)))
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
        #expect(cell.ids == ["caretEcho", "firstWord", "terminalStop"])
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
            ("let's meet at four no sorry at five on tuesday", "Let's meet at five on tuesday."),
            ("we still need milk comma eggs comma and bread", "We still need milk, eggs, and bread."),
            ("we're on postgres sixteen point two right now", "We're on postgres 16.2 right now."),
            ("first line new line second line", "First line\nsecond line."),
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
}
