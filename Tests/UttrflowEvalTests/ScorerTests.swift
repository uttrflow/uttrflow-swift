// Tests the clean-up scorer, runner, report and corpus hygiene.
import Foundation
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

    @Test("fails a long rewrite that closes fewer sentences than the case requires")
    func failsTooFewSentences() {
        let reference = EvaluationCase(
            id: "case", category: .longInput, spoken: "spoken",
            expected: "One thing. Two things. Three things.", minimumSentences: 2)
        let runOn = Scorer.score("One thing two things three things.", against: reference)
        #expect(runOn.brokeShape == ["closes 2 sentences"])
        #expect(!runOn.passed)
        #expect(Scorer.score("One thing. Two things. Three things.", against: reference).passed)
    }

    @Test("names at least three hundred words in its long-input case, which is what the category guards")
    func longInputIsLong() throws {
        let testCase = try #require(EvaluationCorpus.cases(in: .longInput).first)
        #expect(testCase.spoken.split(whereSeparator: \.isWhitespace).count >= 300)
        #expect(Scorer.score(testCase.expected, against: testCase).passed)
    }

    @Test("fails a rewrite that drops a reference word even when similarity clears the floor")
    func failsAnyDeletedWord() {
        let reference = reference(expected: "My manager wants the slides by noon.")
        let shortened = Scorer.score("My manager wants the slides.", against: reference)
        #expect(shortened.similarity >= 0.8)
        #expect(shortened.deleted == ["by", "noon"])
        #expect(!shortened.passed)

        let whole = Scorer.score("My manager wants the slides by noon.", against: reference)
        #expect(whole.deleted.isEmpty)
        #expect(whole.passed)
    }

    /// Case and a final mark are measured separately from word agreement.
    @Test("checks a required beginning and ending exactly, case included")
    func checksShape() {
        let reference = shaped(expected: "the report is attached.", begin: "the report", end: ".")
        #expect(Scorer.score("the report is attached.", against: reference).passed)

        let capitalised = Scorer.score("The report is attached.", against: reference)
        #expect(capitalised.brokeShape == [#"begins with "the report""#])
        #expect(!capitalised.passed)

        let unfinished = Scorer.score("the report is attached", against: reference)
        #expect(unfinished.brokeShape == [#"ends with ".""#])
        #expect(!unfinished.passed)

        #expect(
            Scorer.score("The Report Is Attached", against: reference).brokeShape == [
                #"begins with "the report""#, #"ends with ".""#,
            ])
    }

    /// A structured output has one written form, so a near miss in spacing or case is a miss.
    @Test("checks an exact form character for character and keeps it through the recogniser shape")
    func checksExactForm() {
        let reference = EvaluationCase(
            id: "case", category: .technical, spoken: "select star from orders",
            expected: "SELECT * FROM orders", expectedExact: "SELECT * FROM orders")
        #expect(Scorer.score("SELECT * FROM orders", against: reference).brokeShape.isEmpty)
        #expect(
            Scorer.score("SELECT *  FROM orders", against: reference).brokeShape == [
                #"is exactly "SELECT * FROM orders""#
            ])
        #expect(!Scorer.score("select * from orders", against: reference).passed)
        #expect(reference.shaped(.recogniser).expectedExact == "SELECT * FROM orders")
    }

    @Test("asks nothing of the shape when the case says nothing about it")
    func shapeIsOptional() {
        #expect(Scorer.score("HELLO THERE", against: shaped(expected: "hello there.")).brokeShape.isEmpty)
    }

    @Test("compares romanised Hindi by sound, so a spelling variant is not a lost word")
    func foldsRomanisedSpellings() {
        let hindi = EvaluationCase(
            id: "case", category: .multilingual, language: .hindi, spoken: "spoken",
            expected: "Mujhe theek nahi lag raha.")
        #expect(Scorer.score("Mujhe thik nahi lag raha.", against: hindi).similarity == 1)
        let english = reference(expected: "Mujhe theek nahi lag raha.")
        #expect(Scorer.score("Mujhe thik nahi lag raha.", against: english).similarity < 1)
    }

    @Test("scores an exact match perfectly")
    func exactMatch() {
        let score = Scorer.score("Hello there.", against: reference(expected: "Hello there."))
        #expect(score.similarity == 1)
        #expect(score.isExact)
        #expect(score.passed)
    }

    @Test("reports word, mark, and case accuracy independently")
    func scoresSurfaceMetrics() {
        let score = Scorer.score("i know the answer", against: reference(expected: "I know the answer."))
        #expect(score.similarity == 1)
        #expect(score.markAccuracy == 0)
        #expect(score.caseAccuracy < 1)
        #expect(!score.isExact)
    }

    @Test("exactness preserves punctuation and case but normalises whitespace")
    func exactnessNormalisesOnlyWhitespace() {
        #expect(Scorer.score("Hello   there.\n", against: reference(expected: "Hello there.")).isExact)
        #expect(!Scorer.score("hello there.", against: reference(expected: "Hello there.")).isExact)
        #expect(!Scorer.score("Hello there", against: reference(expected: "Hello there.")).isExact)
    }

    @Test("mark accuracy detects misplaced commas and extra sentence endings")
    func markAccuracyFindsPunctuationRegressions() {
        #expect(Scorer.score("Wait, now.", against: reference(expected: "Wait now.")).markAccuracy < 1)
        #expect(Scorer.score("400. And $20.", against: reference(expected: "400 And $20.")).markAccuracy < 1)
    }

    @Test("case accuracy catches altered word casing")
    func caseAccuracyFindsCaseRegression() {
        #expect(
            Scorer.score("YOY increased.", against: reference(expected: "YoY increased.")).caseAccuracy < 1)
    }

    /// Several phrasings of a sentence can keep full word similarity while surface scores differ.
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

    /// A bag of words scores a permutation perfectly, and reordering clauses is the edit Tier 3 forbids.
    @Test("does not score a clause moved as a clause kept")
    func penalisesReordering() {
        let swapped = Scorer.score(
            "We rejected the design but approved the budget.",
            against: reference(expected: "We approved the design but rejected the budget.")
        )
        #expect(swapped.similarity < 1)
        #expect(!swapped.passed)
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

    /// "()" has no words, so a word-only check reported it lost even when the answer was exactly "()".
    @Test("keeps a symbol-only requirement when the answer holds it literally")
    func symbolRequirementKeptLiterally() {
        let kept = Scorer.score("()", against: reference(expected: "()", mustKeep: ["()"]))
        #expect(kept.lost.isEmpty)
        #expect(kept.passed)

        let dropped = Scorer.score(
            "open close parenthesis", against: reference(expected: "()", mustKeep: ["()"]))
        #expect(dropped.lost == ["()"])
        #expect(!dropped.passed)
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

    /// The two words are in the text, but a full stop stands between them, so they are not one phrase.
    @Test("does not read a guard's run across the end of a sentence")
    func aRunStaysInsideOneSentence() {
        let across = Scorer.score(
            "Put in the order. By Friday it ships.",
            against: reference(expected: "Put in the order. By Friday it ships.", mustNotAdd: ["ORDER BY"])
        )
        #expect(across.invented.isEmpty)

        // An abbreviation's stop does not end a sentence, so a phrase either side of it is still one run.
        let abbreviated = Scorer.score(
            "Ship it at 4 p.m. sharp.",
            against: reference(expected: "Ship it at 4 p.m. sharp.", mustNotAdd: ["p.m. sharp"])
        )
        #expect(abbreviated.invented == ["p.m. sharp"])
    }

    /// A required phrase is held to the same rule, so a sentence end does not satisfy it either.
    @Test("does not satisfy a required phrase across the end of a sentence")
    func aRequirementStaysInsideOneSentence() {
        let across = Scorer.score(
            "Put in the order. By Friday it ships.",
            against: reference(
                expected: "Put in the order by Friday.", mustKeep: ["order by"])
        )
        #expect(across.lost == ["order by"])
        #expect(!across.keptEverythingRequired)
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

    @Test("measured Hindi failures score as invented content while the romanised floor passes")
    func measuredHindiFailures() async throws {
        let failures = [
            ("hindi-translation-refused", "Meeting is at four o'clock, no no, five o'clock."),
            (
                "hindi-worked-example-refused",
                "Main aaj ke standup mein deployment ke baare mein baat karunga."
            ),
        ]
        for (id, badAnswer) in failures {
            let testCase = try #require(EvaluationCorpus.all.first { $0.id == id })
            let badScore = Scorer.score(badAnswer, against: testCase)
            #expect(!badScore.passed, "\(id) accepted the observed bad answer")
            #expect(!badScore.invented.isEmpty, "\(id) has no invented-content guard")

            let floor = try await RuleBasedTransformer().transform(testCase.transformationRequest()).text
            #expect(Scorer.score(floor, against: testCase).passed, "\(id): \(floor)")
        }
    }

    /// A reference that already lost a required word would score every model wrongly.
    @Test("keeps every required word in its own reference answer")
    func referencesAreSelfConsistent() {
        let urlCase = EvaluationCorpus.all.first { $0.id == "fmt-token-url-path-stopped" }
        #expect(urlCase?.expected == "The url is https://example.com/docs.")
        #expect(urlCase?.mustKeep == ["https://example.com/docs"])
        for testCase in EvaluationCorpus.all {
            let score = Scorer.score(testCase.expected, against: testCase)
            #expect(score.keptEverythingRequired, "\(testCase.id) lost \(score.lost)")
            #expect(score.similarity == 1, "\(testCase.id) does not match itself")
        }
    }

    /// A leave-alone case is deliberate only when it pins the shape it guards; similarity alone would pass the raw input.
    @Test("uses the raw transcript as its reference only where the case pins the shape it guards")
    func referencesDifferFromInput() {
        for testCase in EvaluationCorpus.all where testCase.spoken == testCase.expected {
            let pinned =
                testCase.expectedExact != nil || testCase.mustBeginWith != nil || testCase.mustEndWith != nil
                || !testCase.mustNotAdd.isEmpty
            #expect(pinned, "\(testCase.id) expects no change at all and pins nothing")
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

    private func quotedFragments(in text: String) -> [String] {
        let pattern = #""([^"]+)""#
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return [] }
        let range = NSRange(text.startIndex..., in: text)
        return regex.matches(in: text, range: range).compactMap { match in
            guard let range = Range(match.range(at: 1), in: text) else { return nil }
            return String(text[range])
        }
    }

    /// Quoted fragments are checked whole from three words, stricter than the audit's default, since a rule quotes slips.
    private func knownContamination(in prompt: PromptBuilder) -> [(caseID: String, fragment: String)] {
        let instructions =
            [prompt.contract] + prompt.blocks.values.sorted { $0.id.rawValue < $1.id.rawValue }.map(\.rules)
        let fragments =
            instructions + instructions.flatMap(quotedFragments(in:))
            + prompt.contractExamples
            .flatMap(\.sentences)
            + prompt.blocks.values.sorted { $0.id.rawValue < $1.id.rawValue }.flatMap(\.examples).flatMap(
                \.sentences)
        let audit = ContaminationAudit(passages: ContaminationAudit.corpusPassages, shortestPhrase: 3)
        return fragments.flatMap { fragment in
            audit.findings(in: fragment, asset: "prompt").map { (caseID: $0.caseID, fragment: fragment) }
        }
    }

    /// Quoted rule fragments and worked examples cannot give a case's answer away.
    @Test("no corpus case appears in prompt rules or worked examples")
    func corpusIsNotInThePrompt() {
        #expect(knownContamination(in: .standard).isEmpty)
    }

    @Test("finds an exact corpus leak quoted in a rule")
    func detectsKnownRuleLeak() {
        let prompt = PromptBuilder(
            contract: "",
            contractExamples: [],
            blocks: [
                "plain": PromptBlock(
                    id: "plain", rules: #"Fix the slip: "there is three" → "there are three"."#,
                    examples: [])
            ])

        #expect(
            knownContamination(in: prompt).contains {
                $0.caseID == "agreement-there-is" && $0.fragment == "there is three"
            })
    }

    @Test("finds a corpus leak in either half of a worked example")
    func detectsKnownWorkedExampleLeak() {
        let prompt = PromptBuilder(
            contract: "",
            contractExamples: [
                WorkedExample(
                    spoken: "there is three of them waiting outside",
                    cleaned: "There are three of them waiting outside.")
            ],
            blocks: [:])

        #expect(
            knownContamination(in: prompt).contains {
                $0.caseID == "agreement-there-is"
                    && normalise($0.fragment) == "there is three of them waiting outside"
            })
    }

    @Test("finds a worked example that restates a run inside a longer corpus case")
    func detectsWorkedExampleRunLeak() {
        let prompt = PromptBuilder(
            contract: "",
            contractExamples: [
                WorkedExample(
                    spoken: "I'll probably be about 20 minutes late to the meeting",
                    cleaned: "I'll probably be about 20 minutes late to the meeting.")
            ],
            blocks: [:])

        #expect(
            knownContamination(in: prompt).contains {
                $0.caseID == "late-to-meeting"
                    && normalise($0.fragment) == "i ll probably be about 20 minutes late to the meeting"
            })
    }

    /// An input that closely matches a rule fragment or example can make a model repeat it.
    @Test("no corpus case is a near-copy of any prompt rule or worked example")
    func corpusIsNotNearlyInThePrompt() {
        let instructions =
            [PromptBuilder.standard.contract]
            + PromptBuilder.standard.blocks.values.sorted { $0.id.rawValue < $1.id.rawValue }.map(\.rules)
        let promptFragments =
            instructions.flatMap(quotedFragments(in:))
            + PromptBuilder.standard.contractExamples.flatMap(\.sentences)
            + PromptBuilder.standard.blocks.values.sorted { $0.id.rawValue < $1.id.rawValue }
            .flatMap(\.examples).flatMap(\.sentences)

        for testCase in EvaluationCorpus.all {
            let corpusWords = Set(Scorer.tokens(testCase.spoken))
            guard corpusWords.count >= 5 else { continue }
            for fragment in promptFragments {
                let fragmentWords = Set(Scorer.tokens(fragment))
                let share = Double(corpusWords.intersection(fragmentWords).count) / Double(corpusWords.count)
                #expect(
                    share < 0.7, "\(testCase.id) overlaps prompt fragment \(fragment) by \(Int(share * 100))%"
                )
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

    /// Hindi is spoken into the corpus in either alphabet, and every reference is written in the Latin one.
    @Test("expects Hindi written in the Latin alphabet")
    func hindiReferencesAreRomanised() {
        let devanagari: (Character) -> Bool = { ("\u{0900}"..."\u{097F}").contains($0) }
        for testCase in EvaluationCorpus.cases(for: .hindi) {
            #expect(!testCase.expected.contains(where: devanagari), "\(testCase.id) still expects Devanagari")
        }
        #expect(
            EvaluationCorpus.cases(for: .hindi).contains { $0.spoken.contains(where: devanagari) },
            "no Hindi case has Devanagari to romanise")
    }
}

/// A grammar case that asks for a repair must fail the sentence as spoken, or it credits a repair nobody made.
@Suite("Grammar cases require their repair")
struct GrammarRepairTests {
    /// The spoken words as a sentence, capitalised and closed the way the reference is, with nothing repaired.
    private static func unrepaired(_ testCase: EvaluationCase) -> String {
        let spoken = testCase.spoken.prefix(1).uppercased() + testCase.spoken.dropFirst()
        return testCase.expected.hasSuffix(".") ? spoken + "." : spoken
    }

    /// Whether the reference changes a word the speaker said, rather than only case and punctuation.
    private static func asksForARepair(_ testCase: EvaluationCase) -> Bool {
        Scorer.tokens(testCase.expected) != Scorer.tokens(testCase.spoken)
    }

    @Test(
        "fails the unrepaired sentence for every case that asks for a repair",
        arguments: EvaluationCorpus.cases(in: .grammar))
    func theSlipItselfFails(testCase: EvaluationCase) {
        // Dialect and messaging cases keep the speaker's grammar on purpose, so there is no slip to leave in.
        guard Self.asksForARepair(testCase) else { return }
        let score = Scorer.score(Self.unrepaired(testCase), against: testCase)
        #expect(!score.passed, "\(testCase.id) passes with the slip left in")
    }

    @Test("counts sixteen grammar cases as asking for a repair, so the check above is not vacuous")
    func repairCasesAreCounted() {
        #expect(EvaluationCorpus.cases(in: .grammar).filter(Self.asksForARepair).count == 16)
    }

    @Test(
        "passes the reference itself for every grammar case",
        arguments: EvaluationCorpus.cases(in: .grammar))
    func theReferencePasses(testCase: EvaluationCase) {
        #expect(Scorer.score(testCase.expected, against: testCase).passed, "\(testCase.id)")
    }
}
