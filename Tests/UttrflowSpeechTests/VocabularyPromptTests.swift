import Foundation
import Testing
import WhisperKit

@testable import UttrflowCore
@testable import UttrflowSpeech

/// A tokeniser a test can pin exactly.
///
/// One id per character, so a word's cost in the prompt equals its length and the prompt
/// can be read back as the sentence it is — which is what makes the assertions below
/// readable rather than arrays of magic numbers.
private struct SpellingTokenizer: PromptTokenizer {
    let firstSpecialToken = 50_257
    /// Text this tokeniser cannot spell at all, standing in for what a real vocabulary
    /// does with a script it does not cover.
    var unencodable: Set<String> = []
    /// Ids appended to every piece, for checking that special tokens are kept out.
    var trailingSpecials: [Int] = []

    func encode(text: String) -> [Int] {
        guard !unencodable.contains(text) else { return [] }
        return text.unicodeScalars.map { Int($0.value) } + trailingSpecials
    }

    func read(_ tokens: [Int]?) -> String {
        String(String.UnicodeScalarView((tokens ?? []).compactMap(Unicode.Scalar.init)))
    }
}

/// The bytes of a `DecodingOptions`, so that "unchanged" can be asserted rather than
/// approximated. `DecodingOptions` is `Codable` but not `Equatable`, and the fields that
/// matter here are exactly the ones nobody would think to compare by hand.
private func encoded(_ options: DecodingOptions) throws -> Data {
    let encoder = JSONEncoder()
    encoder.outputFormatting = .sortedKeys
    return try encoder.encode(options)
}

@Suite("VocabularyPrompt")
struct VocabularyPromptTests {
    private let tokenizer = SpellingTokenizer()

    // MARK: The wiring is real

    @Test("the same audio with a vocabulary asks the recogniser for something different")
    func vocabularyChangesTheOptions() throws {
        let plain = VocabularyPrompt.decodingOptions(languageHint: .english)
        let biased = VocabularyPrompt.decodingOptions(
            languageHint: .english, vocabulary: ["Uttrflow"], tokenizer: tokenizer)

        #expect(plain.promptTokens == nil)
        #expect(biased.promptTokens?.isEmpty == false)
        #expect(try encoded(plain) != encoded(biased))
    }

    @Test("an empty vocabulary asks for exactly what it asked for before biasing existed")
    func emptyVocabularyChangesNothing() throws {
        for hint: LanguageCode? in [.english, nil] {
            let plain = try encoded(VocabularyPrompt.decodingOptions(languageHint: hint))
            let empty = try encoded(
                VocabularyPrompt.decodingOptions(
                    languageHint: hint, vocabulary: [], tokenizer: tokenizer))

            #expect(plain == empty)
        }
    }

    @Test("a recogniser whose tokeniser has not loaded is asked for exactly the same thing")
    func missingTokenizerChangesNothing() throws {
        let plain = try encoded(VocabularyPrompt.decodingOptions(languageHint: .hindi))
        let unbiasable = try encoded(
            VocabularyPrompt.decodingOptions(
                languageHint: .hindi, vocabulary: ["Uttrflow"], tokenizer: nil))

        #expect(plain == unbiasable)
    }

    @Test("biasing leaves the language decision alone")
    func languageSurvivesBiasing() {
        let pinned = VocabularyPrompt.decodingOptions(
            languageHint: .hindi, vocabulary: ["Uttrflow"], tokenizer: tokenizer)
        #expect(pinned.language == "hi")
        #expect(pinned.detectLanguage == false)

        let detecting = VocabularyPrompt.decodingOptions(
            languageHint: nil, vocabulary: ["Uttrflow"], tokenizer: tokenizer)
        #expect(detecting.language == nil)
        #expect(detecting.detectLanguage == true)
    }

    // MARK: The shape the decoder actually listens to

    @Test("the words are offered as a sentence, not as a list")
    func promptIsASentence() {
        let tokens = VocabularyPrompt.tokens(
            for: ["Uttrflow", "Nikhil", "PaymentSheet"], using: tokenizer)

        // Measured, not chosen: the same three words as a bare run left the recogniser
        // hearing "KidPit", and inside this sentence it heard "Uttrflow".
        #expect(tokenizer.read(tokens) == " The words used here are Uttrflow, Nikhil, PaymentSheet.")
    }

    @Test("a word dropped for want of room takes its separator with it")
    func droppedWordLeavesNoComma() {
        let monster = String(repeating: "z", count: 400)
        let tokens = VocabularyPrompt.tokens(for: ["Uttrflow", monster, "Nikhil"], using: tokenizer)

        // The comma belongs to the word that follows it, so a gap in the middle of the
        // ranking cannot leave the decoder reading ", ,".
        #expect(tokenizer.read(tokens) == " The words used here are Uttrflow, Nikhil.")
    }

    // MARK: The budget

    @Test("the budget is the one WhisperKit actually enforces")
    func budgetMatchesWhisperKit() {
        // `(Constants.maxTokenContext / 2) - 1`, with `maxTokenContext` being
        // `Int(448 / 2)`. Spelt out so that a WhisperKit upgrade that moves either
        // number fails here rather than silently losing half the vocabulary.
        #expect(VocabularyPrompt.maximumTokens == (Constants.maxTokenContext / 2) - 1)
        #expect(VocabularyPrompt.maximumTokens == 111)
    }

    @Test("an absurd vocabulary is truncated rather than handed over whole")
    func absurdVocabularyIsTruncated() throws {
        let words = (0..<500).map { "supercalifragilistic\($0)" }
        let tokens = try #require(VocabularyPrompt.tokens(for: words, using: tokenizer))

        #expect(tokens.count <= VocabularyPrompt.maximumTokens)
        // Full, not merely bounded: a budget that truncated to nothing would also pass
        // the line above while throwing away every word the user has.
        #expect(tokens.count > VocabularyPrompt.maximumTokens - 30)
    }

    @Test("the words kept are the ones ranked highest")
    func truncationKeepsTheBestWords() throws {
        let words = (0..<500).map { "supercalifragilistic\($0)" }
        let tokens = try #require(VocabularyPrompt.tokens(for: words, using: tokenizer))

        // WhisperKit keeps the *last* 111 tokens of whatever it is given, so anything
        // that hands it more than 111 loses the front of a best-first ranking. What
        // survives here must be the front.
        #expect(tokenizer.read(tokens).hasPrefix(" The words used here are supercalifragilistic0,"))
        #expect(!tokenizer.read(tokens).contains("supercalifragilistic400"))
    }

    @Test("one enormous word does not cost the ordinary words ranked behind it")
    func oneLongWordDoesNotEmptyThePrompt() {
        let monster = String(repeating: "z", count: 400)
        let tokens = VocabularyPrompt.tokens(for: [monster, "Uttrflow"], using: tokenizer)

        #expect(tokenizer.read(tokens) == " The words used here are Uttrflow.")
    }

    // MARK: Failing safe

    @Test("a vocabulary that will not tokenise degrades to transcribing normally")
    func unencodableVocabularyChangesNothing() throws {
        var tokenizer = SpellingTokenizer()
        tokenizer.unencodable = [" \u{1F600}"]

        let plain = try encoded(VocabularyPrompt.decodingOptions(languageHint: .english))
        let unencodable = try encoded(
            VocabularyPrompt.decodingOptions(
                languageHint: .english, vocabulary: ["\u{1F600}"], tokenizer: tokenizer))

        #expect(VocabularyPrompt.tokens(for: ["\u{1F600}"], using: tokenizer) == nil)
        #expect(plain == unencodable)
    }

    @Test("an empty vocabulary never becomes a prompt of nothing but the sentence")
    func emptyVocabularyIsNoPrompt() {
        #expect(VocabularyPrompt.tokens(for: [], using: tokenizer) == nil)
    }

    @Test("a tokeniser that cannot even spell the sentence gives up rather than guessing")
    func unencodableSentenceIsNoPrompt() {
        var tokenizer = SpellingTokenizer()
        tokenizer.unencodable = [VocabularyPrompt.opening, VocabularyPrompt.closing]

        #expect(VocabularyPrompt.tokens(for: ["Uttrflow"], using: tokenizer) == nil)
    }

    @Test("one word that will not tokenise costs only that word")
    func unencodableWordIsSkipped() {
        var tokenizer = SpellingTokenizer()
        tokenizer.unencodable = [" \u{1F600}"]

        let tokens = VocabularyPrompt.tokens(for: ["\u{1F600}", "Uttrflow"], using: tokenizer)
        #expect(tokenizer.read(tokens) == " The words used here are Uttrflow.")
    }

    @Test("special tokens never reach the decoder as vocabulary")
    func specialTokensAreDropped() throws {
        var tokenizer = SpellingTokenizer()
        // A real tokeniser can emit these; WhisperKit filters them out of the prompt, so
        // budgeting for them would mean budgeting for tokens that never arrive.
        tokenizer.trailingSpecials = [50_257, 50_361]

        let tokens = try #require(VocabularyPrompt.tokens(for: ["Uttrflow"], using: tokenizer))
        #expect(tokens.allSatisfy { $0 < tokenizer.firstSpecialToken })
        #expect(tokenizer.read(tokens) == " The words used here are Uttrflow.")
    }

    // MARK: What the recogniser has to be held open for

    @Test("counts the tokens WhisperKit forces before the transcript starts")
    func forcedPrefillLength() {
        // <|startofprev|> + prompt + <|startoftranscript|> + language + task + timestamps.
        #expect(
            VocabularyPrompt.forcedPrefillLength(promptLength: 9, isMultilingual: true) == 14)
        // A model that knows only English is given neither a language nor a task token.
        #expect(
            VocabularyPrompt.forcedPrefillLength(promptLength: 9, isMultilingual: false) == 12)
    }
}
