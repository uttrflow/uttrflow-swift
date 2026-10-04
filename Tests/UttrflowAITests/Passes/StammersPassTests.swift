import Testing
import UttrflowCore

@testable import UttrflowAI

@Suite("StammersPass")
struct StammersPassTests {
    private let sut = StammersPass()

    @Test(
        "removes the doubled short word a false start leaves behind",
        arguments: [
            ("the the deployment", "the deployment"),
            ("I I think so", "I think so"),
            ("The the plan", "The plan"),
            ("we we we should", "we should"),
            ("the build is is red", "the build is red"),
            ("do do you want it", "do you want it"),
        ]
    )
    func removesStammer(input: String, expected: String) {
        #expect(cleaned(input, by: sut) == expected)
    }

    @Test(
        "keeps a doubled letter name inside a spelled run",
        arguments: [
            ("a a one two three", "a a one two three"),
            ("b a a four", "b a a four"),
            ("i i t", "i i t"),
            ("code is x a a nine", "code is x a a nine"),
        ]
    )
    func keepsSpelledDouble(input: String, expected: String) {
        #expect(cleaned(input, by: sut) == expected)
    }

    @Test(
        "still removes a doubled a or I in prose",
        arguments: [
            ("I I think so", "I think so"),
            ("a a lot", "a lot"),
            ("it was a a thing", "it was a thing"),
            ("I I was there", "I was there"),
        ]
    )
    func removesProseDouble(input: String, expected: String) {
        #expect(cleaned(input, by: sut) == expected)
    }

    @Test(
        "removes a doubled Hindi or Hinglish grammar word",
        arguments: [
            ("ki ki baat", "ki baat"),
            ("haan hai hai", "haan hai"),
            ("mujh ko ko bolo", "mujh ko bolo"),
            ("ghar ke ke paas", "ghar ke paas"),
            ("kaam se se pehle", "kaam se pehle"),
            ("woh par par baitha", "woh par baitha"),
        ]
    )
    func removesHindiGrammarWordStammer(input: String, expected: String) {
        #expect(cleaned(input, by: sut) == expected)
    }

    /// "this" and "what" are function words, so the restart reading wins over the emphatic one by design.
    @Test(
        "still removes a doubled function word English also emphasises",
        arguments: [
            ("this this thing is broken", "this thing is broken"),
            ("what what did you say", "what did you say"),
        ]
    )
    func removesDoubledFunctionWordDespiteEmphaticReading(input: String, expected: String) {
        #expect(cleaned(input, by: sut) == expected)
    }

    /// A double English means is not a stammer, and taking a word out of one loses what was said.
    @Test(
        "keeps a double the language itself makes",
        arguments: [
            "I had had enough by then",
            "the thing that that person said",
            "bye bye for now",
            "no no no",
            "the soup was so so",
        ]
    )
    func keepsLegitimateDoubles(input: String) {
        #expect(cleaned(input, by: sut) == input)
    }

    /// A number said twice is two digits of one value, so taking one out changes the number.
    @Test(
        "keeps a repeated number word, which spells a digit rather than stammering",
        arguments: ["extension four four two", "port eight zero zero zero", "the code is one one one"]
    )
    func keepsRepeatedNumbers(input: String) {
        #expect(cleaned(input, by: sut) == input)
    }

    @Test(
        "keeps Hindi distributive do before a content word",
        arguments: [
            "sab ko do do laddoo diye",
            "do do roti khao",
            "do do kitaben lo",
        ]
    )
    func keepsHindiDistributiveDo(input: String) {
        #expect(cleaned(input, by: sut) == input)
    }

    @Test(
        "keeps a repeated long word, and a repeat split by punctuation",
        arguments: ["really really good", "had, had", "hello hello"]
    )
    func keepsRepeats(input: String) {
        #expect(cleaned(input, by: sut) == input)
    }

    /// English repeats a short word for emphasis as readily as a long one, and both halves were meant.
    @Test(
        "keeps a short word repeated for emphasis",
        arguments: [
            "this is very very important",
            "much much better",
            "okay okay I hear you",
            "hear hear",
            "chop chop",
        ]
    )
    func keepsEmphaticRepeat(input: String) {
        #expect(cleaned(input, by: sut) == input)
    }

    /// A doubled name loses half of itself to a removal, and no list of exceptions reaches every name.
    @Test(
        "keeps a doubled proper noun",
        arguments: ["we flew to Bora Bora last year", "the flight to Pago Pago"]
    )
    func keepsDoubledName(input: String) {
        #expect(cleaned(input, by: sut) == input)
    }

    /// A third copy is matched against the same stale previous word, so the run collapses to one token.
    @Test("keeps every copy of a word said three times for emphasis")
    func keepsTripledEmphasis() {
        #expect(cleaned("ha ha ha", by: sut) == "ha ha ha")
    }

    @Test("records which pass removed the word")
    func provenance() {
        let draft = sut.apply(Draft(text: "the the plan"))
        #expect(draft.words.map(\.state) == [.kept, .removed(by: StammersPass.id), .kept])
    }

    /// A doubled number is an accidental stammer when the next word is not another number, since "extension four four two" and "port eight zero zero zero" are digit-by-digit readings the rule has to keep.
    @Test(
        "removes a doubled number when the next word is not a number",
        arguments: [
            ("it costs five five dollars", "it costs five dollars"),
            ("there were three three people in the room", "there were three people in the room"),
            ("I waited five five minutes", "I waited five minutes"),
        ]
    )
    func removesDoubledNumberNotFollowedByNumber(input: String, expected: String) {
        #expect(cleaned(input, by: sut) == expected)
    }

    @Test(
        "keeps an ambiguous doubled number at either edge of a piece",
        arguments: ["two two", "my pin is two two", "two two four four"]
    )
    func keepsDoubledNumberAtPieceEdge(input: String) {
        #expect(cleaned(input, by: sut) == input)
    }

    /// A doubled number directly after "point" is a digit of the decimal, not a stammer.
    @Test(
        "keeps a doubled number directly after \"point\" so the decimal survives",
        arguments: [
            "apr is nineteen point nine nine percent",
            "the rate is three point five five percent",
            "the price is two point five five dollars",
            "we scored ninety nine point nine nine percent",
            "the interest is four point four four percent a year",
            "the area is twelve point two two square metres",
            "the dose is point five five milligrams",
        ]
    )
    func keepsDoubledNumberAfterPoint(input: String) {
        #expect(cleaned(input, by: sut) == input)
    }

    /// A word spoken in Devanagari is Hindi, so the English function-word list never reads its romanised spelling.
    @Test(
        "keeps a doubled word that was spoken in Devanagari",
        arguments: [
            ("वो दो दो", "wo do do"), ("मैं मैं", "main main"), ("तो तो चलो", "to to chalo"),
            ("वो थे थे", "wo the the"),
        ]
    )
    func keepsDevanagariDoubles(spoken: String, romanised: String) {
        let draft = sut.apply(Draft(romanising: Transcription(text: spoken)))
        #expect(draft.text == romanised)
    }
}
