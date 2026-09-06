import Foundation
import Testing
import UttrflowAI
import UttrflowCore

@testable import UttrflowEval

/// The corpus half of Phase D: a case that names a doubtful run must actually produce one.
@Suite("Doubtful-word cases")
struct DoubtfulCorpusTests {
    private var doubtfulCases: [EvaluationCase] { EvaluationCorpus.all.filter { !$0.doubtful.isEmpty } }

    private func spans(for testCase: EvaluationCase) async -> [DoubtfulSpan] {
        let draft = CleaningPipeline.beforeModel.run(Draft(transcription: testCase.transcription))
        return await DoubtfulWords.standard.spans(in: draft, for: testCase.situation)
    }

    @Test("scores every word of a case that names a doubtful run, and none of a case that does not")
    func scoresOnlyWhereItMatters() {
        for testCase in EvaluationCorpus.all {
            let draft = Draft(transcription: testCase.transcription)
            #expect(draft.confidencesAreReal == !testCase.doubtful.isEmpty, "\(testCase.id)")
        }
    }

    @Test("puts the doubtful run under the correction engine's threshold and leaves the rest certain")
    func marksTheRightWords() {
        for testCase in doubtfulCases {
            let draft = Draft(transcription: testCase.transcription)
            let unsure = Set(draft.words.filter { $0.confidence < 0.5 }.map(\.text))
            let named = Set(testCase.doubtful.flatMap { $0.split(separator: " ") }.map(String.init))
            #expect(unsure == named, "\(testCase.id)")
        }
    }

    @Test("offers the identifier the screen spells for each of the three identifier cases")
    func offersTheScreensIdentifier() async {
        let wanted = [
            "editor-identifier-casing": ("payment sheet", "PaymentSheet"),
            "code-editor-identifier-from-screen": ("fetch invoices", "fetchInvoices"),
            "sql-editor-identifier-from-screen": ("order totals", "orderTotals"),
        ]
        for (id, expected) in wanted {
            guard let testCase = EvaluationCorpus.all.first(where: { $0.id == id }) else {
                Issue.record("\(id) is not in the corpus")
                continue
            }
            let found = await spans(for: testCase)
            #expect(found.map(\.heard) == [expected.0], "\(id)")
            #expect(found.first?.candidates == [expected.1], "\(id)")
        }
    }

    @Test("offers nothing when the window shows nothing that sounds like the doubtful word")
    func offersNothingWithoutAScreen() async {
        for id in [
            "chat-identifier-casing", "doubtful-word-heard-word-stands",
            "doubtful-word-with-nothing-on-screen",
        ] {
            guard let testCase = EvaluationCorpus.all.first(where: { $0.id == id }) else { continue }
            #expect(await spans(for: testCase).isEmpty, "\(id)")
        }
    }

    /// Only the bake-off can run the real chooser, so a stand-in that takes the first reading offered stands here.
    @Test("passes each identifier case when the model takes the reading it was offered")
    func passesWhenTheModelChooses() async throws {
        for id in [
            "editor-identifier-casing", "code-editor-identifier-from-screen",
            "sql-editor-identifier-from-screen", "doubtful-word-from-window",
        ] {
            guard let testCase = EvaluationCorpus.all.first(where: { $0.id == id }) else { continue }
            let transformer = GenerativeTextTransformer(
                kind: .foundationModels, model: FirstReadingModel(spoken: testCase.spoken))
            let text = try await transformer.transform(testCase.transformationRequest()).text
            let score = Scorer.score(text, against: testCase)
            #expect(score.keptEverythingRequired, "\(id) lost \(score.lost) from \(text)")
            #expect(score.invented.isEmpty, "\(id) invented \(score.invented) in \(text)")
            #expect(score.brokeShape.isEmpty, "\(id) broke \(score.brokeShape) in \(text)")
        }
    }
}

/// A stand-in chooser that takes the first reading it is offered for every doubtful run.
private struct FirstReadingModel: CleanupModel {
    let spoken: String

    func availability(for language: LanguageCode?) async -> TransformerAvailability { .available }

    func rewrite(
        _ text: String, instructions: String, kind: TransformerKind
    ) async throws(TransformationError) -> String {
        Self.readings(in: text).reduce(spoken) { $0.replacingOccurrences(of: $1.heard, with: $1.reading) }
    }

    /// Each run and its first reading, read back off the line the builder wrote.
    static func readings(in prompt: String) -> [(heard: String, reading: String)] {
        guard
            let line = prompt.split(separator: "\n")
                .first(where: { $0.hasPrefix(PromptBuilder.doubtfulLabel) })
        else { return [] }
        return line.dropFirst(PromptBuilder.doubtfulLabel.count)
            .components(separatedBy: "; ")
            .compactMap {
                let halves = $0.components(separatedBy: " — could be: ")
                let quoted = halves.first?.split(separator: "\"") ?? []
                guard halves.count == 2, quoted.count >= 2,
                    let reading = halves[1].components(separatedBy: ", ").first
                else { return nil }
                return (String(quoted[1]), reading)
            }
    }
}
