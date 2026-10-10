import Testing

@testable import UttrflowAI
import UttrflowCore

/// `MeaningPreservationGuard` reads spoken numbers through `UttrflowCore.NumberWords`, scales composed.
@Suite("GuardNumberWords")
struct GuardNumberWordsTests {
    /// With the numbers step switched off the draft keeps "six hundred", and the guard still reads it as 600.
    @Test("a composed number survives the guard when the numbers step is off")
    func composedNumberWithTheNumbersStepOff() {
        let draft = CleaningPipeline.beforeModel(
            for: .standard(for: .plain), situation: .unknown,
            steps: CleaningSteps(switchedOff: [.numberForms])
        )
        .run(Draft(text: "we raised six hundred rupees")).text
        #expect(draft == "we raised six hundred rupees")
        let verdict = MeaningPreservationGuard()
            .verdict(original: draft, rewritten: "We raised 600 rupees.")
        #expect(verdict == .accepted)
    }

    /// Every scale the core table composes is a number the guard accepts the numeral for.
    @Test("the guard reads every scale the core table composes")
    func everyScaleTheCoreTableComposes() {
        let guardUnderTest = MeaningPreservationGuard()
        #expect(
            guardUnderTest.verdict(
                original: "we sold two million units", rewritten: "We sold 2,000,000 units.") == .accepted)
        #expect(
            guardUnderTest.verdict(
                original: "we raised three thousand rupees", rewritten: "We raised 3,000 rupees.")
                == .accepted)
    }

    @Test("a spoken ordinal survives as the ordinal numeral, and a different day is still refused")
    func spokenOrdinalSurvivesAsItsNumeral() {
        let guardUnderTest = MeaningPreservationGuard()
        #expect(
            guardUnderTest.verdict(
                original: "the electrician needs access on the twelfth",
                rewritten: "The electrician needs access on the 12th.") == .accepted)
        #expect(
            guardUnderTest.verdict(
                original: "the electrician needs access on the twelfth",
                rewritten: "The electrician needs access on the 13th.") != .accepted)
    }

    /// Every word the guard reads as a number comes from `NumberWords`, so a key added only here fails.
    @Test("the guard's number words are exactly NumberWords, English and Hindi")
    func numberWordsHaveOneHome() {
        let expected = NumberWords.english.merging(NumberWords.hindi) { first, _ in first }.mapValues(
            String.init)
        #expect(MeaningPreservationGuard.numberWords == expected)
    }

    /// A model that turns a relative clock phrase into a clock time states a number nobody said, and is refused.
    @Test(
        "a relative clock phrase rewritten as a clock time is refused",
        arguments: [
            ("meet at half past two", "Meet at 2:30."),
            ("leave at quarter to six", "Leave at 5:45."),
            ("it is twenty past four", "It is 4:20."),
        ]
    )
    func relativeClockPhraseAsClockTime(original: String, rewritten: String) {
        #expect(MeaningPreservationGuard().verdict(original: original, rewritten: rewritten) != .accepted)
    }

    /// A spoken unit word is the speaker's word, so a rewrite that swaps it for its symbol is refused.
    @Test(
        "a unit word rewritten as its symbol is refused",
        arguments: [
            ("we ran 10 kilometres", "We ran 10 km."),
            ("add 5 millilitres", "Add 5 ml."),
            ("the file is 3 gigabytes", "The file is 3 GB."),
        ]
    )
    func unitWordAsSymbol(original: String, rewritten: String) {
        let verdict = MeaningPreservationGuard().verdict(draft: Draft(text: original), rewritten: rewritten)
        #expect(verdict != .accepted)
    }

    /// A symbol the speaker spelled is already in the draft, so the model keeping it is accepted.
    @Test("a unit symbol already in the draft survives the guard")
    func unitSymbolKept() {
        #expect(
            MeaningPreservationGuard().verdict(draft: Draft(text: "we ran 10 km"), rewritten: "We ran 10 km.")
                == .accepted)
    }

    /// The scales above a thousand are the only words the guard gained when its own table went.
    @Test("a million spoken and a million written are the same number to the guard")
    func millionIsANumber() {
        #expect(MeaningPreservationGuard.numberWords["million"] == "1000000")
        #expect(
            MeaningPreservationGuard.inventedNumber(
                original: "one million rows", rewritten: "one million rows") == nil)
    }

    /// A rewrite that swaps one Hindi quantity for another changes the stated quantity, and is refused.
    @Test(
        "a changed Hindi quantity is refused",
        arguments: [
            ("kal sattar log aaye", "Kal assi log aaye."),
            ("dedh ghante baad milte hain", "Dhai ghante baad milte hain."),
            ("paanch lakh rupaye bheje", "Paanch hazaar rupaye bheje."),
        ]
    )
    func changedHindiQuantity(original: String, rewritten: String) {
        #expect(MeaningPreservationGuard().verdict(original: original, rewritten: rewritten) != .accepted)
    }

    @Test(
        "the guard reads a composed Hindi amount and refuses a changed one",
        arguments: [
            ("paanch sau rupaye de do", "500 rupaye de do", true),
            ("do hazaar paanch sau rupaye", "2500 rupaye", true),
            ("ek lakh rupaye", "1,00,000 rupaye", true),
            ("paanch sau rupaye de do", "5000 rupaye de do", false),
            ("do hazaar rupaye", "200 rupaye", false),
        ]
    )
    func composedHindiAmount(original: String, rewritten: String, accepted: Bool) {
        let verdict = MeaningPreservationGuard().verdict(original: original, rewritten: rewritten)
        #expect((verdict == .accepted) == accepted)
    }

    /// A magnitude is part of the amount, so "50K", "50 thousand" and "50,000" are one value and a changed magnitude is not.
    @Test(
        "the guard compares an amount's value across magnitude spellings",
        arguments: [
            ("the budget is 50K", "The budget is 50,000.", true),
            ("the budget is 50000", "The budget is 50K.", true),
            ("we sold 5 million units", "We sold 5,000,000 units.", true),
            ("we raised $2.5M", "We raised $2,500,000.", true),
            ("they spent 3bn", "They spent 3 billion.", true),
            ("2 lakh rupaye bheje", "2,00,000 rupaye bheje.", true),
            ("the budget is 50K", "The budget is 50.", false),
            ("the budget is 50K", "The budget is 50M.", false),
            ("we sold 5 million units", "We sold 5 thousand units.", false),
            ("we raised $2.5M", "We raised $250,000.", false),
            ("the budget is 50000", "The budget is 5K.", false),
        ]
    )
    func magnitudeIsPartOfTheValue(original: String, rewritten: String, accepted: Bool) {
        let verdict = MeaningPreservationGuard().verdict(original: original, rewritten: rewritten)
        #expect((verdict == .accepted) == accepted)
    }

    /// An amount is compared by value, unit and ordinal, so a currency or percent said as a word and a spoken ordinal pass as their written forms, and a changed one does not.
    @Test(
        "the guard compares amounts by value across currency, percent and ordinal spellings",
        arguments: [
            ("it costs 5 dollars", "It costs $5.", true),
            ("it costs $5", "It costs 5 dollars.", true),
            ("it costs five dollars", "It costs $5.", true),
            ("it costs 12 euros", "It costs \u{20AC}12.", true),
            ("we paid 300 rupees", "We paid \u{20B9}300.", true),
            ("the ticket was 10 pounds", "The ticket was \u{00A3}10.", true),
            ("it was 100 yen", "It was \u{00A5}100.", true),
            ("it costs 1 euro", "It costs \u{20AC}1.", true),
            ("we sold 5 million units", "We sold 5,000,000 units.", true),
            ("the budget is 12,000", "The budget is 12K.", true),
            ("we raised 2.5 million dollars", "We raised $2.5M.", true),
            ("we raised $2.5 million", "We raised 2.5 million dollars.", true),
            ("she came 1st", "She came first.", true),
            ("she came first", "She came 1st.", true),
            ("the 2nd floor", "The second floor.", true),
            ("the electrician comes on the twelfth", "The electrician comes on the 12th.", true),
            ("on the twenty first", "On the 21st.", true),
            ("on the twenty-first", "On the 21st.", true),
            ("the thirty third visitor", "The 33rd visitor.", true),
            ("the fifty first visitor", "The 51st visitor.", true),
            ("the one hundred first visitor", "The 101st visitor.", true),
            ("twenty one people came first", "21 people came 1st.", true),
            ("it is 50 percent", "It is 50%.", true),
            ("it is 50%", "It is 50 percent.", true),
            ("it is 50 per cent", "It is 50%.", true),
            ("it is twelve percent", "It is 12%.", true),
            ("it rose 50 percent to 5 dollars", "It rose 50% to $5.", true),
            ("we paid five hundred rupees", "We paid \u{20B9}500.", true),
            ("it costs 2 euros", "It costs \u{20AC}2.", true),
            ("the forty second floor", "The 42nd floor.", true),
            ("it costs 5 dollars", "It costs $6.", false),
            ("it costs 5 dollars", "It costs \u{00A3}5.", false),
            ("it costs $5", "It costs 5 euros.", false),
            ("it costs 5 pounds", "It costs $5.", false),
            ("it costs 12 euros", "It costs $12.", false),
            ("we paid 300 rupees", "We paid \u{20B9}3,000.", false),
            ("it costs 1 euro", "It costs \u{20AC}2.", false),
            ("it costs $5", "It costs 5.", false),
            ("it costs $5", "It costs 5%.", false),
            ("the balance is 5 dollars", "The balance is -$5.", false),
            ("the budget is 12,000", "The budget is 1,200.", false),
            ("we sold 5 million units", "We sold 5 thousand units.", false),
            ("we raised $2.5M", "We raised $250,000.", false),
            ("she came 1st", "She came second.", false),
            ("she came first", "She came 2nd.", false),
            ("the 2nd floor", "The 3rd floor.", false),
            ("the electrician comes on the twelfth", "The electrician comes on the 13th.", false),
            ("on the twenty first", "On the 22nd.", false),
            ("the thirty third visitor", "The 34th visitor.", false),
            ("the fifty first visitor", "The 52nd visitor.", false),
            ("the one hundred first visitor", "The 102nd visitor.", false),
            ("twenty one people came", "22 people came.", false),
            ("it is 50 percent", "It is 5%.", false),
            ("it is 50 per cent", "It is 60%.", false),
            ("it is 50%", "It is 50.", false),
            ("it is 50 percent", "It is 50.", false),
            ("it is 50 percent", "It is 50 dollars.", false),
            ("it is twelve percent", "It is 21%.", false),
            ("the forty second floor", "The 43rd floor.", false),
            ("we paid five hundred rupees", "We paid \u{20B9}5,000.", false),
        ]
    )
    func valueAcrossUnitAndOrdinalSpellings(original: String, rewritten: String, accepted: Bool) {
        let verdict = MeaningPreservationGuard().verdict(original: original, rewritten: rewritten)
        #expect((verdict == .accepted) == accepted)
    }
}
