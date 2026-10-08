import Testing
import UttrflowCore

@testable import UttrflowAI

@Suite("LayoutWordsPass")
struct LayoutWordsPassTests {
    private let sut = LayoutWordsPass()

    @Test(
        "turns a layout word between other words into layout",
        arguments: [
            ("first line new line second line", "first line\nsecond line"),
            ("thanks new paragraph the second issue", "thanks\n\nthe second issue"),
            ("thanks blank line the second issue", "thanks\n\nthe second issue"),
            ("we need bullet point milk bullet point eggs", "we need\n- milk\n- eggs"),
            (
                "bullet point added the sidebar bullet point fixed a crash bullet point removed a flag",
                "- added the sidebar\n- fixed a crash\n- removed a flag"
            ),
            (
                "what's left to pack bullet point the tent bullet point the stove bullet point the first aid kit",
                "what's left to pack\n- the tent\n- the stove\n- the first aid kit"
            ),
            (
                "the plan bullet point write the spec bullet point review it",
                "the plan\n- write the spec\n- review it"
            ),
            (
                "priorities this week number one hire a designer number two finish the audit",
                "priorities this week\n1. hire a designer\n2. finish the audit"
            ),
            ("agenda new line one intro new line two demo", "agenda\none intro\ntwo demo"),
            (
                "here is the plan. number one, fix the build. number two, ship it",
                "here is the plan.\n1. fix the build.\n2. ship it"
            ),
            (
                "Shopping list, bullet point milk, bullet point eggs, bullet point bread.",
                "Shopping list\n- milk\n- eggs\n- bread."
            ),
            ("milk, new line eggs", "milk,\neggs"),
            ("milk; next point eggs", "milk\n- eggs"),
            ("milk,\" bullet point eggs", "milk\"\n- eggs"),
            ("milk... bullet point eggs", "milk...\n- eggs"),
            ("milk, bullet point eggs?", "milk\n- eggs?"),
            ("first, next point second", "first\n- second"),
        ]
    )
    func laysOut(input: String, expected: String) {
        #expect(cleaned(input, by: sut) == expected)
    }

    @Test(
        "keeps clause commas before line and paragraph breaks but removes them before list items",
        arguments: [
            ("dear sam, new line thanks", "dear sam,\nthanks"),
            ("best regards, new paragraph sam", "best regards,\n\nsam"),
            ("milk, bullet point eggs", "milk\n- eggs"),
            ("milk, number one eggs number two bread", "milk\n1. eggs\n2. bread"),
        ]
    )
    func keepsClauseCommaBeforeBreak(input: String, expected: String) {
        #expect(cleaned(input, by: sut) == expected)
    }

    @Test(
        "numbers the items a spoken number opens",
        arguments: [
            ("number one call mom number two pay rent", "1. call mom\n2. pay rent"),
            ("we need number one milk number two eggs", "we need\n1. milk\n2. eggs"),
            (
                "then number two call the landlord number three pay the rent",
                "then\n2. call the landlord\n3. pay the rent"
            ),
            ("we need number 1 milk number 2 eggs", "we need\n1. milk\n2. eggs"),
            ("we need number twenty one milk number twenty two eggs", "we need\n21. milk\n22. eggs"),
            (
                "agenda number one budget number two hiring number three offsite",
                "agenda\n1. budget\n2. hiring\n3. offsite"
            ),
            (
                "the steps are number one gather the files number two check the names",
                "the steps are\n1. gather the files\n2. check the names"
            ),
            ("number one budget number two hiring", "1. budget\n2. hiring"),
        ]
    )
    func numbersItems(input: String, expected: String) {
        #expect(cleaned(input, by: sut) == expected)
    }

    @Test(
        "keeps numbered-item positions valid for reported consecutive-number inputs",
        arguments: [
            "Number 5, milk. Number 6, eggs.",
            "Number five milk. Number six eggs.",
            "number 10 milk number 11 eggs",
            "number 5 number 6",
        ])
    func keepsConsecutiveNumbersSafe(input: String) {
        #expect(!cleaned(input, by: sut).isEmpty)
    }

    @Test("keeps consecutive numbered items safe for each insertion state")
    func keepsNumberedItemsSafeAcrossInsertionStates() {
        let precedingTexts: [String?] = [
            nil, "", "The previous sentence ended. ", "I looked at the numbers ",
        ]
        for precedingText in precedingTexts {
            let pass = LayoutWordsPass(insertionPoint: InsertionPoint(precedingText: precedingText))
            for first in 1...30 {
                let input = "Number \(first), milk. Number \(first + 1), eggs."
                #expect(!cleaned(input, by: pass).isEmpty)
            }
        }
    }

    @Test("keeps a repeated label with each numbered item")
    func keepsRepeatedLabelsWithNumberedItems() {
        #expect(
            cleaned(
                "reason number one it is cheap reason number two it is fast reason number three it works",
                by: sut)
                == "Reason 1: it is cheap\nReason 2: it is fast\nReason 3: it works")
    }

    @Test(
        "keeps numbers after dictated line breaks instead of treating the break as a repeated label",
        arguments: [
            (
                "agenda new line number one budget new line number two hiring new line number three billing",
                "agenda\n\n1. budget\n\n2. hiring\n\n3. billing"
            ),
            (
                "agenda new paragraph number one budget new line number two hiring",
                "agenda\n\n\n1. budget\n\n2. hiring"
            ),
        ]
    )
    func keepsNumberedItemsAfterLayoutBreaks(input: String, expected: String) {
        #expect(cleaned(input, by: sut) == expected)
    }

    @Test("keeps repeated step labels with numbered items")
    func keepsRepeatedStepLabelsWithNumberedItems() {
        #expect(
            cleaned(
                "step number one open the app step number two tap settings",
                by: sut)
                == "Step 1: open the app\nStep 2: tap settings")
    }

    @Test("does not turn repeated numbered labels into lists where lists are unavailable")
    func leavesRepeatedLabelsAsProseWithoutListLayout() {
        let input = "reason number one it is cheap reason number two it is fast"
        #expect(cleaned(input, by: LayoutWordsPass(layout: .paragraphs)) == input)
    }

    @Test(
        "keeps connected number words in a sentence when an item ends in a conjunction",
        arguments: [
            "the list includes number one speed number two cost and number three quality all of which matter",
            "we ranked number one on speed number two on price and number three on support last year",
            "we ranked number one on speed number two on price number three on support last year",
            "she said number one was the plan and number two was the backup which we never used",
            "they named number one Ada and number two Lin before the vote closed",
            "we need number one milk number two eggs or number three bread",
        ]
    )
    func keepsConjoinedNumbersInSentences(input: String) {
        #expect(cleaned(input, by: sut) == input)
    }

    /// Issue 254: with no lookback to ask, a phrase opening its sentence is an item only if the speaker set it off.
    @Test(
        "reads a phrase opening its sentence as layout only when a mark sets it off",
        arguments: [
            ("the build failed. number one is broken", "the build failed. number one is broken"),
            ("here is the plan. number one, fix the build", "here is the plan.\n1. fix the build"),
            ("number one, fix the build", "1. fix the build"),
            ("number one check logs number two restart the server", "1. check logs\n2. restart the server"),
            ("number one is broken", "number one is broken"),
            ("bullet point, the milk", "- the milk"),
            ("we shipped. bullet point, the milk", "we shipped.\n- the milk"),
            // A break at the head of the text has nothing to break from, so the words stay.
            ("new line, hello there", "new line, hello there"),
        ]
    )
    func readsTheSentenceNotTheText(input: String, expected: String) {
        #expect(cleaned(input, by: sut) == expected)
    }

    /// Issue 566: a break said straight after a sentence's stop is the break, however the stop arrived.
    @Test(
        "reads a break opening a sentence as layout, since a stop then a break is how one is dictated",
        arguments: [
            ("the build is green. new paragraph thanks everyone", "the build is green.\n\nthanks everyone"),
            ("is it ready? new line yes", "is it ready?\nyes"),
            ("the build is green. blank line thanks everyone", "the build is green.\n\nthanks everyone"),
            ("is it ready? New paragraph. Yes", "is it ready?\n\nYes"),
            // Still words when nothing follows, and still an item's business to be set off.
            ("the build is green. new paragraph", "the build is green. new paragraph"),
            ("we shipped. bullet point the milk", "we shipped. bullet point the milk"),
        ]
    )
    func readsABreakAfterAStop(input: String, expected: String) {
        #expect(cleaned(input, by: sut) == expected)
    }

    @Test(
        "uses known text at the caret to decide what a leading break means",
        arguments: [
            ("The numbers look fine. ", "\n\nthanks sam"),
            ("I looked at the numbers ", "\n\nthanks sam"),
        ]
    )
    func leadingBreakWithTextBeforeCaret(precedingText: String, expected: String) {
        let pass = LayoutWordsPass(insertionPoint: InsertionPoint(precedingText: precedingText))
        #expect(cleaned("new paragraph thanks sam", by: pass) == expected)
    }

    @Test("drops a leading break command in a known empty field")
    func leadingBreakInEmptyField() {
        let pass = LayoutWordsPass(insertionPoint: InsertionPoint(precedingText: ""))
        #expect(cleaned("new paragraph thanks sam", by: pass) == "thanks sam")
    }

    @Test("keeps the existing numbered item behavior at the caret")
    func numberedItemAtCaret() {
        let pass = LayoutWordsPass(insertionPoint: InsertionPoint(precedingText: "The numbers look fine. "))
        #expect(cleaned("number one, thanks sam", by: pass) == "1. thanks sam")
    }

    /// One spoken phrase cannot straddle a sentence end, so neither the phrase nor the item number reaches past one.
    @Test(
        "reads neither a layout phrase nor an item number across a sentence end",
        arguments: [
            (
                "we need number nineteen milk number twenty. One more of them",
                "we need\n19. milk\n20. One more of them"
            ),
            ("I bought something new. Line up here", "I bought something new. Line up here"),
            ("show me what is next. Point two is wrong", "show me what is next. Point two is wrong"),
        ]
    )
    func staysInsideTheSentence(input: String, expected: String) {
        #expect(cleaned(input, by: sut) == expected)
    }

    @Test(
        "leaves a layout word that is mentioned, first, or last",
        arguments: [
            "add a new line here",
            "the next point is",
            "new line",
            "hello new line",
            "new line hello",
            "my next point of order",
            "three bullet points",
            "the number one problem is latency",
            "my number one priority is shipping",
            "number one buy the milk",
            "and that is number two",
        ]
    )
    func leavesMentions(input: String) {
        #expect(cleaned(input, by: sut) == input)
    }

    @Test(
        "keeps layout phrases named by verbs as words",
        arguments: [
            "type bullet point to start a list",
            "say new line when you want a break",
            "make one more next point soon",
            "write new paragraph in the notes",
            "use new line in the example",
            "press bullet point to start a list",
            "pack bullet point milk then say new line",
        ]
    )
    func keepsVerbLedMentions(input: String) {
        #expect(cleaned(input, by: sut) == input)
    }

    @Test(
        "leaves a layout phrase an opener heads across modifiers",
        arguments: [
            "her first new line was funny", "our best new line got a laugh",
            "his first new paragraph was long", "the very last new line matters",
            "that final new paragraph needs work", "the opening new line got applause",
            "her next new paragraph starts badly", "a great new line got a laugh",
            "the funniest new line was hers", "our tallest new line got a laugh",
            "the brightest new paragraph needs work",
            "her new line manager is kind", "every new line counts",
        ]
    )
    func leavesModifiedMentions(input: String) {
        #expect(cleaned(input, by: sut) == input)
    }

    @Test("preserves every reported adjective mention and still follows a spoken line break command")
    func preservesIssue2458AcceptanceCases() {
        let mentions = [
            "our best new line got a laugh",
            "her last new line, honestly, flopped",
            "that final new paragraph needs work",
            "the opening new line got applause",
            "her next new paragraph starts badly",
            "a great new line got a laugh",
            "the funniest new line was hers",
        ]
        for input in mentions {
            #expect(cleaned(input, by: sut) == input)
        }
        #expect(cleaned("write the date new line then sign it", by: sut) == "write the date\nthen sign it")
    }

    @Test(
        "leaves a layout phrase opened by a plural determiner",
        arguments: [
            "strip those new line characters from the file",
            "remove these new line breaks",
            "delete those new paragraph markers",
        ]
    )
    func leavesPluralDeterminerMentions(input: String) {
        #expect(cleaned(input, by: sut) == input)
    }

    @Test(
        "still lays out commands and phrases whose nearest opener heads a noun before it",
        arguments: [
            ("we need eggs new line milk", "we need eggs\nmilk"),
            ("write the date new line then sign it", "write the date\nthen sign it"),
            ("retry the request new line log the failure", "retry the request\nlog the failure"),
            (
                "thanks for the update new paragraph the second issue",
                "thanks for the update\n\nthe second issue"
            ),
        ]
    )
    func laysOutAfterANoun(input: String, expected: String) {
        #expect(cleaned(input, by: sut) == expected)
    }

    /// Issue 238: a numbered item inside its sentence is laid out only when an item numbered next to it is said too.
    @Test(
        "leaves a lone number inside its sentence as the designator it is",
        arguments: [
            "ring number 5 now", "call number 5 please", "check number 7 again",
            "shopping list number three call the bank", "we need number twenty one more of them",
            "room number 5 is free and so is room number 7", "take bus number twelve to the station",
            "check number 9223372036854775807 again",
        ]
    )
    func leavesALoneDesignator(input: String) {
        #expect(cleaned(input, by: sut) == input)
    }

    @Test(
        "keeps boundary and unparseable numbers as ordinary text",
        arguments: [
            "check number 9223372036854775806 again",
            "check number 0 again",
            "check number 9223372036854775808 again",
        ]
    )
    func keepsBoundaryNumbers(input: String) {
        #expect(cleaned(input, by: sut) == input)
    }

    @Test(
        "leaves a number word that opens no item",
        arguments: [
            "run number zero was the baseline",
            "watch number crunching happen here",
        ]
    )
    func leavesNonItems(input: String) {
        #expect(cleaned(input, by: sut) == input)
    }

    @Test(
        "does not turn spoken layout phrases into marks when the destination has no list layout",
        arguments: [
            LayoutPolicy.preserveNewlines, LayoutPolicy.paragraphs,
        ]
    )
    func respectsLayoutPolicy(layout: LayoutPolicy) {
        let pass = LayoutWordsPass(layout: layout)
        let input = "number one buy milk number two walk the dog"
        #expect(cleaned(input, by: pass) == input)
        #expect(cleaned("we need bullet point milk", by: pass) == "we need bullet point milk")
        #expect(cleaned("first line new line second line", by: pass) == "first line\nsecond line")
    }

    @Test("records the layout mark as a replacement and the second word as removed")
    func provenance() {
        let draft = sut.apply(Draft(text: "one new line two"))
        #expect(draft.words[1].state == .replaced(by: LayoutWordsPass.id, from: "new"))
        #expect(draft.words[2].state == .removed(by: LayoutWordsPass.id))
        #expect(draft.words[1].isLayoutMark)
    }

    @Test("records the item mark as a replacement of number and removes every word of the number said")
    func numberingProvenance() {
        let draft = sut.apply(Draft(text: "milk number twenty one eggs number twenty two bread"))
        #expect(draft.words[1].state == .replaced(by: LayoutWordsPass.id, from: "number"))
        #expect(draft.words[2].state == .removed(by: LayoutWordsPass.id))
        #expect(draft.words[3].state == .removed(by: LayoutWordsPass.id))
        #expect(draft.words[1].isLayoutMark && draft.words[1].isListMark)
    }

    private static let oneLine = LayoutWordsPass(layout: .singleLine)

    @Test(
        "writes a spoken list in a one-line field as one line kept apart by the list separator",
        arguments: [
            ("bullet point red bullet point green", "red, green"),
            ("bullet point red bullet point green bullet point blue", "red, green, blue"),
            ("number one milk number two eggs", "milk, eggs"),
            ("tags new line draft new line review", "tags, draft, review"),
            ("draft new paragraph review", "draft, review"),
            ("urgent blank line later", "urgent, later"),
            ("bullet point red next point green", "red, green"),
            ("we need bullet point milk bullet point eggs", "we need, milk, eggs"),
            ("bullet point paris, france bullet point rome", "paris, france; rome"),
            ("first. new line second", "first. second"),
        ]
    )
    func oneLineList(input: String, expected: String) {
        #expect(cleaned(input, by: Self.oneLine) == expected)
    }

    @Test(
        "leaves the list words alone in a one-line field when they are not a list",
        arguments: [
            "the bullet point was too long", "number one is broken", "red",
            "she drew a new line on the map", "my number one priority", "the next point matters",
        ]
    )
    func oneLineNonList(input: String) {
        #expect(cleaned(input, by: Self.oneLine) == input)
    }
    @Test(
        "writes a numbered list after a heading through the shipped pipeline",
        arguments: [
            (
                "the agenda number one budget number two hiring number three travel",
                "The agenda\n1. Budget\n2. Hiring\n3. Travel"
            ),
            (
                "agenda new line number one budget new line number two hiring",
                "Agenda\n\n1. Budget\n\n2. Hiring"
            ),
            (
                "steps new line number one open the app new line number two tap settings"
                    + " new line number three sign out",
                "Steps\n\n1. Open the app\n\n2. Tap settings\n\n3. Sign out"
            ),
            (
                "agenda colon new line number one budget review new line number two hiring plan",
                "Agenda:\n\n1. Budget review\n\n2. Hiring plan"
            ),
        ]
    )
    func listsAfterHeadingThroughPipeline(input: String, expected: String) {
        #expect(CleaningPipeline.standard.run(Draft(text: input)).text == expected)
    }
}
