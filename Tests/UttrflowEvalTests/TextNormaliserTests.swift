// Tests each normalisation rule for what it folds away and what it must not.
import Testing

@testable import UttrflowEval

/// Normalisation decides the number, so each rule is tested for what it folds away and what it must not.
@Suite("Normalisation")
struct TextNormaliserTests {
    private let normaliser = TextNormaliser.standard

    @Test("folds case and punctuation")
    func caseAndPunctuation() {
        #expect(normaliser.words("Hello, there! Ship it.") == ["hello", "there", "ship", "it"])
    }

    @Test("drops apostrophes rather than splitting on them")
    func apostrophes() {
        #expect(normaliser.words("don't") == ["dont"])
        #expect(normaliser.words("I\u{2019}ll") == ["ill"])
    }

    /// The rule that stops the scorer manufacturing errors out of the terms the product exists to get right.
    @Test(
        "keeps a version number or an identifier whole",
        arguments: [
            ("Python 3.11", ["python", "3.11"]), ("call get_user now", ["call", "get_user", "now"]),
        ]
    )
    func keepsIdentifiers(text: String, expected: [String]) {
        #expect(normaliser.words(text) == expected)
    }

    /// A full stop that ends a sentence is a separator; only one between two alphanumerics is part of a word.
    @Test("still splits on a sentence-ending full stop")
    func sentenceStop() {
        #expect(
            normaliser.words("It shipped. Version 2.4 works.") == [
                "it", "shipped", "version", "2.4", "works",
            ])
    }

    @Test("treats a hyphen as a separator, because nobody says one")
    func hyphens() {
        #expect(normaliser.words("on-call rota") == ["on", "call", "rota"])
    }

    @Test("rewrites number words as digits")
    func numberWords() {
        #expect(normaliser.words("about fifteen people") == ["about", "15", "people"])
        #expect(normaliser.words("forty two percent") == ["42", "percent"])
        #expect(normaliser.words("thirty days") == ["30", "days"])
    }

    /// "Twenty" and "five" are two numbers when they are not a compound.
    @Test("only joins a tens word to a unit that follows it")
    func compoundNumbers() {
        #expect(normaliser.words("twenty five") == ["25"])
        #expect(normaliser.words("five twenty") == ["5", "20"])
        #expect(normaliser.words("twenty people") == ["20", "people"])
    }

    @Test("rewrites Devanagari digits and number words")
    func devanagariNumbers() {
        #expect(normaliser.words("२०१५") == ["2015"])
        #expect(normaliser.words("बीस मिनट") == ["20", "मिनट"])
    }

    /// "एक" is also "a" and "दो" is also "give", so turning either into a digit would garble sentences.
    @Test("leaves the ambiguous Devanagari number words as words")
    func ambiguousNumberWords() {
        #expect(normaliser.words("बता दो") == ["बता", "दो"])
        #expect(normaliser.words("एक बार") == ["एक", "बार"])
    }

    @Test("joins a spoken decimal back together")
    func spokenDecimal() {
        #expect(normaliser.words("python three point eleven") == ["python", "3.11"])
        #expect(
            normaliser.words("that is the point five of us agreed") == [
                "that", "is", "the", "point", "5", "of", "us", "agreed",
            ])
    }

    /// The corpus is written with false starts, and removing them would hide what those passages measure.
    @Test("leaves fillers and repeats alone")
    func keepsDisfluencies() {
        #expect(normaliser.words("um so the the deploy") == ["um", "so", "the", "the", "deploy"])
    }

    @Test("applies only the rules it was given")
    func selectiveRules() {
        let caseOnly = TextNormaliser(rules: [.caseFolding])
        #expect(caseOnly.words("Twenty Five, please") == ["twenty", "five,", "please"])
        let noNumbers = TextNormaliser(rules: [.caseFolding, .punctuationAsSeparators])
        #expect(noNumbers.words("Twenty five!") == ["twenty", "five"])
    }

    @Test("renders the words it compared, for a report to print")
    func normalisedText() {
        #expect(normaliser.normalised("Hello, World — twenty one!") == "hello world 21")
    }

    @Test("explains every rule it can apply")
    func everyRuleExplainsItself() {
        for rule in NormalisationRule.allCases {
            #expect(!rule.explanation.isEmpty, "\(rule.rawValue) has nothing to say for itself")
        }
    }
}

@Suite("Script")
struct ScriptTests {
    @Test("calls anything with Devanagari in it a Devanagari answer")
    func detection() {
        #expect(Script.of("hello there") == .latin)
        #expect(Script.of("नमस्ते") == .devanagari)
        #expect(Script.of("मैं meeting में हूँ") == .devanagari)
        #expect(Script.of("") == .latin)
        #expect(Script.of("42 8080") == .latin)
    }

    /// ICU romanises letter by letter, which is why every score through it is an upper bound.
    @Test("romanises Devanagari when there is nothing else to compare with")
    func transliteration() {
        let romanised = "नमस्ते".transliteratedToLatin
        #expect(romanised.contains("namas"))
        #expect(Script.of(romanised) == .latin)
    }

    @Test("leaves Latin text alone")
    func latinIsUntouched() {
        #expect("already latin".transliteratedToLatin == "already latin")
    }
}
