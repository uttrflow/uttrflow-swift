import Foundation
import Testing

@testable import UttrflowAI
@testable import UttrflowCore
@testable import UttrflowPipeline
@testable import UttrflowTestSupport

/// A dictionary holding one spelling for one heard word, wherever it is heard.
private struct OneEntryDictionary: WordCorrecting {
    let heard: String
    let wrote: String

    func corrections(
        for transcription: Transcription, seeing context: AppContext
    ) async throws(DictationChangeError) -> [DictationCorrection] {
        transcription.text.split(whereSeparator: \.isWhitespace).enumerated().compactMap {
            $0.element.lowercased() == heard
                ? DictationCorrection(
                    heard: String($0.element), wrote: wrote, wordRange: $0.offset..<($0.offset + 1),
                    entryID: UUID(), reason: .unknown("test"), heardConfidence: 0.2)
                : nil
        }
    }
}

@Suite("Snippet triggers: how a phrase arrives at the matcher")
struct SnippetArrivalTests {
    /// Invented triggers across numbers, spoken marks, fillers, contractions, a dictionary word and romanised Hindi.
    static let triggers = [
        "email one", "send a comma", "um sign off", "cube control", "page two", "step three please",
        "room twenty one", "uh my address", "dont forget", "its done", "call me at five",
        "question mark reply", "new line thanks", "version two point one", "ok bye", "cube notes",
        "hmm standup link", "i am out", "weekly one on one", "my zoom link", "tea break",
        "thanks so much", "हाँ ठीक है", "मैं अभी आता हूँ", "कल मिलते हैं", "बहुत अच्छा",
        "चलो ठीक है", "नमस्ते जी", "धन्यवाद भाई", "अच्छा सुनो",
    ]

    private static let dictionary = OneEntryDictionary(heard: "cube", wrote: "Kube")

    /// One phrase said into an unknown app, tidied by the rules alone, with the one-entry dictionary on file.
    private func scenario(hearing phrase: String, snippets: [Snippet] = []) -> Scenario {
        Scenario(
            pieces: [ScriptedPiece(phrase)], context: .unknown,
            cleaner: TransformerRouter(
                engines: [RuleBasedTransformer()], preference: [.rules], rulesAlone: .shortReplies),
            corrector: Self.dictionary, snippets: FiledSnippets(snippets: snippets))
    }

    private func words(_ text: String) -> [String] {
        Snippet(trigger: text, expansion: " ", created: .distantPast).triggerWords
    }

    @Test("the preview is the words a dictation of that phrase inserts", arguments: triggers)
    func previewMatchesDictation(_ phrase: String) async {
        let arrives = await ScenarioDriver.arrival(ofSpoken: phrase, in: scenario(hearing: phrase))
        let run = await ScenarioDriver.run(scenario(hearing: phrase))

        #expect(run.writes.count == 1)
        #expect(words(arrives) == words(run.writes.first ?? ""), "\(arrives) vs \(run.writes)")
        #expect(LatinScript.isLatin(arrives))
    }

    @Test("a trigger saved in the form it arrives fires when said", arguments: triggers)
    func arrivedFormFires(_ phrase: String) async {
        let arrives = await ScenarioDriver.arrival(ofSpoken: phrase, in: scenario(hearing: phrase))
        let snippet = Snippet(trigger: arrives, expansion: "EXPANDED", created: .distantPast)
        let run = await ScenarioDriver.run(scenario(hearing: phrase, snippets: [snippet]))

        #expect(run.writes.first?.contains("EXPANDED") == true, "\(arrives) -> \(run.writes)")
    }

    @Test("a snippet's caret marker moves the caret back to it once the words are written")
    func caretMarkerIsPlaced() async throws {
        let snippet = Snippet(trigger: "sign off", expansion: "Regards,{caret} team", created: .distantPast)
        let run = await ScenarioDriver.run(scenario(hearing: "sign off", snippets: [snippet]))

        let written = try #require(run.writes.first)
        let back = try #require(run.placedCarets.first)
        #expect(run.placedCarets.count == 1)
        #expect(String(decoding: Array(written.utf16).suffix(back), as: UTF16.self).hasPrefix(" team"))
        #expect(!written.contains("{caret}"))
    }

    @Test("a snippet without a marker leaves the caret after the words")
    func noMarkerNoMove() async {
        let snippet = Snippet(trigger: "sign off", expansion: "Regards, team", created: .distantPast)
        let run = await ScenarioDriver.run(scenario(hearing: "sign off", snippets: [snippet]))

        #expect(run.placedCarets.isEmpty)
    }

    /// Invented triggers typed in Devanagari or in mixed script, as a person types them in the editor.
    static let typedInDevanagari = [
        "हाँ ठीक है", "मैं अभी आता हूँ", "कल मिलते हैं", "बहुत अच्छा", "नमस्ते जी",
        "मेरा address", "office का पता", "धन्यवाद team", "send करो notes", "चाय break",
    ]

    @Test(
        "a trigger typed in Devanagari fires when said, and inserts Latin only",
        arguments: typedInDevanagari)
    func devanagariTriggerFires(_ phrase: String) async {
        let snippet = Snippet(trigger: phrase, expansion: "पता: EXPANDED", created: .distantPast)
        let run = await ScenarioDriver.run(scenario(hearing: phrase, snippets: [snippet]))

        let inserted = run.writes.first ?? ""
        #expect(inserted.contains("EXPANDED"), "\(phrase) -> \(run.writes)")
        #expect(LatinScript.writesOnlyLatin(inserted), "\(inserted)")
    }

    @Test("the dictionary's spelling is part of the arrival")
    func dictionaryIsApplied() async {
        let arrives = await ScenarioDriver.arrival(
            ofSpoken: "cube control", in: scenario(hearing: "cube control"))
        #expect(words(arrives) == ["kube", "control"])
    }
}
