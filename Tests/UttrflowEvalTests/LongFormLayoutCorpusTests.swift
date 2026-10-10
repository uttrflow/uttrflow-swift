import Testing
import UttrflowAI
import UttrflowCore

@testable import UttrflowEval

/// Dictations of three to eight sentences, laid out in paragraphs and lists, with a recipe for their audio.
@Suite("Long-form layout corpus")
struct LongFormLayoutCorpusTests {
    /// The cases the rules engine fails today; a fix that passes one removes it here.
    static let failingToday: Set<String> = [
        // No paragraph break at a long pause where the topic changes.
        "long-form-hesitating-status-paragraph-at-a-pause",
        // Spoken ordinals ("first", "second", "finally") do not open a numbered list.
        "long-form-listing-steps-by-ordinal",
        // "no actually make that" inside a list item keeps the replaced words.
        "long-form-correcting-an-item-in-a-list",
    ]

    @Test("each case is three to eight sentences, laid out, and speaks for 30 seconds to 5 minutes")
    func shape() {
        #expect(EvaluationCorpus.longForm.count >= 5)
        for item in EvaluationCorpus.longForm {
            let sentences = Self.sentences(in: item.expected)
            #expect((3...8).contains(sentences), "\(item.id): \(sentences) sentences")
            #expect(item.expected.contains("\n"), "\(item.id) has no layout")
            let recipe = LongFormRecipe(item)
            #expect((30...300).contains(recipe.estimatedSeconds), "\(item.id): \(recipe.estimatedSeconds) s")
            let words = item.spoken.split(whereSeparator: \.isWhitespace).count
            #expect(item.pausedAfter.allSatisfy { $0 < words - 1 }, "\(item.id) pauses past its last word")
        }
    }

    /// Sentence ends in `text`, leaving out the stop a numbered list marker carries.
    static func sentences(in text: String) -> Int {
        text.split(separator: "\n").map { line in
            let body = line.drop { $0.isNumber }.drop { $0 == "." || $0 == ")" }
            return body.filter { ".?!".contains($0) }.count
        }.reduce(0, +)
    }

    @Test("covers both a cut forced by the recogniser's window and cuts at natural pauses")
    func cuts() {
        let recipes = EvaluationCorpus.longForm.map(LongFormRecipe.init)
        #expect(recipes.contains { $0.longestUnbrokenSeconds > SpeechWindowing.standard.maximumLength })
        #expect(EvaluationCorpus.longForm.filter { !$0.pausedAfter.isEmpty }.count >= 4)
    }

    @Test("writes each pause as silence after its word")
    func recipeScript() {
        let item = EvaluationCase(
            id: "case", category: .everyday, spoken: "one two three", expected: "One.\nTwo three.",
            pausedAfter: [0])
        #expect(LongFormRecipe(item).script == "one [[slnc 1000]] two three")
    }

    @Test("fails exactly the cases the rules engine cannot lay out yet")
    func rulesEngineToday() async throws {
        var failing: Set<String> = []
        for item in EvaluationCorpus.longForm {
            let result = try await RuleBasedTransformer().transform(item.transformationRequest())
            if !item.longFormPasses(result.text) {
                failing.insert(item.id)
            }
        }
        #expect(failing == Self.failingToday)
    }
}
