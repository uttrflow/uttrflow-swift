import Testing
import UttrflowCore
import UttrflowTestSupport

@testable import UttrflowAI
@testable import UttrflowEval

/// Holds every pass to the numbers, units and negators in their input, over the corpora and generated sentences.
@Suite("Numbers, units and negators across the cleaning passes")
struct IntegrityCorpusTests {
    /// The cases where a pass alters or drops a protected word, once per pipeline that does it.
    static let known: [String: [IntegrityViolation]] = [:]

    /// The passes a rewrite is handed the result of, and the whole rules path.
    static let pipeline = CleaningPipeline.beforeModel(for: .standard(for: .plain), situation: .unknown)
    static let rules = CleaningPipeline.standard(for: .standard(for: .plain), situation: .unknown)

    static func violations(spoken: String) -> [IntegrityViolation] {
        [pipeline, rules].flatMap {
            IntegrityAudit.violations(in: $0.run(Draft(text: spoken)), grants: $0.grants)
        }
    }

    @Test("finds a violation only in the evaluation cases that record one", arguments: EvaluationCorpus.all)
    func evaluationCases(testCase: EvaluationCase) {
        let request = testCase.transformationRequest()
        let model = CleaningPipeline.beforeModel(
            for: .standard(for: request.situation.destination), situation: request.situation)
        let rules = RuleBasedTransformer.pipeline(for: request, steps: .default)
        let found = [model, rules].flatMap {
            IntegrityAudit.violations(
                in: $0.run(Draft(transcription: request.transcription)), grants: $0.grants)
        }
        #expect(found == Self.known[testCase.id] ?? [], "\(testCase.id)")
    }

    @Test("finds none in the transcription passages", arguments: TranscriptionCorpus.all)
    func transcriptionPassages(passage: TranscriptionCase) {
        #expect(Self.violations(spoken: passage.romanised).isEmpty, "\(passage.id)")
    }

    @Test("names only cases the corpus holds")
    func namesRealCases() {
        #expect(Set(Self.known.keys).isSubset(of: Set(EvaluationCorpus.all.map(\.id))))
    }

    /// A spoken amount and the digits it is written with.
    static let amounts = [
        ("fifteen", "15"), ("twenty five", "25"), ("two hundred", "200"), ("three point five", "3.5"),
        ("forty", "40"), ("seven", "7"), ("one hundred and fifty", "150"), ("12", "12"), ("250", "250"),
        ("3.5", "3.5"),
    ]

    /// A sentence of a dose, a count or a duration, with a negator or without one, and what it must keep.
    struct Sentence {
        let spoken: String
        let amount: String
        let digits: String
        let unit: String
        let negator: String

        init(_ random: inout Seeded) {
            let (amount, digits) = random.pick(IntegrityCorpusTests.amounts)
            unit = random.pick(["mg", "milligrams", "grams", "kg", "hours", "days", "ml", "g", "l", "s", "h"])
            negator = random.pick(["", "not", "never", "no", "don't", "cannot", "nothing"])
            let lead = random.pick(["take", "give the patient", "I said", "the invoice is", "wait"])
            let tail = random.pick(["twice daily", "before food", "in total", ""])
            self.amount = amount
            self.digits = digits
            spoken = [lead, negator, amount, unit, tail].filter { !$0.isEmpty }.joined(separator: " ")
        }
    }

    @Test("keeps every number, unit and negator in 2,000 generated sentences")
    func generatedSentences() {
        var random = Seeded(seed: 4044)
        var found: [String] = []
        for _ in 0..<2000 {
            let sentence = Sentence(&random)
            for pipeline in [Self.pipeline, Self.rules] {
                let draft = pipeline.run(Draft(text: sentence.spoken))
                let words = draft.text.lowercased().split(separator: " ").map { WordShape(String($0)).key }
                let kept =
                    (draft.text.contains(sentence.digits)
                        || draft.text.lowercased().contains(sentence.amount))
                    && words.contains(sentence.unit.lowercased())
                    && (sentence.negator.isEmpty
                        || words.contains { MeaningPreservationGuard.isNegation($0) })
                let violations = IntegrityAudit.violations(in: draft, grants: pipeline.grants)
                if !kept || !violations.isEmpty {
                    found.append("\(sentence.spoken) -> \(draft.text) \(violations)")
                }
            }
        }
        #expect(found.isEmpty, "\(found.prefix(10))")
    }

    @Test("names the pass that changes a unit or drops a negator")
    func namesThePass() {
        var draft = Draft(text: "take not 5 mg")
        draft.words[1].state = .removed(by: .fillers)
        draft.words[3].text = "g"
        draft.words[3].state = .replaced(by: .numberForms, from: "mg")
        #expect(
            IntegrityAudit.violations(in: draft, grants: [.fillers: .sound, .numberForms: .conversion])
                == [
                    IntegrityViolation(pass: .fillers, kind: .negator, heard: "not"),
                    IntegrityViolation(pass: .numberForms, kind: .unit, heard: "mg"),
                ])
    }

    @Test("names the pass that changes a numeral")
    func namesNumeralPass() {
        var draft = Draft(text: "take 15 mg")
        draft.words[1].text = "50"
        draft.words[1].state = .replaced(by: .numberForms, from: "15")
        #expect(
            IntegrityAudit.violations(in: draft, grants: [:])
                == [IntegrityViolation(pass: .numberForms, kind: .number, heard: "15")])
    }

    @Test("names the pass that drops or changes a unit of one letter")
    func namesLetterPass() {
        var dropped = Draft(text: "take 5 g daily")
        dropped.words[2].state = .removed(by: .fillers)
        var swapped = Draft(text: "take 5 g daily")
        swapped.words[2].text = "kg"
        swapped.words[2].state = .replaced(by: .numberForms, from: "g")
        #expect(
            IntegrityAudit.violations(in: dropped, grants: [:])
                == [IntegrityViolation(pass: .fillers, kind: .unit, heard: "g")])
        #expect(
            IntegrityAudit.violations(in: swapped, grants: [:])
                == [IntegrityViolation(pass: .numberForms, kind: .unit, heard: "g")])
    }

    @Test("passes a unit letter joined to its number or to the letter after it")
    func passesJoinedLetter() {
        var number = Draft(text: "take 15 k daily")
        number.words[1].text = "15k"
        number.words[1].state = .replaced(by: .numberForms, from: "15")
        number.words[2].state = .removed(by: .numberForms)
        var spelled = Draft(text: "take 81 m g daily")
        spelled.words[2].text = "mg"
        spelled.words[2].state = .replaced(by: .spelledInitialism, from: "m")
        spelled.words[3].state = .removed(by: .spelledInitialism)
        #expect(IntegrityAudit.violations(in: number, grants: [:]).isEmpty)
        #expect(IntegrityAudit.violations(in: spelled, grants: [:]).isEmpty)
        var missingNumber = number
        missingNumber.words[1].text = "15"
        #expect(
            IntegrityAudit.violations(in: missingNumber, grants: [:])
                == [IntegrityViolation(pass: .numberForms, kind: .unit, heard: "k")])
        var missingSpelled = spelled
        missingSpelled.words[2].text = "g"
        #expect(
            IntegrityAudit.violations(in: missingSpelled, grants: [:])
                == [IntegrityViolation(pass: .spelledInitialism, kind: .unit, heard: "m")])
    }

    @Test("does not take an untouched word that starts with the letter for the unit")
    func untouchedNeighbour() {
        var draft = Draft(text: "take 5 g green tea")
        draft.words[2].state = .removed(by: .numberForms)
        #expect(
            IntegrityAudit.violations(in: draft, grants: [:])
                == [IntegrityViolation(pass: .numberForms, kind: .unit, heard: "g")])
        var rewritten = draft
        rewritten.words[3].text = "greens"
        rewritten.words[3].state = .replaced(by: .numberForms, from: "green")
        #expect(
            IntegrityAudit.violations(in: rewritten, grants: [:])
                == [IntegrityViolation(pass: .numberForms, kind: .unit, heard: "g")])
    }
}
