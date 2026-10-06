import Testing
import UttrflowCore

@testable import UttrflowAI

@Suite("FillersPass")
struct FillersPassTests {
    private let sut = FillersPass()

    @Test(
        "removes the sounds people make while thinking",
        arguments: [
            ("um hello there", "hello there"),
            ("hello uh there", "hello there"),
            ("er hello", "hello"),
            ("hello there hmm", "hello there"),
            ("Um, hello", "hello"),
            ("uh um er hello", "hello"),
            ("aah ahh mhm okay", "okay"),
            ("hmm? yes", "yes"),
        ]
    )
    func removesFillers(input: String, expected: String) {
        #expect(cleaned(input, by: sut) == expected)
    }

    @Test("removes fillers joined to neighboring words by an ellipsis")
    func removesEllipsisJoinedFillers() {
        #expect(
            cleaned("Ah...the...um...the invoice is...ah...overdue", by: sut)
                == "the...the invoice is...overdue")
        #expect(cleaned("e.g. uh...hello", by: sut) == "e.g. hello")
        #expect(
            cleaned("https://example.com/uh...hello", by: sut)
                == "https://example.com/uh...hello")
    }

    @Test(
        "joins fixed assent and alarm replies",
        arguments: [
            ("uh huh", "Uh-huh"),
            ("uh huh sounds good", "Uh-huh sounds good"),
            ("uh oh", "Uh-oh"),
            ("mm hmm", "Mm-hmm"),
        ]
    )
    func joinsInterjections(input: String, expected: String) {
        #expect(cleaned(input, by: sut) == expected)
    }

    @Test("keeps hmm and mhm when they are the whole reply")
    func keepsStandaloneReplies() {
        #expect(cleaned("hmm", by: sut) == "hmm")
        #expect(cleaned("mhm", by: sut) == "mhm")
        #expect(cleaned("hello there hmm", by: sut) == "hello there")
        #expect(cleaned("hello there mhm", by: sut) == "hello there")
    }

    @Test(
        "keeps words that only sometimes act as filler",
        arguments: [
            "I would like a coffee",
            "well done everyone",
            "so the answer is four",
            "you know the answer",
            "basically that is a hard problem",
            "the umbrella is in the hall",
            "uh-oh",
            "um2 is a label",
            // "mm" is millimetres, and "MM" is millions.
            "the gap is three mm",
            "revenue of 4 MM",
        ]
    )
    func keepsAmbiguousWords(input: String) {
        #expect(cleaned(input, by: sut) == input)
    }

    @Test(
        "keeps a filler when the sentence names it",
        arguments: [
            "The word ah is an interjection", "Write the sound ah in the field", "Say an mhm when you agree",
            "Type the word er into the box", "Spell um after the greeting", "She said ‘uh’ yesterday",
            "Write ‘um’ in quotes after hello",
        ]
    )
    func keepsNamedFillers(input: String) {
        #expect(cleaned(input, by: sut) == input)
    }

    @Test(
        "removes a hesitation after a verb that could name it",
        arguments: [
            ("he said um I think it is fine", "he said I think it is fine"),
            ("I would say uh maybe next week", "I would say maybe next week"),
            ("let me write uh a quick note", "let me write a quick note"),
        ]
    )
    func removesHesitationAfterNamingVerb(input: String, expected: String) {
        #expect(cleaned(input, by: sut) == expected)
    }

    @Test("removes a filler not being named")
    func removesUnnamedFiller() {
        #expect(cleaned("I, um, think so", by: sut) == "I think so")
    }

    /// A determiner before it says the token is a noun, which is what tells "the ER" from a hesitation.
    @Test(
        "keeps a word a determiner opens, however it is spelled",
        arguments: [
            "I took her to the ER", "an ER visit ran long", "her ER shift",
            "we waited in the ER for hours",
            // An interior mark is part of the word, so this is not the filler spelling at all.
            "I took her to the E.R.",
        ]
    )
    func keepsANounADeterminerOpens(input: String) {
        #expect(cleaned(input, by: sut) == input)
    }

    /// The guard reads one word back, so a filler that opens the text has nothing to be mentioned by.
    @Test("still removes a filler with no determiner before it")
    func removesAFillerWithNoDeterminer() {
        #expect(cleaned("Er, I think so", by: sut) == "I think so")
        #expect(cleaned("we waited er for hours", by: sut) == "we waited for hours")
    }

    @Test(
        "removes um and uh after determiners while keeping a determiner-led er noun",
        arguments: [
            ("check the uh logs", "check the logs"),
            // The repeated "the" is RepeatedPhrasePass's to remove, not this pass's.
            ("the uh the database is down", "the the database is down"),
            ("the er ward is full", "the er ward is full"),
        ]
    )
    func removesFillerSoundsAndKeepsErNoun(input: String, expected: String) {
        #expect(cleaned(input, by: sut) == expected)
    }

    @Test(
        "keeps ER when it is a noun after a determiner or a common noun cue",
        arguments: [
            ("the ER is full", "the ER is full"),
            ("take me to the ER now", "take me to the ER now"),
            ("the er ward is full", "the er ward is full"),
        ]
    )
    func keepsNounSpelledLikeFiller(input: String, expected: String) {
        #expect(cleaned(input, by: sut) == expected)
    }

    @Test("records which pass removed the word")
    func provenance() {
        let draft = sut.apply(Draft(text: "um hello"))
        #expect(draft.words[0].state == .removed(by: FillersPass.id))
        #expect(draft.words[1].state == .kept)
        #expect(draft.originalText == "um hello")
    }

    /// The recogniser hangs the sentence's mark on the last word it heard, and that can be the filler.
    @Test(
        "keeps the mark the recogniser hung on a trailing filler",
        arguments: [
            ("so are we shipping today, uh?", "so are we shipping today?"),
            ("are we shipping today uh?", "are we shipping today?"),
            ("that is amazing uh!", "that is amazing!"),
            ("no way um!", "no way!"),
            // Nothing stands before it, so there is nowhere for the mark to go.
            ("hmm? yes", "yes"),
        ]
    )
    func keepsTheMarkOnATrailingFiller(input: String, expected: String) {
        #expect(cleaned(input, by: sut) == expected)
    }

    /// Found by dictating it: "we should, uh, ship" left a comma separating nothing.
    @Test(
        "takes the comma that only bracketed the filler",
        arguments: [
            ("we should, uh, ship it", "we should ship it"),
            ("the build, um, failed", "the build failed"),
            // Only a bracketed one: a comma doing its own work stays.
            ("first, uh second", "first, second"),
            ("So um, I think we should", "So I think we should"),
        ]
    )
    func dropsTheBracketingComma(input: String, expected: String) {
        #expect(cleaned(input, by: sut) == expected)
    }

    /// The recogniser marks the hesitation's pause with an ellipsis or a stop, which is not the sentence ending.
    @Test(
        "takes the pause a filler was written with, not a sentence end",
        arguments: [
            ("I think we should um... move the meeting.", "I think we should move the meeting."),
            ("I think we should um\u{2026} move the meeting.", "I think we should move the meeting."),
            ("The problem is um. We don't have enough time.", "The problem is we don't have enough time."),
            ("Let's um. Order pizza for the team.", "Let's order pizza for the team."),
            ("We are going to... Um. Ship it next week.", "We are going to... ship it next week."),
            ("we are done um. next item", "we are done next item"),
            ("Send it to um. The team", "Send it to the team"),
            ("Let's um. I think go", "Let's I think go"),
        ]
    )
    func takesThePause(input: String, expected: String) {
        #expect(cleaned(input, by: sut) == expected)
    }

    @Test(
        "keeps a full stop that ends the sentence the filler trailed",
        arguments: [
            ("we are done um. Next item", "we are done. Next item"),
            ("Okay. Um. So we go", "Okay. So we go"),
            ("I sent it um. Then I left", "I sent it. Then I left"),
            ("it works um...? right", "it works? right"),
        ]
    )
    func keepsASentenceEnd(input: String, expected: String) {
        #expect(cleaned(input, by: sut) == expected)
    }
}
