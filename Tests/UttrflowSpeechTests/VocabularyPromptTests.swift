// Tests how the user's words are packed into Whisper's prompt.
import Foundation
import Testing
import WhisperKit

@testable import UttrflowCore
@testable import UttrflowSpeech

/// A tokeniser with one id per character, so a prompt reads back as the sentence it is.
private struct SpellingTokenizer: PromptTokenizer {
    let firstSpecialToken = 50_257
    /// Text this tokeniser cannot spell at all, standing in for a script a real vocabulary lacks.
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

/// The bytes of a `DecodingOptions`, which is not `Equatable`, so "unchanged" can be asserted exactly.
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

    @Test("the fallback plan sets the retry count and log-probability test, and ships Whisper's own")
    func fallbackPlanReachesTheOptions() {
        let shipping = VocabularyPrompt.decodingOptions(languageHint: .english)
        let swept = VocabularyPrompt.decodingOptions(
            languageHint: .english, fallback: SpeechFallbackPlan(temperatureCount: 0, logProbThreshold: -0.7))

        #expect(shipping.temperatureFallbackCount == 5)
        #expect(shipping.logProbThreshold == -1.0)
        #expect(swept.temperatureFallbackCount == 0)
        #expect(swept.logProbThreshold == -0.7)
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

    @Test("two adjacent words carry nothing between them the decoder can copy")
    func adjacentWordsAreNotPunctuated() throws {
        let tokens = try #require(
            VocabularyPrompt.tokens(for: ["Mirvella", "Ostrander"], using: tokenizer))
        let prompt = tokenizer.read(tokens)

        // The prompt is read as the transcript before this one, so a mark between two words returns between them. See issue 567.
        #expect(prompt == " The words used here are Mirvella Ostrander.")
        #expect(prompt.dropLast().rangeOfCharacter(from: .punctuationCharacters) == nil)
    }

    @Test("the words are offered as a sentence, not as a list")
    func promptIsASentence() {
        let tokens = VocabularyPrompt.tokens(
            for: ["Uttrflow", "Nikhil", "PaymentSheet"], using: tokenizer)

        // Measured, not chosen: as a bare run these words left the recogniser hearing "KidPit".
        #expect(tokenizer.read(tokens) == " The words used here are Uttrflow Nikhil PaymentSheet.")
    }

    @Test("a word dropped for want of room takes its separator with it")
    func droppedWordLeavesNoGap() {
        let monster = String(repeating: "z", count: 400)
        let tokens = VocabularyPrompt.tokens(for: ["Uttrflow", monster, "Nikhil"], using: tokenizer)

        // The space belongs to the word after it, so a gap in the ranking cannot leave two of them.
        #expect(tokenizer.read(tokens) == " The words used here are Uttrflow Nikhil.")
    }

    // MARK: The budget

    @Test("the budget is the one WhisperKit actually enforces")
    func budgetMatchesWhisperKit() {
        // Spelt out so a WhisperKit upgrade that moves either number fails here rather than silently.
        #expect(VocabularyPrompt.maximumTokens == (Constants.maxTokenContext / 2) - 1)
        #expect(VocabularyPrompt.maximumTokens == 111)
    }

    @Test("an absurd vocabulary is truncated rather than handed over whole")
    func absurdVocabularyIsTruncated() throws {
        let words = (0..<500).map { "supercalifragilistic\($0)" }
        let tokens = try #require(VocabularyPrompt.tokens(for: words, using: tokenizer))

        #expect(tokens.count <= VocabularyPrompt.maximumTokens)
        // Full, not merely bounded: a budget that truncated to nothing would also pass the line above.
        #expect(tokens.count > VocabularyPrompt.maximumTokens - 30)
    }

    @Test("the words kept are the ones ranked highest")
    func truncationKeepsTheBestWords() throws {
        let words = (0..<500).map { "supercalifragilistic\($0)" }
        let tokens = try #require(VocabularyPrompt.tokens(for: words, using: tokenizer))

        // WhisperKit keeps the *last* 111 tokens, so what survives here must be the front of the ranking.
        #expect(tokenizer.read(tokens).hasPrefix(" The words used here are supercalifragilistic0 "))
        #expect(!tokenizer.read(tokens).contains("supercalifragilistic400"))
    }

    @Test("reports the exact words kept when the real prompt-token ceiling drops words")
    func reportsPackedWords() {
        let newest = "Maelis"
        let older = (0..<40).map { "Old\($0)" }
        let packing = VocabularyPrompt.packing(for: [newest] + older, using: tokenizer)

        #expect(packing.tokens?.count ?? 0 <= VocabularyPrompt.maximumTokens)
        #expect(packing.words.first == newest)
        #expect(packing.words.count < older.count + 1)
        #expect(!packing.words.contains(older.last!))
    }

    @Test("skips a word that does not fit and keeps lower-ranked words that fit")
    func overflowSkipsOnlyTheWordThatDoesNotFit() throws {
        let first = String(repeating: "a", count: 60)
        let second = String(repeating: "b", count: 25)
        let third = "cc"
        let fourth = "d"
        let tokens = try #require(
            VocabularyPrompt.tokens(for: [first, second, third, fourth], using: tokenizer))
        let prompt = tokenizer.read(tokens)

        #expect(prompt.contains(first))
        #expect(!prompt.contains(second))
        #expect(prompt.contains(third))
        #expect(prompt.contains(fourth))
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
        // WhisperKit filters these out of the prompt, so budgeting for them would budget for nothing.
        tokenizer.trailingSpecials = [50_257, 50_361]

        let tokens = try #require(VocabularyPrompt.tokens(for: ["Uttrflow"], using: tokenizer))
        #expect(tokens.allSatisfy { $0 < tokenizer.firstSpecialToken })
        #expect(tokenizer.read(tokens) == " The words used here are Uttrflow.")
    }

    // MARK: The end of the clip

    @Test("the options drive WhisperKit with the end-of-clip window its floor is derived from")
    func windowClipTimeIsTheNamedOne() {
        for hint: LanguageCode? in [.english, nil] {
            let options = VocabularyPrompt.decodingOptions(languageHint: hint)
            #expect(options.windowClipTime == VocabularyPrompt.windowClipTime)
        }
    }

    @Test("WhisperKit's floor lies past that window, so a clip at the floor has a window to decode")
    func floorClearsTheWindow() {
        let rate = Double(AudioSamples.canonicalSampleRate)
        let window = Int(VocabularyPrompt.windowClipTime * Float(AudioSamples.canonicalSampleRate))
        let floor = Int((WhisperKitBackend.shortestClip / .seconds(1) * rate).rounded(.up))

        #expect(floor > window)
        let backend = WhisperKitBackend(model: .default, modelFolder: URL(filePath: "/nonexistent"))
        #expect(backend.minimumDuration == WhisperKitBackend.shortestClip)
    }

    @Test("WhisperKit is not asked to cut the audio itself, because the product already has")
    func noChunkingOfItsOwn() {
        #expect(VocabularyPrompt.decodingOptions(languageHint: nil).chunkingStrategy == nil)
    }

    // MARK: The text before the caret

    @Test("the text before the caret follows the vocabulary sentence, so the decoder continues from it")
    func precedingTextComesLast() {
        let tokens = VocabularyPrompt.tokens(
            for: ["Uttrflow"], after: "Run the build with", using: tokenizer)

        #expect(tokenizer.read(tokens) == " The words used here are Uttrflow. Run the build with")
    }

    @Test("the text before the caret alone is a prompt, with no empty vocabulary sentence")
    func precedingTextWithoutVocabulary() {
        let tokens = VocabularyPrompt.tokens(for: [], after: "Deploy it\nwith  kubectl", using: tokenizer)

        #expect(tokenizer.read(tokens) == " Deploy it with kubectl")
    }

    @Test("long text before the caret keeps its last whole words within its share of the budget")
    func precedingTextKeepsTheTail() {
        let text = (1...40).map { "word\($0)" }.joined(separator: " ")
        let lead = VocabularyPrompt.leadIn(text, using: tokenizer)
        let read = tokenizer.read(lead)

        #expect(lead.count <= VocabularyPrompt.maximumLeadTokens)
        #expect(lead.count > VocabularyPrompt.maximumLeadTokens - 8)
        #expect(read.hasSuffix(" word40"))
        #expect(read.dropFirst().split(separator: " ").allSatisfy { $0.hasPrefix("word") })
    }

    @Test("the vocabulary packs into what the text before the caret leaves, never past 111 tokens")
    func vocabularySharesTheBudget() {
        let words = (1...60).map { "term\($0)" }
        let text = (1...40).map { "word\($0)" }.joined(separator: " ")
        let alone = VocabularyPrompt.packing(for: words, using: tokenizer)
        let shared = VocabularyPrompt.packing(for: words, after: text, using: tokenizer)

        #expect(shared.tokens?.count ?? 0 <= VocabularyPrompt.maximumTokens)
        #expect(shared.words.count < alone.words.count)
        #expect(!shared.words.isEmpty)
        #expect(shared.words == Array(alone.words.prefix(shared.words.count)))
    }

    @Test("blank or absent text before the caret changes nothing")
    func blankPrecedingTextChangesNothing() throws {
        let plain = try encoded(
            VocabularyPrompt.decodingOptions(
                languageHint: .english, vocabulary: ["Uttrflow"], tokenizer: tokenizer))
        for text: String? in [nil, "", "  \n "] {
            let options = VocabularyPrompt.decodingOptions(
                languageHint: .english, vocabulary: ["Uttrflow"], precedingText: text, tokenizer: tokenizer)
            #expect(try encoded(options) == plain)
        }
    }

    @Test("the options carry the text before the caret to the recogniser")
    func optionsCarryPrecedingText() {
        let options = VocabularyPrompt.decodingOptions(
            languageHint: .english, precedingText: "Open the", tokenizer: tokenizer)

        #expect(tokenizer.read(options.promptTokens) == " Open the")
    }
}
