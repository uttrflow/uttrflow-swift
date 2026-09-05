import Testing
import UttrflowCore

@testable import UttrflowAI

@Suite("NumberFormsPass")
struct NumberFormsPassTests {
    private let sut = NumberFormsPass()

    @Test(
        "writes a number from ten up as a numeral, with commas only from ten thousand",
        arguments: [
            ("about fifteen people", "about 15 people"),
            ("twenty one days", "21 days"),
            ("one hundred and five", "105"),
            ("nine thousand rupees", "9000 rupees"),
            ("fifteen thousand users", "15,000 users"),
            ("two million", "2,000,000"),
            ("nineteen hundred", "1900"),
            ("two thousand and five", "2005"),
            ("fifteen,", "15,"),
            ("\"twenty\"", "\"20\""),
            ("twenty, one", "20, one"),
        ]
    )
    func wholeNumbers(input: String, expected: String) {
        #expect(cleaned(input, by: sut) == expected)
    }

    /// A cell, a query and a line of code want the numeral; prose wants the word. See the design's §2 table.
    @Test(
        "writes every number as a numeral where the place asks for all of them",
        arguments: [
            ("one of them", "1 of them"),
            ("zero", "0"),
            ("two to three", "2 to 3"),
            ("about fifteen people", "about 15 people"),
            ("nine thousand rupees", "9000 rupees"),
        ]
    )
    func everyNumberAsANumeral(input: String, expected: String) {
        #expect(cleaned(input, by: NumberFormsPass(policy: .always)) == expected)
    }

    @Test("the place a dictation lands in decides how many of its numbers are numerals")
    func policyComesFromTheFormatter() {
        #expect(cleaned("one of them", by: NumberFormsPass(policy: .fromTen)) == "one of them")
        #expect(cleaned("one of them", by: NumberFormsPass()) == "one of them")
        #expect(NumberFormsPass(policy: .always).policy == .always)
    }

    @Test(
        "keeps a single digit as a word unless something makes it a number",
        arguments: [
            "one of them", "the one", "two to three", "zero", "a hundred", "hundred", "point five",
            "15 people",
        ]
    )
    func keepsWords(input: String) {
        #expect(cleaned(input, by: sut) == input)
    }

    @Test(
        "writes digits after a labelling word, run together and never grouped",
        arguments: [
            ("port eight thousand eighty", "port 8080"),
            ("port eighty eighty", "port 8080"),
            ("port fifty thousand", "port 50000"),
            ("version two point four point one", "version 2.4.1"),
            ("page two", "page 2"),
            ("step three", "step 3"),
            ("chapter one", "chapter 1"),
            ("extension four five six", "extension 456"),
            ("number one priority", "number 1 priority"),
            ("port 8080", "port 8080"),
        ]
    )
    func labelledNumbers(input: String, expected: String) {
        #expect(cleaned(input, by: sut) == expected)
    }

    @Test(
        "writes decimals, percentages and versions",
        arguments: [
            ("sixteen point two", "16.2"),
            ("two point five", "2.5"),
            ("three point one four", "3.14"),
            ("sixteen point twenty five", "16.25"),
            ("five percent", "5%"),
            ("twenty five per cent", "25%"),
            ("2.5 percent", "2.5%"),
            ("five percent.", "5%."),
            ("two point five percent", "2.5%"),
            ("one point is that", "one point is that"),
            ("sixteen point 2", "16.2"),
        ]
    )
    func decimals(input: String, expected: String) {
        #expect(cleaned(input, by: sut) == expected)
    }

    @Test(
        "writes times of day",
        arguments: [
            ("two thirty pm", "2:30 pm"),
            ("ten am", "10 am"),
            ("ten a.m.", "10 a.m."),
            ("two oh five pm", "2:05 pm"),
            ("five o'clock", "5 o'clock"),
            ("at four thirty", "at 4:30"),
            ("twelve fifteen pm", "12:15 pm"),
            ("2 thirty pm", "2:30 pm"),
            ("one thirty", "1:30"),
            ("two forty five pm", "2:45 pm"),
        ]
    )
    func times(input: String, expected: String) {
        #expect(cleaned(input, by: sut) == expected)
    }

    @Test(
        "writes years spoken in two halves",
        arguments: [
            ("twenty twenty four", "2024"),
            ("nineteen ninety nine", "1999"),
            ("twenty ten", "2010"),
            ("in twenty twenty", "in 2020"),
        ]
    )
    func years(input: String, expected: String) {
        #expect(cleaned(input, by: sut) == expected)
    }

    @Test("leaves numbers in other languages alone")
    func otherLanguages() {
        #expect(cleaned("बीस मिनट", by: sut) == "बीस मिनट")
    }

    @Test("records the numeral as a replacement and the other words as removed")
    func provenance() {
        let draft = sut.apply(Draft(text: "twenty one days"))
        #expect(draft.words[0].state == .replaced(by: NumberFormsPass.id, from: "twenty"))
        #expect(draft.words[1].state == .removed(by: NumberFormsPass.id))
        #expect(draft.words[2].state == .kept)
    }
}

@Suite("NumberWords")
struct NumberWordsTests {
    private func cardinal(_ words: String) -> (Int, Int)? {
        NumberWords.cardinal(words.split(separator: " ").map(String.init)[...]).map { ($0.value, $0.count) }
    }

    @Test(
        "reads the longest cardinal at the start and says how many words it used",
        arguments: [
            ("fifteen", 15, 1),
            ("twenty one", 21, 2),
            ("twenty twenty", 20, 1),
            ("two hundred", 200, 2),
            ("one hundred and five", 105, 4),
            ("two thousand and", 2000, 2),
            ("eight thousand eighty", 8080, 3),
            ("zero", 0, 1),
            ("five zero", 5, 1),
            ("one million two hundred thousand", 1_200_000, 5),
            ("twenty and five", 20, 1),
            ("three hundred hundred", 300, 2),
            ("nine thousand thousand", 9000, 2),
        ]
    )
    func cardinals(words: String, value: Int, count: Int) {
        #expect(cardinal(words).map { $0.0 } == value)
        #expect(cardinal(words).map { $0.1 } == count)
    }

    @Test("reads nothing from words that are not a number", arguments: ["hundred", "and five", "hello", ""])
    func notNumbers(words: String) {
        #expect(cardinal(words) == nil)
    }

    @Test("knows a numeral already in digits")
    func digits() {
        #expect(NumberWords.digits("15") == "15")
        #expect(NumberWords.digits("16.2") == "16.2")
        #expect(NumberWords.digits("2:30") == "2:30")
        #expect(NumberWords.digits("15.") == nil)
        #expect(NumberWords.digits("1st") == nil)
        #expect(
            NumberWords.isNumber("15") && NumberWords.isNumber("fifteen") && !NumberWords.isNumber("hello"))
    }

    @Test("groups thousands with commas only from ten thousand")
    func grouping() {
        #expect(NumberWords.render(9999, grouped: true) == "9999")
        #expect(NumberWords.render(10_000, grouped: true) == "10,000")
        #expect(NumberWords.render(1_234_567, grouped: true) == "1,234,567")
        #expect(NumberWords.render(1_234_567, grouped: false) == "1234567")
    }
}
