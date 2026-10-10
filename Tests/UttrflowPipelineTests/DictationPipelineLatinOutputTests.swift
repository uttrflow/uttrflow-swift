import Foundation
import Testing

@testable import UttrflowAI
@testable import UttrflowCore
@testable import UttrflowDictionary
@testable import UttrflowPipeline
@testable import UttrflowTestSupport

@Suite("Dictation pipeline: Latin letters only")
struct DictationPipelineLatinOutputTests {
    /// One short take, heard as `heard` in Hindi, tidied by `cleaner`, and what was inserted.
    private func dictate(
        _ heard: String,
        cleaner: any TranscriptCleaning = FakeTranscriptCleaner(producedBy: .foundationModels),
        snippets: [Snippet] = []
    ) async -> [String] {
        await ScenarioDriver.run(scenario(heard, cleaner: cleaner, snippets: snippets)).writes
    }

    /// One piece heard in Hindi into the standard field, with the snippets on file.
    private func scenario(
        _ heard: String,
        cleaner: any TranscriptCleaning = FakeTranscriptCleaner(producedBy: .foundationModels),
        snippets: [Snippet] = []
    ) -> Scenario {
        Scenario(
            pieces: [ScriptedPiece(heard, language: .hindi)], context: .fixture(), cleaner: cleaner,
            snippets: FiledSnippets(snippets: snippets))
    }

    @Test("writes a listed word in the spelling the user prefers, after romanising it")
    func writesPreferredSpelling() async {
        var scenario = self.scenario("हाँ ठीक है।")
        scenario.spellings = { ["thik": "theek"] }
        let written = await ScenarioDriver.run(scenario).writes
        #expect(written.first?.hasPrefix("Haan theek hai") == true, "\(written)")
    }

    @Test("writes a listed word as the user's dictionary entry spells it, on the model and the rules path")
    func writesDictionaryEntrySpelling() async {
        let entry = DictionaryEntry(word: "theek", origin: .added, firstSeen: Date(timeIntervalSince1970: 0))
        let rules = TransformerRouter(
            engines: [RuleBasedTransformer()], preference: [.foundationModels, .rules],
            rulesAlone: .shortReplies)
        for cleaner: any TranscriptCleaning in [FakeTranscriptCleaner(producedBy: .foundationModels), rules] {
            var scenario = self.scenario("हाँ ठीक है।", cleaner: cleaner)
            scenario.spellings = { SpellingPreferences.preferred(filed: [entry], learnt: ["theek": "thik"]) }
            let written = await ScenarioDriver.run(scenario).writes
            #expect(written.first?.hasPrefix("Haan theek hai") == true, "\(written)")
        }
    }

    @Test("romanises Devanagari that no tidier romanised, whether the tidy failed or handed the words back")
    func romanisesUntidiedDevanagari() async {
        for cleaner: any TranscriptCleaning in [
            FakeTranscriptCleaner(answering: ScriptedSequence(.failure(.noCapableTransformer))),
            FakeTranscriptCleaner(producedBy: .foundationModels),
        ] {
            let inserted = await dictate("हाँ ठीक है।", cleaner: cleaner)
            #expect(inserted.count == 1)
            #expect(inserted.allSatisfy { !Romaniser.containsDevanagari($0) && LatinScript.isLatin($0) })
            #expect(inserted.first?.hasPrefix("Haan thik hai") == true, "\(inserted)")
        }
    }

    @Test("romanises Devanagari from a snippet before insertion")
    func romanisesSnippetExpansion() async {
        let snippet = Snippet(
            trigger: "greeting", expansion: "हाँ ठीक है", created: Date(timeIntervalSince1970: 0))
        let inserted = await dictate(
            "greeting", cleaner: FakeTranscriptCleaner(producedBy: .foundationModels), snippets: [snippet])

        #expect(inserted == ["Haan thik hai"])
        #expect(inserted.allSatisfy { !Romaniser.containsDevanagari($0) && LatinScript.isLatin($0) })
    }

    @Test("inserts romanised Hinglish on the shipping floor when the model is not there")
    func rulesFloorRomanises() async {
        let router = TransformerRouter(
            engines: [RuleBasedTransformer()], preference: [.foundationModels, .rules],
            rulesAlone: .shortReplies)
        let inserted = await dictate("मैं अभी आता हूँ", cleaner: router)
        #expect(inserted.count == 1)
        #expect(inserted.first?.hasPrefix("Main abhi aata hoon") == true, "\(inserted)")
    }

    @Test(
        "a piece heard mostly in a script neither language is written in inserts nothing and fails as untranscribed",
        arguments: ["Привет, как дела", "你好，谢谢观看", "شكرا جزيلا", "สวัสดีครับ"])
    func untranscribedScriptIsARecognitionFailure(heard: String) async {
        var scenario = self.scenario(heard)
        scenario.pieces.append(ScriptedPiece(heard, language: .hindi))
        scenario.take = ScenarioDriver.take(Array(scenario.pieces.prefix(1)))
        let run = await ScenarioDriver.run(scenario)
        #expect(run.writes.isEmpty)
        #expect(run.state == .failed(DictationFailure(SpeechEngineError.speechWithoutWords)))
        #expect(run.heard.count == 2)
    }

    @Test("writes a single word of another script inside an English sentence in Latin letters")
    func transliteratesOneForeignWord() async {
        let inserted = await dictate(
            "Let us meet at the Привет cafe tomorrow",
            cleaner: FakeTranscriptCleaner(producedBy: .foundationModels))
        #expect(inserted.count == 1)
        #expect(inserted.allSatisfy { LatinScript.isLatin($0) && $0.hasPrefix("Let us meet at the ") })
    }

    @Test(
        "inserts English exactly as the tidier wrote it",
        arguments: ["Okay, see you at 5 p.m. 👍", "Café “naïve” — résumé…", "x² ≤ ½, ₹1,50,000 and 3.5%"])
    func leavesEnglishAlone(text: String) async {
        #expect(await dictate(text, cleaner: FakeTranscriptCleaner(producedBy: .foundationModels)) == [text])
    }

    @Test(
        "every written word is heard or counted as a script conversion on the outcome",
        arguments: [
            ("हाँ ठीक है।", 3, 0), ("मुझे report भेजो", 2, 0), ("मैं अभी आता हूँ", 4, 0),
            ("send the report today", 0, 0), ("Let us meet at the Привет cafe tomorrow", 0, 1),
        ])
    func writtenWordsAreAccounted(heard: String, romanised: Int, transliterated: Int) async {
        let run = await ScenarioDriver.run(scenario(heard))
        let inserted = run.writes
        guard let outcome = run.outcome else {
            Issue.record("not inserted: \(run.state)")
            return
        }
        let conversions = outcome.changes.scriptConversions
        #expect(
            conversions == ScriptConversions(wordsRomanised: romanised, wordsTransliterated: transliterated))
        let heardWords = Set(Self.words(heard))
        let novel = inserted.flatMap(Self.words).filter { !heardWords.contains($0) }.count
        let unaccounted = max(0, novel - conversions.words)
        print("romanised \(conversions.wordsRomanised), transliterated \(conversions.wordsTransliterated)")
        #expect(unaccounted == 0, "\(inserted) has \(unaccounted) words with no named origin")
    }

    /// Lower-cased words with their punctuation dropped, the form two texts are compared in.
    private static func words(_ text: String) -> [String] {
        text.split(whereSeparator: \.isWhitespace)
            .map { $0.lowercased().filter { $0.isLetter || $0.isNumber } }
            .filter { !$0.isEmpty }
    }
}
