import Testing

@testable import UttrflowAI
@testable import UttrflowCore
@testable import UttrflowEval

/// The meaning guard's false-accept rate per class of model error. See `Docs/mutation-guard.md`.
@Suite("Meaning guard false accepts over a classed model-error set")
struct MeaningGuardFalseAcceptTests {
    /// Accepted mutations per class at the last measurement; the gate lets each fall and never rise.
    static let baseline: [ModelErrorClass: Int] = [.dropContentWord: 2, .swapWords: 1, .appendClause: 1]

    struct Judged {
        let id: String
        let errorClass: ModelErrorClass
        let rewrite: String
        let accepted: Bool
    }

    /// Mutations judged per class: enough for a rate, few enough for the suite. `make bakeoff` judges all.
    static let perClass = 40

    /// Judges an even spread of mutations of expected texts the guard accepts, as the engine judges a rewrite.
    static func judged() async -> [Judged] {
        let guarder = MeaningPreservationGuard()
        var correct: [String: Bool] = [:]
        var judged: [Judged] = []
        for (sample, errorClass, rewrite) in ModelErrorClass.mutations(
            of: EvaluationCorpus.all, perClass: perClass)
        {
            let request = sample.transformationRequest()
            if correct[sample.id] == nil {
                correct[sample.id] = await guarder.verdict(onReference: sample.expected, for: request)
                    .isAccepted
            }
            guard correct[sample.id] == true else { continue }
            let verdict = await guarder.verdict(onReference: rewrite, for: request)
            judged.append(
                Judged(id: sample.id, errorClass: errorClass, rewrite: rewrite, accepted: verdict.isAccepted))
        }
        return judged
    }

    @Test("over a hundred cases, each class lets through exactly its baseline, so a fix lowers it")
    func falseAcceptsOnlyFall() async {
        let all = await Self.judged()
        print("meaning guard false accepts over \(all.count) mutations of \(Set(all.map(\.id)).count) cases")
        #expect(Set(all.map(\.id)).count >= 100)
        for errorClass in ModelErrorClass.allCases {
            let ofClass = all.filter { $0.errorClass == errorClass }
            let accepted = ofClass.filter(\.accepted)
            print("  \(errorClass)  \(accepted.count) of \(ofClass.count)")
            for mutation in accepted { print("    \(mutation.id)  \(mutation.rewrite)") }
            #expect(ofClass.count >= 20, "\(errorClass) has too few mutations")
            #expect(
                accepted.count == Self.baseline[errorClass, default: 0],
                "\(errorClass) accepts \(accepted.count); the baseline says \(Self.baseline[errorClass, default: 0])"
            )
        }
    }

    @Test(
        "each class makes the error it names",
        arguments: [
            (ModelErrorClass.dropContentWord, "Send the report today.", "The report today."),
            (.addNegation, "The build is ready.", "The build is not ready."),
            (.swapWords, "We send report today.", "We report send today."),
            (.changeNumber, "Meet at 5 pm.", "Meet at 6 pm."),
            (.appendClause, "Ship it.", "Ship it. Also remember to book the meeting room."),
            (
                .answerInsteadOfTidy, "Ship it.",
                "Sure, I can help with that. What would you like me to change?"
            ),
            (.translate, "Send the file and the notes.", "Send el file y el notes."),
            (.wrapInLabel, "Ship it.", "Here is the cleaned text: Ship it."),
            (
                .moveWordAcrossSentence, "Please send the report. Then call me.",
                "Please the report. Then call me send."
            ),
        ]
    )
    func mutates(errorClass: ModelErrorClass, text: String, expected: String) {
        #expect(errorClass.mutate(text, seed: 0) == expected)
    }

    @Test(
        "a class with nothing to act on makes no mutation",
        arguments: [
            (ModelErrorClass.dropContentWord, "Ship it."), (.addNegation, "Ship it."),
            (.swapWords, "Ship it."),
            (.changeNumber, "Ship it."), (.translate, "Ship it."), (.moveWordAcrossSentence, "Ship it."),
        ]
    )
    func leavesTextWithoutATarget(errorClass: ModelErrorClass, text: String) {
        #expect(errorClass.mutate(text, seed: 0) == nil)
    }

    @Test("a per-class limit keeps that many of each class, spread over the corpus")
    func samplesEvenly() {
        let all = ModelErrorClass.mutations(of: EvaluationCorpus.all)
        let sampled = ModelErrorClass.mutations(of: EvaluationCorpus.all, perClass: 20)
        for errorClass in ModelErrorClass.allCases {
            let ofClass = sampled.filter { $0.errorClass == errorClass }
            #expect(ofClass.count == min(20, all.count { $0.errorClass == errorClass }))
        }
        #expect(Set(sampled.map(\.sample.id)).count > 100)
    }
}
