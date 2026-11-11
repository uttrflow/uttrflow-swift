import Foundation
import Testing
import UttrflowAI
import UttrflowCore

@testable import UttrflowEval

/// Every notation case written the same from its bare words and from the recogniser's cased, punctuated form of them.
@Suite("Notation from recogniser-style text")
struct NotationRecogniserFormTests {
    /// The notation cases `NotationRecallTests` counts, at every destination whose notation the symbol rows write.
    static let cases = NotationRecallTests.destinations.flatMap(NotationRecallTests.notationCases(at:))

    /// The cases whose recogniser form differs from the bare words because the mark is the only evidence of a boundary.
    static let markOnlyBoundaries: Set<String> = []

    /// Words a recogniser writes a comma before.
    private static let conjunctions: Set<String> = ["and", "or", "but", "if", "then"]

    /// Words a recogniser pauses before in a query, so it ends the clause before them with a stop.
    private static let clauseOpeners: Set<String> = [
        "from", "where", "join", "inner", "left", "order", "group", "having", "limit",
    ]

    /// The marks a recogniser writes at a pause.
    private static let pauseMarks: [Character] = [",", ".", ";", "!", "?"]

    /// The words as a recogniser writes them: a capital at the start, `stop` at each pause (before a conjunction or a query's clause) with a capital after a full stop, a stop at the end.
    static func recogniserForm(_ spoken: String, at destination: Destination, stop: String) -> String {
        var words = spoken.split(separator: " ").map(String.init)
        guard !words.isEmpty else { return spoken }
        for index in words.indices.dropFirst() where !(words[index - 1].last?.isPunctuation ?? true) {
            let word = words[index]
            let opensClause =
                destination == .sqlEditor && clauseOpeners.contains(word)
                && words[index - 1] != "left" && words[index - 1] != "inner"
            guard opensClause || conjunctions.contains(word) else { continue }
            words[index - 1] += stop
            if stop == "." { words[index] = word.prefix(1).uppercased() + word.dropFirst() }
        }
        words[0] = words[0].prefix(1).uppercased() + words[0].dropFirst()
        if !(words[words.count - 1].last?.isPunctuation ?? true) { words[words.count - 1] += "." }
        return words.joined(separator: " ")
    }

    private func written(_ testCase: EvaluationCase, spoken: String) async throws -> String {
        let base = testCase.transformationRequest()
        let request = TransformationRequest(
            transcription: Transcription(
                text: spoken, detectedLanguage: base.transcription.detectedLanguage, segments: []),
            context: base.context, situation: base.situation, vocabulary: base.vocabulary)
        return try await RuleBasedTransformer().transform(request).text
    }

    /// The bare and the recogniser-style output of every case, by case and pause mark.
    private func bothForms() async throws -> [(id: String, bare: String, recognised: String)] {
        var outputs: [(id: String, bare: String, recognised: String)] = []
        for testCase in Self.cases {
            let bare = try await written(testCase, spoken: testCase.spoken)
            for stop in [",", "."] {
                let recognised = try await written(
                    testCase, spoken: Self.recogniserForm(testCase.spoken, at: testCase.destination, stop: stop))
                outputs.append(("\(testCase.id) \(stop)", bare, recognised))
            }
        }
        return outputs
    }

    @Test("writes the recogniser form as the bare words, except where the mark is the only boundary")
    func sameAcrossForms() async throws {
        let outputs = try await bothForms()
        let differing = outputs.filter { $0.bare != $0.recognised }
        print("recogniser forms: \(Self.cases.count) cases, \(differing.count) of \(outputs.count) forms differ")
        for output in differing where !Self.markOnlyBoundaries.contains(output.id) {
            Issue.record("\(output.id): \(output.bare.debugDescription) vs \(output.recognised.debugDescription)")
        }
        #expect(Set(differing.map(\.id)) == Self.markOnlyBoundaries)
    }

    @Test("never writes a pause mark the recogniser added")
    func addsNoRecogniserMark() async throws {
        for output in try await bothForms() {
            for mark in Self.pauseMarks {
                let added = output.recognised.count(where: { $0 == mark }) - output.bare.count(where: { $0 == mark })
                #expect(added <= 0, "\(output.id) keeps \(added) recogniser \(mark): \(output.recognised.debugDescription)")
            }
        }
    }
}
