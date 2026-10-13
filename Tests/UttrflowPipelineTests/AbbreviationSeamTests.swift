// Synthetic abbreviation seams exercise the composed rules pipeline and punctuation ownership.

import Testing

@testable import UttrflowAI
@testable import UttrflowCore
@testable import UttrflowDictionary
@testable import UttrflowPipeline
@testable import UttrflowTestSupport

@Suite("Abbreviation dots survive piece seams")
struct AbbreviationSeamTests {
    private func pipeline() -> DictationPipeline {
        DictationPipeline(
            capture: FakeAudioCaptureEngine(), speech: FakeSpeechEngine(),
            cleaner: TransformerRouter(engines: [RuleBasedTransformer()], preference: [.rules]),
            context: FakeContextEngine(), inserter: FakeTextInserter(),
            corrector: DictionaryCorrections { _ in PhoneticIndex(entries: []) })
    }

    @Test(
        "a Latin lead-in cut after its abbreviation retains the whole transcript",
        arguments: [
            (
                "several markers e.g. ferritin and albumin were measured at baseline", 3,
                "Several markers e.g. ferritin and albumin were measured at baseline."
            ),
            (
                "the control group i.e. the students without tutoring scored lower", 4,
                "The control group i.e. the students without tutoring scored lower."
            ),
        ])
    func composedLeadIn(sentence: String, cut: Int, expected: String) async {
        let words = sentence.split(separator: " ").map(String.init)
        let parts = [words.prefix(cut).joined(separator: " "), words.dropFirst(cut).joined(separator: " ")]
        let context = AppContext(applicationName: "FixtureEditor", precedingText: "")
        let whole = await pipeline().clean([Transcription(text: sentence)], seeing: context).text
        let joined = await pipeline().clean(parts.map { Transcription(text: $0) }, seeing: context).text
        #expect(whole == expected)
        #expect(joined == expected)
    }

    @Test("a continuation preserves a lead-in's own dot", arguments: ["e.g.", "i.e."])
    func leadInOwnership(abbreviation: String) {
        let pieces = ["Several markers \(abbreviation)", "Ferritin and albumin were measured."]
        let output = PieceJoiner.seamed(pieces, under: .standard(for: .document))
        #expect(output == pieces)
    }

    @Test(
        "a destination without sentence stops preserves every registered abbreviation-owned dot",
        arguments: Abbreviations.table.rows.filter { !$0.alsoAWord && $0.symbol == nil }.map { $0.id + "." })
    func noTerminalStopOwnership(abbreviation: String) {
        let formatter = DestinationFormatter.standard(for: .codeEditor)
        let pieces = ["Read \(abbreviation)", "More text"]
        let output = PieceJoiner.seamed(pieces, under: formatter)
        #expect(output[0] == pieces[0])
    }

    @Test(
        "short technical filenames keep their existing sentence-stop removal",
        arguments: ["a.py", "ab.py", "xy.js", "ui.ts"])
    func technicalFileStops(file: String) {
        let pieces = ["Open \(file).", "More text"]
        #expect(PieceJoiner.seamed(pieces, under: .standard(for: .codeEditor))[0] == "Open \(file)")
    }

    @Test("ordinary sentence stops still disappear when a continuation needs no stop")
    func ordinaryStop() {
        #expect(
            PieceJoiner.seamed(["We moved the review to.", "Thursday."], under: .standard(for: .document))
                == ["We moved the review to", "Thursday."])
        #expect(
            PieceJoiner.seamed(["Read the file.", "More text"], under: .standard(for: .codeEditor))[0]
                == "Read the file")
    }
}
