// Tests the clean-up scorer, runner, report and corpus hygiene.
import UttrflowAI
import Synchronization
import Testing

@testable import UttrflowCore
@testable import UttrflowEval

@Suite("Scorer")
struct ScorerTests {
    private func reference(
        expected: String, mustKeep: [String] = [], mustNotAdd: [String] = []
    ) -> EvaluationCase {
        EvaluationCase(
            id: "case", category: .everyday, spoken: "spoken",
            expected: expected, mustKeep: mustKeep, mustNotAdd: mustNotAdd
        )
    }

    private func shaped(expected: String, begin: String? = nil, end: String? = nil) -> EvaluationCase {
        EvaluationCase(
            id: "case", category: .everyday, spoken: "spoken", expected: expected,
            mustBeginWith: begin, mustEndWith: end)
    }

    /// Case and a final mark are what the destination cases are about, so they are looked at literally.
    @Test("checks a required beginning and ending exactly, case included")
    func checksShape() {
        let reference = shaped(expected: "the report is attached.", begin: "the report", end: ".")
        #expect(Scorer.score("the report is attached.", against: reference).passed)

        let capitalised = Scorer.score("The report is attached.", against: reference)
        #expect(capitalised.brokeShape == ["the report"])
        #expect(!capitalised.passed)

        let unfinished = Scorer.score("the report is attached", against: reference)
        #expect(unfinished.brokeShape == ["."])
        #expect(!unfinished.passed)

        #expect(Scorer.score("The Report Is Attached", against: reference).brokeShape == ["the report", "."])
    }

    @Test("asks nothing of the shape when the case says nothing about it")
    func shapeIsOptional() {
        #expect(Scorer.score("HELLO THERE", against: shaped(expected: "hello there.")).brokeShape.isEmpty)
    }

    @Test("scores an exact match perfectly")
    func exactMatch() {
        let score = Scorer.score("Hello there.", against: reference(expected: "Hello there."))
        #expect(score.similarity == 1)
        #expect(score.isExact)
        #expect(score.passed)
    }

    /// Several phrasings of a sentence are correct; punctuation and case are not measured.
    @Test(
        "ignores case and punctuation",
        arguments: ["hello there", "HELLO THERE!", "Hello, there.", "  hello   there  "]
    )
    func ignoresSurfaceDifferences(produced: String) {
        #expect(Scorer.score(produced, against: reference(expected: "Hello there.")).similarity == 1)
    }

    @Test("scores an unrelated answer at zero")
    func unrelated() {
        let score = Scorer.score("Paris", against: reference(expected: "What is the capital of France?"))
        #expect(score.similarity < 0.4)
        #expect(!score.passed)
    }

    @Test("scores a partial match in between")
    func partialMatch() {
        let score = Scorer.score(
            "Hello there friend", against: reference(expected: "Hello there my old friend")
        )
        #expect(score.similarity > 0.5 && score.similarity < 1)
    }

    /// Recall alone would reward a model that repeats itself.
    @Test("does not reward padding the answer")
    func penalisesPadding() {
        let padded = Scorer.score(
            "hello there hello there hello there", against: reference(expected: "hello there")
        )
        #expect(padded.similarity < 0.6)
    }

    @Test("treats two empty strings as agreeing, and one empty as disagreeing")
    func emptyHandling() {
        #expect(Scorer.score("", against: reference(expected: "")).similarity == 1)
        #expect(Scorer.score("", against: reference(expected: "hello")).similarity == 0)
        #expect(Scorer.score("hello", against: reference(expected: "")).similarity == 0)
    }

    /// Losing a name or a number is reported separately rather than folded into a score.
    @Test("reports every required word that went missing")
    func reportsLostWords() {
        let score = Scorer.score(
            "I'll be late to the meeting",
            against: reference(expected: "Hey John, I'll be 20 minutes late.", mustKeep: ["John", "20"])
        )
        #expect(score.lost == ["John", "20"])
        #expect(!score.keptEverythingRequired)
        #expect(!score.passed)
    }

    @Test("accepts a required word in any case")
    func requiredWordCaseInsensitive() {
        let score = Scorer.score(
            "hey john", against: reference(expected: "Hey John.", mustKeep: ["John"])
        )
        #expect(score.keptEverythingRequired)
    }

    /// "get_user" tokenises to two words, and both present separately is not the term surviving.
    @Test("requires a multi-word term to survive as a run, not scattered")
    func multiWordTerm() {
        let intact = Scorer.score(
            "call get_user now", against: reference(expected: "Call get_user now.", mustKeep: ["get_user"])
        )
        #expect(intact.keptEverythingRequired)

        let scattered = Scorer.score(
            "get the user", against: reference(expected: "Call get_user now.", mustKeep: ["get_user"])
        )
        #expect(!scattered.keptEverythingRequired)
    }

    /// Similarity alone would pass a rewrite that dropped someone's name.
    @Test("fails a close rewrite that still lost a required word")
    func closeButLostAName() {
        let score = Scorer.score(
            "Hey, I'll be 20 minutes late to the meeting.",
            against: reference(
                expected: "Hey John, I'll be 20 minutes late to the meeting.", mustKeep: ["John"]
            )
        )
        #expect(score.similarity > 0.8)
        #expect(!score.passed, "high similarity must not excuse losing a name")
    }

    @Test("passes only when both close enough and complete")
    func passingRequiresBoth() {
        #expect(
            CaseScore(caseID: "a", similarity: 0.9, keptEverythingRequired: true, lost: [], isExact: false)
                .passed)
        #expect(
            !CaseScore(
                caseID: "a", similarity: 0.9, keptEverythingRequired: false, lost: ["x"], isExact: false
            ).passed)
        #expect(
            !CaseScore(caseID: "a", similarity: 0.7, keptEverythingRequired: true, lost: [], isExact: false)
                .passed)
    }

    /// A brace in a message to a colleague is the model answering, and "{" has no words to match on.
    @Test("catches a punctuation-only guard in the answer")
    func punctuationGuardFires() {
        let score = Scorer.score(
            "func failed(orders: [Order]) -> [Order] { orders.filter(\\.failed) }",
            against: reference(
                expected: "We need something that hands back the orders that failed.",
                mustNotAdd: ["{"]
            )
        )
        #expect(score.invented == ["{"])
        #expect(!score.passed)
    }

    /// A wordless guard that fired on prose would fail every model on a fault in the scorer.
    @Test("leaves a punctuation-only guard unfired when the answer stayed prose")
    func punctuationGuardStaysQuiet() {
        let prose = "We need something that hands back the orders that failed."
        let score = Scorer.score(prose, against: reference(expected: prose, mustNotAdd: ["{"]))
        #expect(score.invented.isEmpty)
        #expect(score.passed)
    }

    @Test("never fires a guard that holds nothing", arguments: ["", " ", "\n"])
    func emptyGuardNeverFires(emptyGuard: String) {
        let score = Scorer.score(
            "Anything at all.", against: reference(expected: "Anything at all.", mustNotAdd: [emptyGuard])
        )
        #expect(score.invented.isEmpty, "an empty guard accused an answer of inventing nothing")
        #expect(score.passed)
    }

    /// The literal path is for punctuation only, or "cat" convicts every mention of concatenating.
    @Test("holds a word guard to whole words")
    func wordGuardRespectsWordBoundaries() {
        let inside = Scorer.score(
            "We concatenate the strings.",
            against: reference(expected: "We concatenate the strings.", mustNotAdd: ["cat"])
        )
        #expect(inside.invented.isEmpty)

        let onItsOwn = Scorer.score(
            "The cat is out.", against: reference(expected: "The dog is out.", mustNotAdd: ["cat"])
        )
        #expect(onItsOwn.invented == ["cat"])
    }

    /// "ORDER BY" is two ordinary words, and a sentence using both is not a model writing SQL.
    @Test("fires a multi-word guard only on a consecutive run")
    func multiWordGuardNeedsARun() {
        let scattered = Scorer.score(
            "Order the parts by the date they were promised.",
            against: reference(
                expected: "Order the parts by the date they were promised.", mustNotAdd: ["ORDER BY"]
            )
        )
        #expect(scattered.invented.isEmpty)

        let run = Scorer.score(
            "SELECT name FROM users ORDER BY name;",
            against: reference(expected: "List the users by name.", mustNotAdd: ["ORDER BY"])
        )
        #expect(run.invented == ["ORDER BY"])
    }
}

@Suite("EvaluationReport")
struct EvaluationReportTests {
    private func score(_ id: String, similarity: Double, kept: Bool = true) -> CaseScore {
        CaseScore(
            caseID: id, similarity: similarity, keptEverythingRequired: kept,
            lost: kept ? [] : ["name"], isExact: similarity == 1
        )
    }

    @Test("summarises how many cases passed")
    func passRate() {
        let report = EvaluationReport(
            label: "m",
            scores: [score("a", similarity: 1), score("b", similarity: 0.5), score("c", similarity: 0.9)],
            durations: []
        )
        #expect(abs(report.passRate - 2.0 / 3.0) < 0.001)
        #expect(abs(report.meanSimilarity - 0.8) < 0.001)
    }

    @Test("reports nothing rather than dividing by zero on an empty run")
    func emptyReport() {
        let report = EvaluationReport(label: "m", scores: [], durations: [])
        #expect(report.passRate == 0)
        #expect(report.meanSimilarity == 0)
        #expect(report.medianDuration == .zero)
        #expect(report.slowestDuration == .zero)
    }

    @Test("lists the cases that lost a required word")
    func lostWordCases() {
        let report = EvaluationReport(
            label: "m", scores: [score("a", similarity: 1), score("b", similarity: 0.95, kept: false)],
            durations: []
        )
        #expect(report.casesLosingRequiredWords.map(\.caseID) == ["b"])
    }

    /// The middle case describes the usual wait; a mean is dragged by one slow start.
    @Test("reports the middle and the worst latency")
    func latencies() {
        let report = EvaluationReport(
            label: "m", scores: [],
            durations: [.milliseconds(100), .milliseconds(900), .milliseconds(300)]
        )
        #expect(report.medianDuration == .milliseconds(300))
        #expect(report.slowestDuration == .milliseconds(900))
    }
}

@Suite("EvaluationCorpus")
struct EvaluationCorpusTests {
    @Test("covers every kind of case the product has to handle")
    func coversEveryCategory() {
        for category in EvaluationCase.Category.allCases {
            #expect(!EvaluationCorpus.cases(in: category).isEmpty, "no cases for \(category)")
        }
    }

    @Test("gives every case a unique identifier, so a result can be traced")
    func uniqueIdentifiers() {
        let ids = EvaluationCorpus.all.map(\.id)
        #expect(Set(ids).count == ids.count)
    }

    @Test("includes the languages Apple's model cannot handle")
    func includesHindi() {
        #expect(!EvaluationCorpus.cases(for: .hindi).isEmpty)
    }

    /// A reference that already lost a required word would score every model wrongly.
    @Test("keeps every required word in its own reference answer")
    func referencesAreSelfConsistent() {
        for testCase in EvaluationCorpus.all {
            let score = Scorer.score(testCase.expected, against: testCase)
            #expect(score.keptEverythingRequired, "\(testCase.id) lost \(score.lost)")
            #expect(score.similarity == 1, "\(testCase.id) does not match itself")
        }
    }

    @Test("never uses the raw transcript as its own reference")
    func referencesDifferFromInput() {
        for testCase in EvaluationCorpus.all {
            #expect(testCase.spoken != testCase.expected, "\(testCase.id) expects no change at all")
        }
    }

    @Test("is large enough to distinguish models")
    func hasEnoughCases() {
        #expect(EvaluationCorpus.all.count >= 20)
    }
}

@Suite("EvaluationRunner")
struct EvaluationRunnerTests {
    private let cases = [
        EvaluationCase(
            id: "a", category: .everyday, spoken: "um hello", expected: "Hello.",
            mustKeep: ["hello"]),
        EvaluationCase(
            id: "b", category: .everyday, spoken: "uh goodbye", expected: "Goodbye.",
            mustKeep: ["goodbye"]),
    ]

    @Test("scores every case it was given, in order")
    func scoresEveryCase() async {
        let report = await EvaluationRunner(cases: cases).run(label: "perfect") { .produced($0.expected) }

        #expect(report.label == "perfect")
        #expect(report.scores.map(\.caseID) == ["a", "b"])
        #expect(report.passRate == 1)
        #expect(report.durations.count == 2)
    }

    /// A model that refuses a third of the corpus should score badly, not go unmeasured.
    @Test("records a refusal as a failed case and keeps going")
    func failureDoesNotAbandonTheRun() async {
        struct Refused: Error {}
        let report = await EvaluationRunner(cases: cases).run(label: "flaky") { testCase in
            if testCase.id == "a" { throw Refused() }
            return .produced(testCase.expected)
        }

        #expect(report.scores.count == 2)
        #expect(report.scores[0].similarity == 0, "a refusal scores zero, not nothing")
        #expect(report.scores[1].passed)
        #expect(report.passRate == 0.5)
    }

    @Test("reports progress before each case")
    func reportsProgress() async {
        let seen = Mutex<[String]>([])
        _ = await EvaluationRunner(cases: cases).run(
            label: "m", onCase: { testCase in seen.withLock { $0.append(testCase.id) } }
        ) { .produced($0.expected) }

        #expect(seen.withLock { $0 } == ["a", "b"])
    }

    @Test("defaults to the whole corpus")
    func defaultsToFullCorpus() async {
        let report = await EvaluationRunner().run(label: "m") { .produced($0.expected) }
        #expect(report.scores.count == EvaluationCorpus.all.count)
    }

    @Test("measures nothing gracefully when given no cases")
    func emptyCorpus() async {
        let report = await EvaluationRunner(cases: []).run(label: "m") { .produced($0.expected) }
        #expect(report.scores.isEmpty)
        #expect(report.passRate == 0)
    }

    /// A 16 GB laptop is a target, and a model that wins on quality but needs 12 GB has not won.
    @Test("reads this process's real memory use")
    func measuresMemory() {
        let footprint = MemoryFootprint.current()
        #expect(footprint != nil)
        #expect((footprint ?? 0) > 1_000_000, "a running process uses more than a megabyte")
    }
}

@Suite("Declining a case")
struct DeclineTests {
    private let cases = [
        EvaluationCase(id: "en", category: .everyday, spoken: "um hello", expected: "Hello."),
        EvaluationCase(
            id: "hi", category: .multilingual, language: .hindi, spoken: "नमस्ते",
            expected: "नमस्ते।"),
    ]

    /// An engine that correctly refuses a language it does not know has behaved well.
    @Test("keeps a refusal out of the score entirely")
    func declineDoesNotCountAgainstTheScore() async {
        let report = await EvaluationRunner(cases: cases).run(label: "declines-hindi") { testCase in
            testCase.language == .hindi ? .declined : .produced(testCase.expected)
        }

        #expect(report.declinedCount == 1)
        #expect(report.attempted.count == 1)
        #expect(report.passRate == 1, "the one attempted case passed")
        #expect(report.meanSimilarity == 1)
    }

    @Test("never counts a declined case as passing")
    func declinedIsNotPassing() {
        let declined = CaseScore(
            caseID: "x", similarity: 1, keptEverythingRequired: true, lost: [], isExact: true,
            declined: true)
        #expect(!declined.passed)
    }

    @Test("does not blame a declining engine for words it never had a chance to keep")
    func declineIsNotWordLoss() async {
        let report = await EvaluationRunner(cases: cases).run(label: "m") { _ in .declined }
        #expect(report.casesLosingRequiredWords.isEmpty)
        #expect(report.passRate == 0, "an engine that declines everything has proved nothing")
    }
}

@Suite("The corpus and the prompt must not overlap")
struct CorpusIndependenceTests {
    /// Compares on words alone, so punctuation or case cannot hide a reused sentence.
    private func normalise(_ text: String) -> String {
        Scorer.tokens(text).joined(separator: " ")
    }

    /// A worked example that is a verbatim corpus case scores the model on answers it has been shown.
    @Test("no corpus case appears among any block's worked examples")
    func corpusIsNotInThePrompt() {
        let examples = Set(PromptBuilder.standard.allWorkedExamples.map(normalise))
        for testCase in EvaluationCorpus.all {
            #expect(!examples.contains(normalise(testCase.spoken)), "\(testCase.id) is in the prompt")
            #expect(
                !examples.contains(normalise(testCase.expected)),
                "\(testCase.id)'s answer is in the prompt")
        }
    }

    /// An input that closely matches an example can make a model answer with a different example's text.
    @Test("no corpus case is a near-copy of any block's worked example")
    func corpusIsNotNearlyInThePrompt() {
        for testCase in EvaluationCorpus.all {
            let spoken = Set(Scorer.tokens(testCase.spoken))
            guard spoken.count >= 5 else { continue }
            for example in PromptBuilder.standard.allWorkedExamples {
                let overlap = spoken.intersection(Scorer.tokens(example))
                let share = Double(overlap.count) / Double(spoken.count)
                #expect(share < 0.7, "\(testCase.id) overlaps a worked example by \(Int(share * 100))%")
            }
        }
    }

    @Test("finds every block's worked examples, both halves of each")
    func readsTheExamples() {
        let examples = PromptBuilder.standard.allWorkedExamples
        let shown = Set(
            (PromptContract.examples + PromptBlocks.standard.values.flatMap(\.examples)).flatMap(\.sentences))
        #expect(
            Set(examples) == shown && examples.count == shown.count,
            "expected both halves of every block's examples")
        #expect(examples.contains("When does the library close on Sunday?"))
        #expect(examples.contains("42 units shipped in week 9"))
        for destination in Destination.allCases {
            #expect(Set(PromptBuilder.standard.workedExamples(for: destination)).isSubset(of: Set(examples)))
        }
    }

    /// Rules cannot change alphabet, so romanised references measure clean-up rather than doing nothing.
    @Test("expects Hindi written in the Latin alphabet")
    func hindiReferencesAreRomanised() {
        for testCase in EvaluationCorpus.cases(for: .hindi) {
            #expect(
                testCase.expected.allSatisfy { !("\u{0900}"..."\u{097F}").contains($0) },
                "\(testCase.id) still expects Devanagari")
            #expect(
                testCase.spoken.contains { ("\u{0900}"..."\u{097F}").contains($0) },
                "\(testCase.id) has nothing to romanise")
        }
    }
}
