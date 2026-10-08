import Testing
import UttrflowCore

@testable import UttrflowAI

@Suite("SelfCorrectionPass")
struct SelfCorrectionPassTests {
    private let sut = SelfCorrectionPass()

    @Test(
        "removes only a bare-hyphen cut-off when the next word completes it",
        arguments: [
            ("th- the build passed", "the build passed"),
            ("w- we are late", "we are late"),
            ("I- I think so", "I think so"),
            ("s- we are late", "s- we are late"),
            ("I was go- I went to the store", "I was I went to the store"),
            ("a well-known bug", "a well-known bug"),
            ("send an e-mail and re-run it", "send an e-mail and re-run it"),
            ("say dash and keep going", "say dash and keep going"),
        ]
    )
    func removesBareHyphenCutOff(input: String, expected: String) {
        #expect(cleaned(input, by: sut) == expected)
    }

    @Test(
        "replaces a restated phrase with its restatement",
        arguments: [
            ("let's meet at four no sorry at five on tuesday", "let's meet at five on tuesday"),
            ("send it on tuesday I mean on wednesday", "send it on wednesday"),
            ("the red one scratch that the blue one", "the blue one"),
            ("the blue sorry green", "the green"),
            ("the blue, actually green", "the green"),
            ("the red, no blue", "the blue"),
            ("meet on Friday scratch that Thursday", "meet on Thursday"),
            ("at four never mind at five", "at five"),
            ("at four wait sorry at five", "at five"),
            ("at four no wait at five", "at five"),
            ("chaar baje nahi nahi paanch baje", "paanch baje"),
            ("chaar baje mera matlab, paanch baje", "paanch baje"),
            ("call me no call me later", "call me later"),
            ("send the file to sam actually send the file to priya", "send the file to priya"),
            ("book a table for two i mean book a table for four", "book a table for four"),
            ("open the red folder sorry open the blue folder", "open the blue folder"),
            ("call the plumber no wait call the electrician", "call the electrician"),
            ("add milk i mean add sugar", "add sugar"),
            ("tell sam scratch that tell priya to join", "tell priya to join"),
            ("at four, no sorry, at five", "at five"),
            ("put it on the table no sorry on the shelf", "put it on the shelf"),
            ("at four no sorry at five I mean at six", "at six"),
            (
                "I'll bring the cake and the drinks no wait and the plates",
                "I'll bring the cake and the plates"
            ),
            (
                "git push dash dash force no wait dash dash force dash with dash lease",
                "git push dash dash force dash with dash lease"
            ),
        ]
    )
    func replacesRestatement(input: String, expected: String) {
        #expect(cleaned(input, by: sut) == expected)
    }

    @Test(
        "keeps ordinary actually and no between content words",
        arguments: [
            "the weather actually improved overnight",
            "sales actually grew last quarter",
            "the server actually crashed again",
            "the team actually shipped the release",
            "she gave no reason",
            "he said no thanks to the offer",
        ]
    )
    func keepsOrdinaryActuallyAndNo(input: String) {
        #expect(cleaned(input, by: sut) == input)
    }

    @Test(
        "keeps both halves when the word after a trigger cannot take the place of the word before it",
        arguments: [
            "it works i mean sometimes",
            "he is a nice guy i mean really nice",
            "she is on leave i mean please call me back",
            "the budget is approved i mean please call me back",
            "i will send the draft today i mean thanks",
        ]
    )
    func keepsQualifyingTrigger(input: String) {
        #expect(cleaned(input, by: sut) == input)
    }

    @Test(
        "replaces one word with a word of the same class after a trigger",
        arguments: [
            ("send it today i mean tomorrow", "send it tomorrow"),
            ("the app crashed i mean froze", "the app froze"),
            ("she is on leave i mean holiday", "she is on holiday"),
            ("it is red i mean blue", "it is blue"),
        ]
    )
    func replacesSameClassWord(input: String, expected: String) {
        #expect(cleaned(input, by: sut) == expected)
    }

    @Test("does not treat ordinary Hindi negation as a correction")
    func keepsHindiNegation() {
        #expect(cleaned("nahi aaunga", by: sut) == "nahi aaunga")
        #expect(cleaned("main nahi nahi aaunga", by: sut) == "main nahi nahi aaunga")
        #expect(
            cleaned("chaar baje mera matlab paanch baje", by: sut) == "chaar baje mera matlab paanch baje")
    }

    /// The comma before the trigger went with the discarded half, so its partner after the restatement separates nothing.
    @Test(
        "drops the comma that closed a correction set off by commas",
        arguments: [
            (
                "Send the file to Alex, I mean to Sam, before lunch.",
                "Send the file to Sam before lunch."
            ),
            (
                "Book a table for six, actually eight, at the usual place.",
                "Book a table for eight at the usual place."
            ),
            ("We need six, no sorry, eight, chairs.", "We need eight chairs."),
        ]
    )
    func dropsTheClosingComma(input: String, expected: String) {
        #expect(cleaned(input, by: sut) == expected)
    }

    @Test(
        "keeps a comma the sentence needs after the restatement",
        arguments: [
            // The comma closes the clause "if" opened, which the correction sat inside.
            (
                "If it's six, actually eight, we need more chairs.",
                "If it's eight, we need more chairs."
            ),
            // Nothing set the correction off, so the comma after it is the speaker's own.
            (
                "Send the file to Alex I mean to Sam, then call me.",
                "Send the file to Sam, then call me."
            ),
            // A comma past the restatement belongs to the next clause, not to the correction.
            (
                "Send it to Alex, I mean to Sam today, and call me.",
                "Send it to Sam today, and call me."
            ),
            // A sentence that ends on the restatement keeps its full stop.
            ("Book a table for six, actually eight.", "Book a table for eight."),
            // A comma already closed the opening clause, so the one after the restatement is stray again.
            (
                "If it rains, bring six, actually eight, umbrellas.",
                "If it rains, bring eight umbrellas."
            ),
        ]
    )
    func keepsANeededComma(input: String, expected: String) {
        #expect(cleaned(input, by: sut) == expected)
    }

    @Test(
        "replaces a number with the number said after the trigger",
        arguments: [
            ("coffee at 2 actually 3", "coffee at 3"),
            ("coffee at two actually three", "coffee at three"),
            ("call at two thirty actually three", "call at three"),
            ("I have two no three cats", "I have three cats"),
        ]
    )
    func replacesNumber(input: String, expected: String) {
        #expect(cleaned(input, by: sut) == expected)
    }

    @Test(
        "takes back the sign of an amount along with its number",
        arguments: [
            ("The total is $40, no wait, $50.", "The total is $50."),
            ("The total is $40 no wait $50.", "The total is $50."),
            ("It costs $5 sorry $6.", "It costs $6."),
            ("It costs \u{00A3}5 sorry \u{00A3}6.", "It costs \u{00A3}6."),
            ("The fee is 40% actually 50%.", "The fee is 50%."),
        ]
    )
    func takesBackAnAmountsSign(input: String, expected: String) {
        #expect(cleaned(input, by: sut) == expected)
    }

    @Test(
        "applies a correction whose trigger the recogniser wrote as its own sentence",
        arguments: [
            ("The total is 40. No wait. 50.", "The total is 50."),
            ("Meet me at four. Scratch that. At five.", "Meet me at five."),
            ("Send it on Tuesday. Sorry. On Wednesday.", "Send it on Wednesday."),
            ("Call the office. I mean. Call the lab.", "Call the lab."),
        ]
    )
    func readsThroughATriggerSentence(input: String, expected: String) {
        #expect(cleaned(input, by: sut) == expected)
    }

    @Test(
        "leaves a real sentence that opens with a trigger word",
        arguments: [
            "Did we ship? No. We shipped it.",
            "We shipped. No. We shipped it.",
            "Is it 3? No wait. 4.",
            "The code is 45. No. 46.",
        ]
    )
    func leavesARealSentenceAfterAStop(input: String) {
        #expect(cleaned(input, by: sut) == input)
    }

    @Test(
        "keeps a reported no before its following clause",
        arguments: [
            ("The vote was no, the board will not proceed", "The vote was no, the board will not proceed"),
            ("The exit code was no, the script did not run", "The exit code was no, the script did not run"),
            ("The result was no, the sample did not match", "The result was no, the sample did not match"),
            ("The status was no, the order is held", "The status was no, the order is held"),
            ("Tell her the vote is no, the plan stays", "Tell her the vote is no, the plan stays"),
        ]
    )
    func keepsReportedNo(input: String, expected: String) {
        #expect(cleaned(input, by: sut) == expected)
    }

    /// A number anchor may not reach back through a full stop, because the number in the sentence before was not the one corrected. See `Docs/cleanup.md`.
    @Test(
        "leaves a number the speaker said in the sentence before the correction",
        arguments: [
            "the meeting is at 3. no 4 people confirmed",
            "the meeting is at three. no four people confirmed",
            "the meeting is at 3! no 4 people confirmed",
            "the meeting is at 3? no 4 people confirmed",
            "the code is 4 5. no 6",
            "call at 2:30. no 3",
            "room 5. actually 6",
        ]
    )
    func leavesNumbersBeforeASentenceEnd(input: String) {
        #expect(cleaned(input, by: sut) == input)
    }

    /// The correction still runs inside its own sentence, reaching back only as far as the stop.
    @Test(
        "corrects the number in this sentence without taking the one in the last",
        arguments: [
            ("the code is 4. 5 no 6", "the code is 4. 6"),
            ("we booked 7. 8 actually 9", "we booked 7. 9"),
        ]
    )
    func correctsWithinTheSentence(input: String, expected: String) {
        #expect(cleaned(input, by: sut) == expected)
    }

    @Test(
        "leaves everything, trigger included, when the halves do not match",
        arguments: [
            "no I don't think so",
            "I actually enjoyed it",
            "sorry I'm late",
            "I mean it",
            "the meeting is at four actually",
            "I can't come to the party no I have to work",
            "meet at four. no at five",
            "at noon we will send the report to them no sorry at one",
            "the meeting is at four I mean it's at five",
            "wait for me",
            // "wait" alone is a verb far more often than a trigger, so it needs "no" or "sorry" beside it.
            "at four wait at five",
            "grab a coffee and wait a moment",
            "we need to wait to finish the review",
        ]
    )
    func leavesUnmatched(input: String) {
        #expect(cleaned(input, by: sut) == input)
    }

    /// A contracted pronoun heads a fresh clause as the pronoun does, so it cannot anchor a correction either.
    @Test(
        "leaves a clause that opens on a contracted pronoun",
        arguments: [
            "he's in the kitchen, actually, he's cooking dinner",
            "we're late, sorry, we're stuck in traffic",
            "you're right, actually, you're always right",
            "they'll call, I mean, they'll call if it rains",
            "she\u{2019}s at home, actually, she\u{2019}s working",
            "that's fine, sorry, that's what I meant",
            "he is in the kitchen, actually, he is cooking",
            "I'll drive, sorry, I'll take the train",
        ]
    )
    func leavesContractedPronounClauses(input: String) {
        #expect(cleaned(input, by: sut) == input)
    }

    /// A Hindi pronoun heads a fresh clause as an English one does, so it cannot anchor a correction.
    @Test(
        "leaves a Hinglish apology and the clause before it",
        arguments: [
            "main late hoon sorry main abhi aata hoon",
            "मैं late हूँ sorry मैं अभी आता हूँ",
            "wo nahi aa raha actually wo kal aayega",
            "hum ready hain sorry hum thoda late honge",
        ]
    )
    func leavesHinglishClauses(input: String) {
        #expect(cleaned(input, by: sut) == input)
    }

    /// Only a trigger phrase marks a correction; a phrase said twice over is a list far more often. See `Docs/cleanup.md`.
    @Test(
        "leaves a phrase repeated with no trigger exactly as it was said",
        arguments: [
            "I'll pay for lunch for everyone",
            "coffee with milk with sugar",
            "the meeting is on Monday on Zoom",
            "I wanted to buy a record as a gift as a present",
            "let's meet on tuesday on wednesday afternoon",
            "send it to the office in london in paris",
            "I like tea I like coffee both are fine",
            "she said she said nothing of the sort",
            "as soon as possible we should ship",
            "the good the bad and the ugly",
        ]
    )
    func leavesUntriggeredRepeats(input: String) {
        #expect(cleaned(input, by: sut) == input)
    }

    @Test(
        "a numeric restart cannot discard a unit when the quantities do not match",
        arguments: [
            "ten apples actually twelve pears", "ten boxes no twelve",
            "we need ten boxes no twelve. boxes", "i counted ten. boxes no twelve boxes",
            "ten apples, actually twelve pears", "ten boxes, no twelve",
            "ten boxes sorry twelve", "ten apples i mean twelve pears",
            "boxes no wait twelve boxes", "i counted ten. boxes sorry twelve boxes",
            "we need ten boxes i mean twelve. boxes", "say sorry 3 sorry 4",
        ]
    )
    func preservesUnmatchedNumberCorrection(input: String) {
        #expect(cleaned(input, by: sut) == input)
    }

    /// A trigger heading a repeated frame coordinates a list, and the first item is not a discarded half. See `Docs/cleanup.md`.
    @Test(
        "leaves a coordinated list whose items are headed by the trigger word itself",
        arguments: [
            "I said no to the offer, no to the meeting",
            "say sorry to John, sorry to Marcy too",
            "say no to the offer no to the meeting",
            "there's no room, no room at all",
            "say no 3 no 4",
            "the bus is no 7 no 8",
        ]
    )
    func leavesTriggerHeadedLists(input: String) {
        #expect(cleaned(input, by: sut) == input)
    }

    /// One answer answering another is a pair of items, and taking the first back inverts what was said. See `Docs/cleanup.md`.
    @Test(
        "leaves a pair whose items are headed by different answers",
        arguments: [
            "I said yes to the offer no to the meeting",
            "say thanks to John sorry to Marcy too",
        ]
    )
    func leavesAnsweredPairs(input: String) {
        #expect(cleaned(input, by: sut) == input)
    }

    @Test(
        "never reaches back across a spoken line or paragraph break",
        .bug(id: 6563),
        arguments: [
            "over fifty m b new paragraph no schema changes and no new dependencies",
            "the old build new line the build is green and no new warnings",
        ]
    )
    func stopsAtSpokenLayout(input: String) {
        #expect(cleaned(input, by: sut) == input)
    }

    @Test("records the discarded half and the trigger as removed by this pass")
    func provenance() {
        let draft = sut.apply(Draft(text: "at four no sorry at five"))
        #expect(draft.words.map(\.isPresent) == [false, false, false, false, true, true])
        #expect(draft.removed.allSatisfy { $0.state == .removed(by: SelfCorrectionPass.id) })
        #expect(draft.originalText == "at four no sorry at five")
    }
}
