import Testing
import UttrflowCore

@testable import UttrflowAI

@Suite("CaretCloserPass")
struct CaretCloserPassTests {
    @Test(
        "removes model-added closers for unmatched text before the caret",
        arguments: [
            ("I told him (", "see the attached file", "see the attached file.\"", "see the attached file."),
            ("She said \"", "we will be late", "we will be late.'", "we will be late."),
            ("The ratio is (approximately ", "two to one", "two to one).", "two to one."),
            ("He wrote 'hello ", "world and goodbye", "world and goodbye.'", "world and goodbye."),
        ])
    func removesUnspokenClosingDelimiter(
        preceding: String, spoken: String, answer: String, expected: String
    ) {
        let pass = CaretCloserPass(precedingText: preceding, spokenText: spoken)
        #expect(pass.apply(Draft(keepingLineBreaks: answer)).text == expected)
    }

    @Test("keeps a closing delimiter present in the processed spoken text")
    func keepsDictatedClosingDelimiter() {
        let pass = CaretCloserPass(precedingText: "The ratio is (approximately ", spokenText: "two to one)")
        #expect(pass.apply(Draft(keepingLineBreaks: "Two to one).")).text == "Two to one).")
        let separateToken = CaretCloserPass(
            precedingText: "The ratio is (approximately ", spokenText: "two to one )")
        #expect(separateToken.apply(Draft(keepingLineBreaks: "Two to one )")).text == "Two to one )")
    }

    @Test("leaves a balanced or absent opening delimiter alone")
    func ignoresBalancedContext() {
        #expect(!CaretStructure(precedingText: "The ratio is (approximately two to one). ").hasOpenDelimiter)
        #expect(!CaretStructure(precedingText: "She said \"we will be late.\" ").hasOpenDelimiter)
        let pass = CaretCloserPass(
            precedingText: "The ratio is (approximately two to one). ", spokenText: "three")
        #expect(pass.apply(Draft(keepingLineBreaks: "Three.")).text == "Three.")
    }

    @Test("tracks nested and curly delimiters without treating contractions as open quotes")
    func recognizesOpenDelimiters() {
        #expect(CaretStructure(precedingText: "start ([").hasOpenDelimiter)
        #expect(CaretStructure(precedingText: "She said \u{201C}hello").hasOpenDelimiter)
        #expect(!CaretStructure(precedingText: "It's ready. ").hasOpenDelimiter)
        #expect(!CaretStructure(precedingText: "start (done) ").hasOpenDelimiter)
    }

    @Test("removes a delimiter split into its own final token")
    func removesStandaloneClosingToken() {
        let pass = CaretCloserPass(precedingText: "I told him (", spokenText: "see the attached file")
        #expect(
            pass.apply(Draft(keepingLineBreaks: "See the attached file. )")).text == "See the attached file.")
    }

    @Test("runs after the model, leaving the open bracket's sentence unstopped and lower-case")
    func pipelineRemovesCloserBeforeFinishing() {
        let context = AppContext(precedingText: "I told him (")
        let situation = Situation(app: context, insertion: context.insertionPoint, destination: .document)
        let pipeline = CleaningPipeline.afterModel(
            for: .standard(for: .document), situation: situation,
            heard: "see the attached file", spoken: "see the attached file")
        #expect(
            pipeline.run(Draft(keepingLineBreaks: "see the attached file)\"")).text
                == "see the attached file")
    }
}
