import Testing
import UttrflowCore

@testable import UttrflowAI
@testable import UttrflowPipeline
import UttrflowTestSupport

@Suite("End-to-end word survival")
struct EndToEndWordSurvivalTests {
    private static let seed: UInt64 = 0x2474_2026
    private static let inputCount = 400
    /// Dictations running at once; each waits mostly on its own early-loop polls, not on the processor.
    private static let inFlight = 16
    private static let destinations: [Destination] = [
        .plain, .document, .email, .messaging, .sqlEditor, .codeEditor, .terminal, .spreadsheet,
    ]

    @Test("reports every word's first loss, by stage, through the real pipeline to the write")
    func wordsSurviveEveryStage() async throws {
        let inputs = Self.dictations(count: Self.inputCount, seed: Self.seed)
        #expect(inputs.count == Self.inputCount)
        #expect(inputs.allSatisfy { noCleaningTriggers($0.text) && $0.parts.count <= 4 && !$0.parts.isEmpty })
        #expect(Set(inputs.map(\.text)).count == Self.inputCount)
        #expect(inputs.allSatisfy { $0.parts.joined(separator: " ") == $0.text })
        for destination in Self.destinations {
            #expect(
                inputs.count(where: { $0.destination == destination }) == Self.inputCount
                    / Self.destinations.count)
        }
        // Each dictation has its own pipeline, so they run side by side; the report keeps the inputs' order.
        let losses = await withTaskGroup(of: (Int, [LostWord]).self) { group in
            var found: [Int: [LostWord]] = [:]
            for (position, input) in inputs.enumerated() {
                if position >= Self.inFlight, let (done, lost) = await group.next() { found[done] = lost }
                group.addTask { (position, await run(input)) }
            }
            for await (done, lost) in group { found[done] = lost }
            return found
        }
        let failures = inputs.indices.flatMap { position in
            (losses[position] ?? []).map {
                "input \(inputs[position].index) [\(inputs[position].destination)]: '\($0.word)' first lost at \($0.stage)"
            }
        }
        #expect(failures.isEmpty, Comment(rawValue: failures.prefix(20).joined(separator: "\n")))
    }

    @Test("the check identifies a known deletion at the stage that introduces it")
    func knownDeletionIsReportedAtFirstStage() {
        let found = Self.firstLostWords(
            reference: "keep the secret",
            stages: [
                ("per-piece clean", "keep the secret"),
                ("join", "keep secret"),
                ("message finish", "keep secret."),
            ], reportWords: ["the"])
        #expect(found == [LostWord(word: "the", stage: "join")])
        let substitution = Self.firstLostWords(
            reference: "the callers waited",
            stages: [("per-piece clean", "the caller waited"), ("join", "the caller waited")],
            reportWords: ["callers"])
        #expect(substitution.isEmpty)
        let changedWord = Self.firstLostWords(
            reference: "keep the secret",
            stages: [("per-piece clean", "keep a secret")], reportWords: ["the"])
        #expect(changedWord == [LostWord(word: "the", stage: "per-piece clean")])
    }

    @Test("keeps every digit when a PIN is cut at any word boundary")
    func repeatedPINDigitsSurviveEveryPieceBoundary() async throws {
        let words = "my pin is two two four four".split(separator: " ").map(String.init)
        // The whole join, including the re-tidy of a number cut in two, is the pipeline's.
        let pipeline = DictationPipeline(
            capture: FakeAudioCaptureEngine(), speech: FakeSpeechEngine(), cleaner: ScenarioCleaners.rules,
            context: FakeContextEngine(), inserter: FakeTextInserter())

        for boundary in 1..<words.count {
            let parts = [
                words[..<boundary].joined(separator: " "),
                words[boundary...].joined(separator: " "),
            ]
            let heard = parts.map {
                Transcription(text: $0, detectedLanguage: DetectedLanguage(code: .english, confidence: 1))
            }
            let finished = await pipeline.clean(heard, seeing: AppContext()).text

            #expect(finished == "My pin is 2244.", "boundary after word \(boundary): \(finished ?? "nil")")
        }
    }

    @Test("a stage that drops a word inside the real pipeline is named as the stage that lost it")
    func lossyStageInsideThePipelineIsNamed() async {
        let dictation = await ScenarioDriver.run(
            Scenario(
                pieces: [ScriptedPiece("keep the secret"), ScriptedPiece("for the team")],
                context: Self.app(for: .document), cleaner: DroppingFinish(word: "secret")))
        let stages = await dictation.stages()

        let found = Self.firstLostWords(
            reference: "keep the secret for the team", stages: stages,
            reportWords: ["keep", "secret", "team"])

        #expect(found == [LostWord(word: "secret", stage: "message finish")])
    }

    @Test("each destination's app is classified by its bundle identifier, not named by the test")
    func everyDestinationIsReachedByItsBundleIdentifier() {
        for destination in Self.destinations {
            #expect(DestinationClassifier.classify(Self.app(for: destination)) == destination)
        }
    }

    /// One dictation of `input`, spoken in its parts, into the app its destination names.
    private func run(_ input: Input) async -> [LostWord] {
        let dictation = await ScenarioDriver.run(
            Scenario(pieces: input.parts.map { ScriptedPiece($0) }, context: Self.app(for: input.destination))
        )
        guard dictation.heard.map(\.text) == input.parts else {
            return [LostWord(word: input.text, stage: "recognition: \(dictation.heard.map(\.text))")]
        }
        guard dictation.writes.count == 1 else {
            return [
                LostWord(
                    word: input.text, stage: "write: \(dictation.writes.count) writes, \(dictation.state)")
            ]
        }
        let stages = await dictation.stages()
        let reportWords = Set(input.text.split(whereSeparator: \.isWhitespace).map(String.init))
        return Self.firstLostWords(reference: input.text, stages: stages, reportWords: reportWords)
    }

    /// An app the standard table files under `destination`, named only by its bundle identifier.
    private static func app(for destination: Destination) -> AppContext {
        let bundle =
            DestinationRules.standard.first {
                $0.destination == destination && !$0.bundlePrefixes.isEmpty
            }?.bundlePrefixes.first ?? "com.example.unlisted"
        return AppContext.fixture(applicationName: nil, bundleIdentifier: bundle, documentName: nil)
    }

    private static func firstLostWords(
        reference: String, stages: [(stage: String, text: String)], reportWords: Set<String>
    ) -> [LostWord] {
        let referenceWords = spokenWords(reference)
        var losses: [LostWord] = []
        var priorWords = referenceWords
        for (stage, text) in stages {
            let current = spokenWords(text)
            let alignment = WordErrorRate.measure(reference: priorWords, hypothesis: current)
            let changed = alignment.alignment.compactMap { operation -> (String, String?)? in
                let word: String
                let replacement: String?
                switch operation {
                case .deletion(let deleted):
                    word = deleted
                    replacement = nil
                case .substitution(let expected, let actual):
                    word = expected
                    replacement = actual
                case .match, .insertion:
                    return nil
                }
                if let replacement, WordForms.sameForm(word, replacement) { return nil }
                guard reportWords.contains(where: { WordForms.sameForm(word, $0) }) else {
                    return nil
                }
                guard !losses.contains(where: { $0.word == word }) else { return nil }
                guard
                    !current.contains(where: {
                        WordForms.sameForm(word, $0)
                    })
                else { return nil }
                if let replacement, isNumberRewrite(word, replacement) { return nil }
                return (word, replacement)
            }
            for (word, _) in changed {
                if !losses.contains(where: { $0.word == word }) {
                    losses.append(LostWord(word: word, stage: stage))
                }
            }
            priorWords = current
        }
        return losses
    }

    /// The words of a stage's text without the stops and capitals that stage may write around them.
    private static func spokenWords(_ text: String) -> [String] {
        text.split(whereSeparator: \.isWhitespace).map { WordShape(String($0)).core.lowercased() }
            .filter { !$0.isEmpty }
    }

    private static func dictations(count: Int, seed: UInt64) -> [Input] {
        let subjects = [
            "the project team", "our support group", "the research office", "the product team",
            "the finance group",
        ]
        let verbs = [
            "reviewed", "prepared", "updated", "checked", "shared", "organized", "compared", "documented",
        ]
        let objects = [
            "the customer report", "the revised schedule", "the account summary", "the installation guide",
            "the deployment plan",
        ]
        let endings = [
            "before the meeting", "during the afternoon", "for the next release", "with the design group",
        ]
        let contexts = [
            "on the company network", "in the shared project folder", "for the regional office",
            "across the product group",
        ]
        var random = SeededGenerator(seed: seed)
        return (0..<count).map { index in
            let subject = subjects[index % subjects.count]
            let verb = verbs[(index / subjects.count) % verbs.count]
            let object = objects[(index / (subjects.count * verbs.count)) % objects.count]
            let ending = endings[(index / (subjects.count * verbs.count * objects.count)) % endings.count]
            let context = contexts[
                (index / (subjects.count * verbs.count * objects.count * endings.count)) % contexts.count]
            let text = "\(subject) \(verb) \(object) \(ending) \(context)"
            let words = text.split(whereSeparator: \.isWhitespace).map(String.init)
            let pieceCount = min(words.count, random.next(upperBound: 4) + 1)
            let cuts = Set(random.permutation(Array(1..<words.count)).prefix(pieceCount - 1))
            let boundaries = [0] + cuts.sorted() + [words.count]
            let parts = zip(boundaries, boundaries.dropFirst()).map { words[$0..<$1].joined(separator: " ") }
            return Input(
                index: index + 1, text: text, parts: parts,
                destination: destinations[index % destinations.count])
        }
    }
}

/// The shipping rules, except that finishing the joined message drops one word, as a broken stage would.
private struct DroppingFinish: TranscriptCleaning {
    let word: String

    func clean(_ request: TransformationRequest) async throws(TransformationError) -> TransformationResult {
        try await ScenarioCleaners.rules.clean(request)
    }

    func finishMessage(_ text: String, for request: TransformationRequest) async -> String {
        let finished = await ScenarioCleaners.rules.finishMessage(text, for: request)
        return finished.split(separator: " ").filter { WordShape(String($0)).core.lowercased() != word }
            .joined(separator: " ")
    }
}

private struct Input: Sendable {
    let index: Int
    let text: String
    let parts: [String]
    let destination: Destination
}

private struct LostWord: Equatable, Sendable {
    let word: String
    let stage: String
}

private struct SeededGenerator {
    private var state: UInt64

    init(seed: UInt64) { state = seed }

    mutating func next(upperBound: Int) -> Int {
        state = state &* 6_364_136_223_846_793_005 &+ 1_442_695_040_888_963_407
        return Int(state % UInt64(upperBound))
    }

    mutating func permutation<T>(_ values: [T]) -> [T] {
        var shuffled = values
        for index in shuffled.indices.dropLast() {
            let swapIndex = index + next(upperBound: shuffled.count - index)
            shuffled.swapAt(index, swapIndex)
        }
        return shuffled
    }
}

/// Whether a generated dictation holds nothing the clean-up exists to change: no filler, number word or repeat.
private func noCleaningTriggers(_ text: String) -> Bool {
    let words = text.lowercased().split(whereSeparator: \.isWhitespace).map(String.init)
    return words.allSatisfy { !FillersPass.fillerWords.contains($0) && NumberWords.value(of: $0) == nil }
        && zip(words, words.dropFirst()).allSatisfy { $0 != $1 }
}

private func isNumberRewrite(_ spoken: String, _ written: String) -> Bool {
    guard let value = NumberWords.value(of: spoken.lowercased()) else { return false }
    return NumberWords.digits(written.lowercased()).flatMap(Int.init) == value
}
