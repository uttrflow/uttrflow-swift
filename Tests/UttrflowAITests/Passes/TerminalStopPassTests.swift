import Testing
import UttrflowCore

@testable import UttrflowAI

@Suite("TerminalStopPass")
struct TerminalStopPassTests {
    private let sut = TerminalStopPass()
    private let never = TerminalStopPass(policy: .never)
    private let short = TerminalStopPass(policy: .offForShortMessages(sentences: 2))
    private let email = TerminalStopPass(destination: .email)

    @Test(
        "finishes a sentence that has no ending",
        arguments: [
            ("hello there", "hello there."), ("42", "42."), ("ship it", "ship it."),
            ("मेरी उड़ान 15 अगस्त को सुबह 9 बजे है", "मेरी उड़ान 15 अगस्त को सुबह 9 बजे है."),
        ])
    func addsStop(input: String, expected: String) {
        #expect(cleaned(input, by: sut) == expected)
    }

    @Test(
        "ends no dictation with a stop after a word that leaves the clause open",
        arguments: [
            ("i went to the bank and", "i went to the bank and"),
            ("i would go but", "i would go but"),
            ("i stayed home because", "i stayed home because"),
            ("i went to the bank and.", "i went to the bank and"),
        ])
    func danglingWord(input: String, expected: String) {
        for destination in Destination.allCases {
            let formatter = DestinationFormatter.standard(for: destination)
            let pass = TerminalStopPass(
                policy: formatter.terminalStop, layout: formatter.layout, destination: destination)
            #expect(cleaned(input, by: pass) == expected)
        }
    }

    @Test("leaves a paragraph that ends on a word leaving the clause open without a stop")
    func danglingParagraph() {
        let text = "we sent the report and\n\nthen we left the office"
        #expect(email.apply(Draft(keepingLineBreaks: text)).text == "we sent the report and\n\nthen we left the office.")
    }

    @Test("leaves an open parenthetical unfinished but keeps a question mark")
    func openBracketBeforeCaret() {
        let formatter = DestinationFormatter.standard(for: .plain)
        func pass(before: String) -> TerminalStopPass {
            TerminalStopPass(
                policy: formatter.terminalStop, layout: formatter.layout,
                insertionPoint: InsertionPoint(precedingText: before))
        }

        #expect(cleaned("buy milk", by: pass(before: "Details (")) == "buy milk")
        #expect(cleaned("is it ready?", by: pass(before: "Details (")) == "is it ready?")
        #expect(cleaned("buy milk", by: pass(before: "Details (see above) ")) == "buy milk.")
    }

    /// An unpunctuated question is finished as one, on the rules path and after a model that left it bare. Issue #2177.
    @Test(
        "finishes a sentence that asks a question with a question mark",
        arguments: [
            ("where did you put the keys", "where did you put the keys?"),
            ("papa did you take your medicine", "papa, did you take your medicine?"),
            ("that is it", "that is it."),
            ("it is a good idea", "it is a good idea."),
            ("this is a really good idea for us", "this is a really good idea for us."),
            ("that was a good point", "that was a good point."),
            ("it is my two cents", "it is my two cents."),
            ("i am a hundred percent sure", "i am a hundred percent sure."),
            ("these are a few good reasons", "these are a few good reasons."),
            ("those were a few good days", "those were a few good days."),
            ("we are a hundred percent sure", "we are a hundred percent sure."),
            ("he is a very good doctor", "he is a very good doctor."),
            ("she is a very good nurse", "she is a very good nurse."),
            ("they are a very good team", "they are a very good team."),
            ("it is good", "it is good."),
            ("she is a nurse", "she is a nurse."),
            ("the report is a good idea", "the report is a good idea."),
            ("it is not a good idea", "it is not a good idea."),
            ("here is the list: apples and pears.", "here is the list: apples and pears."),
            ("here are the files: a and b.", "here are the files: a and b."),
            ("there is a list: one two three.", "there is a list: one two three."),
            ("here is what we need: milk and eggs", "here is what we need: milk and eggs."),
            ("here is the plan", "here is the plan."),
            ("you are the best person for this", "you are the best person for this."),
            ("everything is the way it should be", "everything is the way it should be."),
            ("nothing is the same as before", "nothing is the same as before."),
            (
                "didi can you ask jiju if he's free on saturday",
                "didi, can you ask jiju if he's free on saturday?"
            ),
            (
                "hey quick question do we support ios sixteen or only seventeen and above",
                "hey quick question, do we support ios sixteen or only seventeen and above?"
            ),
            ("papa did the shopping", "papa did the shopping."),
            ("ravi is the owner of the account", "ravi is the owner of the account."),
            (
                "papa did the shopping. where is my bag",
                "papa did the shopping. where is my bag?"
            ),
            ("did the tests pass should i merge it now", "did the tests pass should i merge it now?"),
            ("the printer is jammed again who used it last", "the printer is jammed again who used it last."),
            ("Done. can you review the PR", "Done. can you review the PR?"),
            (
                "I'm blocked on the credentials for the sandbox account can someone help",
                "I'm blocked on the credentials for the sandbox account, can someone help?"
            ),
            (
                "I think this will break if the array is empty can you add a check.",
                "I think this will break if the array is empty, can you add a check?"
            ),
            (
                "This duplicates the logic in the helper class can we reuse that instead",
                "This duplicates the logic in the helper class, can we reuse that instead?"
            ),
            (
                "I don't have access to the production database can someone grant it",
                "I don't have access to the production database, can someone grant it?"
            ),
            ("it's late isn't it", "it's late isn't it?"),
            ("the meeting is at three right", "the meeting is at three, right?"),
            ("you sent the invoice right", "you sent the invoice, right?"),
            ("the file is saved right", "the file is saved, right?"),
            ("we leave at noon right", "we leave at noon, right?"),
            ("is it okay if i leave at five", "is it okay if i leave at five?"),
            ("is it fine if we start late", "is it fine if we start late?"),
            ("is it okay when i call later", "is it okay when i call later?"),
            ("what we need is more time", "what we need is more time."),
            ("I think we can do it", "I think we can do it."),
            ("Can you check? I think it's fine", "Can you check? I think it's fine."),
        ])
    func addsQuestionMark(input: String, expected: String) {
        #expect(cleaned(input, by: sut) == expected)
    }

    @Test(
        "sets off a review label said first with a colon and judges the clause after it alone",
        arguments: [
            ("nit spelling mistake hai yahan", "nit: spelling mistake hai yahan."),
            (
                "minor mujhe lagta hai we should log the error here",
                "minor: mujhe lagta hai we should log the error here."
            ),
            ("minor we should log the error here", "minor: we should log the error here."),
            ("suggestion rename this to user id", "suggestion: rename this to user id."),
            ("question why is this async", "question: why is this async?"),
            ("question is this needed", "question: is this needed?"),
            ("optional you could inline this", "optional: you could inline this."),
            ("minor changes only", "minor changes only."),
            ("optional parameters are fine", "optional parameters are fine."),
            ("question is whether we ship today", "question is whether we ship today."),
            ("suggestion for the team is to wait", "suggestion for the team is to wait."),
            ("nit: missing a blank line", "nit: missing a blank line."),
            ("we have a minor issue", "we have a minor issue."),
        ])
    func setsOffReviewTag(input: String, expected: String) {
        #expect(cleaned(input, by: sut) == expected)
    }

    @Test("sets off a review label in a short chat message without adding a stop")
    func reviewTagInChat() {
        #expect(cleaned("nit missing a blank line", by: short) == "nit: missing a blank line")
        #expect(cleaned("question why is this async", by: short) == "question: why is this async?")
    }

    @Test("leaves right as a command or confirmation instead of a question tag")
    func rightWithoutAClauseIsNotATag() {
        #expect(cleaned("turn right", by: sut) == "turn right.")
        #expect(cleaned("that's right", by: sut) == "that's right.")
        #expect(cleaned("everything is right", by: sut) == "everything is right.")
        #expect(cleaned("you should turn right", by: sut) == "you should turn right.")
        #expect(cleaned("it feels right", by: sut) == "it feels right.")
        #expect(cleaned("I have no right", by: sut) == "I have no right.")
        #expect(cleaned("you got the answer right", by: sut) == "you got the answer right.")
        #expect(cleaned("I think it is right", by: sut) == "I think it is right.")
    }

    @Test("keeps an indirect if clause as a statement")
    func indirectIfClauseIsNotAQuestion() {
        #expect(
            cleaned("I wonder if it is okay when I leave", by: sut) == "I wonder if it is okay when I leave.")
    }

    @Test("keeps a question's mark in a short chat message and adds none where the place never ends one")
    func questionMarkUnderOtherPolicies() {
        let sql = TerminalStopPass(policy: .always, layout: .preserveNewlines)
        #expect(cleaned("where total is greater than 12000", by: sql) == "where total is greater than 12000.")
        #expect(cleaned("are you coming tonight", by: short) == "are you coming tonight?")
        #expect(cleaned("on my way", by: short) == "on my way")
        #expect(cleaned("are you coming tonight", by: never) == "are you coming tonight")
    }

    @Test(
        "leaves text that already ends, looks like code, or is empty",
        arguments: [
            "hello.", "hello!", "hello?", "hello…", "hello,", "\"hello\"", "get_user(id)",
            "SELECT * FROM user;", "मेरी उड़ान 15 अगस्त को सुबह 9 बजे है।", "वह घर गया॥",
            "let x = [1, 2, 3]", "func main() {}", "",
        ]
    )
    func leavesFinished(input: String) {
        #expect(cleaned(input, by: sut) == input)
    }

    /// A symbol ends a word without ending a sentence, and the policy here is `.always`.
    @Test(
        "finishes a sentence whose last word ends in a symbol",
        arguments: [
            ("conversion went up 5%", "conversion went up 5%."),
            ("the gap is 20\u{00B0}", "the gap is 20\u{00B0}."),
            ("the cost was $5", "the cost was $5."),
        ]
    )
    func addsStopAfterASymbol(input: String, expected: String) {
        #expect(cleaned(input, by: sut) == expected)
    }

    /// The stop belongs inside the quotation it ends, which is also where the typography wants it.
    @Test(
        "puts the stop inside a closing quote",
        arguments: [
            ("she said \"ship it\"", "she said \"ship it.\""),
            ("he replied \u{201C}ship it\u{201D}", "he replied \u{201C}ship it.\u{201D}"),
        ]
    )
    func addsStopInsideAQuote(input: String, expected: String) {
        #expect(cleaned(input, by: sut) == expected)
    }

    @Test(
        "takes back a stop it put inside a quote, where the policy wants none",
        arguments: [("she said \"ship it.\"", "she said \"ship it\""), ("up 5%.", "up 5%")])
    func takesBackAStopInsideAQuote(input: String, expected: String) {
        #expect(cleaned(input, by: never) == expected)
    }

    /// A short message is finished and then unfinished, so the two have to agree on where the stop went.
    @Test(
        "leaves a short message as it was, symbol or quote and all",
        arguments: ["on my way", "up 5%", "she said \"ship it\""])
    func shortMessageKeepsItsEnding(input: String) {
        #expect(cleaned(input, by: short) == input)
    }

    @Test("adds nothing when the text holds a line break and the layout keeps newlines")
    func leavesLayout() {
        let code = TerminalStopPass(policy: .always, layout: .preserveNewlines)
        let draft = Draft(words: ["line", "one", "\n", "line", "two"].map { Draft.Word($0) })
        #expect(code.apply(draft).text == "line one\nline two")
        #expect(code.apply(Draft(text: "ship it")).text == "ship it.")
    }

    @Test("ends the last sentence under a paragraph layout whatever line breaks the text holds")
    func paragraphsEndTheLast() {
        let draft = Draft(words: ["line", "one", "\n", "line", "two"].map { Draft.Word($0) })
        #expect(sut.apply(draft).text == "line one\nline two.")
        let long = Draft(keepingLineBreaks: "One. Two.\n\nThree here")
        #expect(short.apply(long).text == "One. Two.\n\nThree here.")
    }

    @Test("leaves a model answer ending in a numbered list item without a full stop")
    func modelAnswerEndingInNumberedItem() {
        let answer = Draft(keepingLineBreaks: "Number 1 call mom\n2. Pay rent\n3. Book the flight")

        #expect(sut.apply(answer).text == "Number 1 call mom\n2. Pay rent\n3. Book the flight")
    }

    @Test(
        "ends each paragraph of three or more words with a full stop, and leaves one that has a mark",
        arguments: [
            (
                "thanks for your note\n\nI've attached the revised quote",
                "thanks for your note.\n\nI've attached the revised quote."
            ),
            ("Thanks\n\nThe second issue", "Thanks\n\nThe second issue."),
            ("Ready?\n\nSee you at five", "Ready?\n\nSee you at five."),
            ("one two\nthree four\n\nfive six seven", "one two\nthree four.\n\nfive six seven."),
        ])
    func paragraphStops(text: String, expected: String) {
        #expect(sut.apply(Draft(keepingLineBreaks: text)).text == expected)
    }

    @Test(
        "leaves short and long email greetings and sign-offs open",
        arguments: [
            ("Dear Sam", "Dear Sam"),
            ("Dear hiring manager", "Dear hiring manager"),
            ("Thanks, Sam", "Thanks, Sam"),
            ("Best regards, Samantha Jones", "Best regards, Samantha Jones"),
            ("The deck looks great. Thanks, Sam", "The deck looks great. Thanks, Sam"),
            ("The deck looks great. Thanks, Sam. Go.", "The deck looks great. Thanks, Sam. Go."),
            ("The deck looks great. Best regards\nAna", "The deck looks great. Best regards\nAna"),
            ("The deck looks great. Cheers, Jo", "The deck looks great. Cheers, Jo"),
        ])
    func emailOpenersAndClosings(text: String, expected: String) {
        #expect(email.apply(Draft(keepingLineBreaks: text)).text == expected)
    }

    @Test("leaves email greetings and signatures open while finishing body paragraphs")
    func emailBodyStops() {
        let text =
            "Dear hiring manager for the product design team\n\nI am writing to ask about the role\n\nThanks, Sam"
        #expect(
            email.apply(Draft(keepingLineBreaks: text)).text
                == "Dear hiring manager for the product design team\n\nI am writing to ask about the role.\n\nThanks, Sam"
        )
    }

    @Test("keeps the stop when body text follows a greeting in the same paragraph")
    func emailGreetingContinuesIntoBody() {
        #expect(
            email.apply(Draft(keepingLineBreaks: "Hi Priya, please send the deck")).text
                == "Hi Priya, please send the deck.")
    }

    @Test("gives a list item no stop, at the end or before a blank line")
    func listItems() {
        let list = Draft(keepingLineBreaks: "what's left to pack\n- the tent\n- the first aid kit")
        #expect(sut.apply(list).text == "what's left to pack\n- the tent\n- the first aid kit")
        let after = Draft(keepingLineBreaks: "- the tent and the stove\n\nthat is all we need")
        #expect(sut.apply(after).text == "- the tent and the stove\n\nthat is all we need.")
        let items = Draft(keepingLineBreaks: "- the tent and the stove\n- the first aid kit here")
        #expect(sut.apply(items).text == "- the tent and the stove\n- the first aid kit here")
    }

    @Test("joins every line under a single-line layout with the list separator, per #4102")
    func singleLine() {
        let cell = TerminalStopPass(policy: .never, layout: .singleLine)
        #expect(cell.apply(Draft(keepingLineBreaks: "line one\nline two.")).text == "line one, line two")
        #expect(cell.apply(Draft(keepingLineBreaks: "a\n\n- b\n- c")).text == "a, b, c")
        #expect(cell.apply(Draft(keepingLineBreaks: "one.\n\ntwo")).text == "one. two")
        let stopped = TerminalStopPass(policy: .always, layout: .singleLine)
        #expect(stopped.apply(Draft(keepingLineBreaks: "line one\nline two")).text == "line one, line two.")
    }

    @Test("adds no paragraph stop when the policy is never, and lays out paragraphs by default")
    func neverAndDefault() {
        let paragraphs = TerminalStopPass(policy: .never, layout: .paragraphs)
        #expect(
            paragraphs.apply(Draft(keepingLineBreaks: "one two three\n\nfour five six.")).text
                == "one two three\n\nfour five six")
        #expect(TerminalStopPass().layout == .paragraphs)
    }

    @Test("never adds a stop, and takes back one that was put there")
    func neverAdds() {
        #expect(cleaned("total revenue", by: never) == "total revenue")
        #expect(cleaned("total revenue.", by: never) == "total revenue")
        #expect(cleaned("return x;", by: never) == "return x;")
    }

    @Test(
        "never keeps a question mark, an exclamation mark and an ellipsis",
        arguments: ["ready?", "go!", "wait...", "wait…"])
    func neverKeepsOtherMarks(text: String) {
        #expect(cleaned(text, by: never) == text)
    }

    @Test("a short message has its stop withheld, whoever put it there")
    func shortMessages() {
        #expect(cleaned("on my way", by: short) == "on my way")
        #expect(cleaned("On my way.", by: short) == "On my way")
        #expect(
            cleaned("Are you around? I should be there in ten.", by: short)
                == "Are you around? I should be there in ten")
    }

    @Test("a longer message keeps its stop, and gains one it lacked")
    func longerMessages() {
        #expect(cleaned("One. Two. Three.", by: short) == "One. Two. Three.")
        #expect(cleaned("One. Two. Three", by: short) == "One. Two. Three.")
    }

    @Test(
        "a short message keeps a question mark, an exclamation mark and an ellipsis",
        arguments: ["Ready?", "Go!", "Well…"])
    func shortMessagesKeepOtherMarks(text: String) {
        #expect(cleaned(text, by: short) == text)
    }

    @Test(
        "counts sentences by their marks, with a decimal point and a run of marks not counting",
        arguments: [
            ("", 0), ("   ", 0), ("one", 1), ("one.", 1), ("One. Two", 2), ("One. Two.", 2),
            ("Version 16.2 is out.", 1), ("Really?! Yes.", 2), ("One!  Two?  Three...", 3),
            ("line one\nline two.", 1), ("वाक्य।", 1), ("वाक्य॥", 1),
            ("पहला वाक्य। दूसरा वाक्य॥", 2),
        ]
    )
    func sentenceCount(text: String, expected: Int) {
        #expect(TerminalStopPass.sentenceCount(text) == expected)
    }

    @Test("records the stop against the last word, and nothing against a word it left alone")
    func provenance() {
        let draft = sut.apply(Draft(text: "hello there"))
        #expect(draft.words[1].state == .replaced(by: TerminalStopPass.id, from: "there"))
        let flattened = TerminalStopPass(policy: .never, layout: .singleLine)
            .apply(Draft(keepingLineBreaks: "one\ntwo"))
        #expect(flattened.words[1].state == .removed(by: TerminalStopPass.id))
        let paragraphs = sut.apply(Draft(keepingLineBreaks: "one two three\n\nfour"))
        #expect(paragraphs.words[2].state == .replaced(by: TerminalStopPass.id, from: "three"))
        #expect(short.apply(Draft(text: "on my way")).words[2].state == .kept)
        #expect(
            never.apply(Draft(text: "on my way.")).words[2].state
                == .replaced(by: TerminalStopPass.id, from: "way."))
    }
    @Test("a one-line field drops the stop from one sentence and keeps all three of three")
    func oneLineFieldEntry() {
        let app = AppContext(accessibilityRole: "AXTextField", isMultiline: false)
        let formatter = DestinationFormatter.standard(for: SituationResolver.resolve(from: app))
        let pass = TerminalStopPass(policy: formatter.terminalStop, layout: formatter.layout)
        #expect(cleaned("Project plan", by: pass) == "Project plan")
        #expect(cleaned("Is it ready?", by: pass) == "Is it ready?")
        #expect(
            cleaned("Call Sam. Book the room. Send notes", by: pass) == "Call Sam. Book the room. Send notes."
        )
    }
}
