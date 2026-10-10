import Testing
import UttrflowAI
import UttrflowCore

@Suite("Sentence boundaries use the piece seam evidence inside a piece")
struct SentenceBoundaryPassTests {
    private func cleaned(_ text: String) -> String {
        CleaningPipeline.standard(
            for: .standard(for: .document), situation: .unknown
        ).run(Draft(text: text)).text
    }

    @Test(
        "repairs the reported in-piece false stops",
        arguments: [
            ("We need the. Final version of the contract", "We need the final version of the contract."),
            ("My manager. Wants the slides by noon", "My manager wants the slides by noon."),
            ("I stayed home. Because it was raining", "I stayed home because it was raining."),
            ("I finished the report. And sent it to Maria", "I finished the report and sent it to Maria."),
            ("I wanted to come. But my train was cancelled", "I wanted to come, but my train was cancelled."),
            ("The shop was closed. So we went home", "The shop was closed, so we went home."),
            ("We can meet on Monday. Or on Tuesday", "We can meet on Monday or on Tuesday."),
        ])
    func repairsFalseStops(input: String, expected: String) {
        #expect(cleaned(input) == expected)
    }

    @Test(
        "repairs a stop after a word whose class leads into the next words",
        arguments: [
            (
                "We can ship it without any. Changes to the plan",
                "We can ship it without any changes to the plan."
            ),
            ("We walked through. The old town at night", "We walked through the old town at night."),
            ("We met during. The lunch break", "We met during the lunch break."),
        ])
    func repairsStopAfterLeadingWord(input: String, expected: String) {
        #expect(cleaned(input) == expected)
    }

    @Test(
        "keeps a stop after a word that ends its sentence before a new clause",
        arguments: [
            (
                "A wide path will let a wheelbarrow through. The beds can stay as grass",
                "A wide path will let a wheelbarrow through. The beds can stay as grass."
            ),
            ("I know that. She left early", "I know that. She left early."),
            ("I want some. The shop is closed", "I want some. The shop is closed."),
        ])
    func keepsStopAfterSentenceEnd(input: String, expected: String) {
        #expect(cleaned(input) == expected)
    }

    @Test("keeps a subject-bearing independent sentence after the stop")
    func keepsIndependentSentence() {
        #expect(cleaned("I left. She arrived") == "I left. She arrived.")
    }

    @Test(
        "keeps the recogniser's stop before a subordinate clause that an imperative main clause completes",
        arguments: [
            (
                "Call me when you are outside and I will come down. if nobody answers leave it with the shop",
                "Call me when you are outside and I will come down. If nobody answers leave it with the shop."
            ),
            (
                "The keys are on the desk. if the door is locked ring the bell",
                "The keys are on the desk. If the door is locked ring the bell."
            ),
        ])
    func keepsStopBeforeConditionalWithImperative(input: String, expected: String) {
        #expect(cleaned(input) == expected)
    }

    @Test(
        "keeps a stop before a lowercase word when the preceding words can end a sentence",
        arguments: [
            ("We shipped it. eBay is next", "We shipped it. eBay is next."),
            ("Please send it today. i will check tomorrow", "Please send it today. I will check tomorrow."),
            ("The patient is stable. vitals are normal", "The patient is stable. Vitals are normal."),
            ("the server. crashed twice last night", "The server. Crashed twice last night."),
            ("The price is five dollars. that is cheap", "The price is 5 dollars. That is cheap."),
            ("He is here. she is not", "He is here. She is not."),
            ("Yes. no. maybe", "Yes. No. Maybe."),
        ]
    )
    func keepsCompleteSentencesBeforeLowercaseWords(input: String, expected: String) {
        #expect(cleaned(input) == expected)
    }

    @Test(
        "preserves full stops that belong to abbreviations before lowercase words",
        arguments: [
            ("Meet me at 9 a.m. sharp.", "Meet me at 9 am sharp."),
            ("Call me at 5 p.m. tomorrow.", "Call me at 5 pm tomorrow."),
            ("Use tools, e.g. a hammer.", "Use tools, e.g. a hammer."),
            ("That is, i.e. the main one.", "That is, i.e. the main one."),
            ("Apples vs. oranges is a fair fight.", "Apples vs. oranges is a fair fight."),
        ]
    )
    func keepsAbbreviationStops(input: String, expected: String) {
        #expect(cleaned(input) == expected)
    }

    @Test(
        "keeps stops after complete phrasal verbs",
        arguments: [
            ("Let us move on. The meeting is over", "Let us move on. The meeting is over."),
            ("Hold on. The page is loading", "Hold on. The page is loading."),
            ("Please sign up. The form is short", "Please sign up. The form is short."),
            ("We gave up. The team left", "We gave up. The team left."),
            ("Come in. The door is open", "Come in. The door is open."),
            ("Log in. The dashboard opens", "Log in. The dashboard opens."),
        ])
    func keepsPhrasalVerbStops(input: String, expected: String) {
        #expect(cleaned(input) == expected)
    }

    @Test("keeps a pronoun I and a known name capitalized when a false stop is removed")
    func keepsNameAndPronounCase() {
        #expect(
            cleaned("We finished the report. I sent it to Maria")
                == "We finished the report. I sent it to Maria.")
        #expect(cleaned("I sent it to. Paris yesterday") == "I sent it to Paris yesterday.")
        #expect(cleaned("We need the. Monday version") == "We need the Monday version.")
    }
}
