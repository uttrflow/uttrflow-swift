import Testing
import UttrflowAI
import UttrflowCore

@testable import UttrflowEval

/// What a case says about where its words are going, and how the bake-off hands that to an engine.
@Suite("Destination cases")
struct DestinationCorpusTests {
    /// Apps whose entry line is a title or a line the app parses, so it takes no closing stop.
    static let quickEntryApps = [
        "com.apple.reminders", "com.apple.iCal", "com.culturedcode.ThingsMac", "com.omnigroup.OmniFocus3",
        "com.flexibits.fantastical2.mac", "com.todoist.mac.Todoist",
    ]

    private let slack = AppContext(
        applicationName: "Slack", bundleIdentifier: "com.tinyspeck.slackmacgap", documentName: "#ops",
        precedingText: "because ")

    private var shaped: EvaluationCase {
        EvaluationCase(
            id: "shaped", category: .contextual, spoken: "on my way", expected: "on my way",
            context: slack, destination: .email)
    }

    @Test("a case is plain unless it says where it is dictated, so nothing older changes")
    func plainByDefault() {
        let plain = EvaluationCase(id: "p", category: .everyday, spoken: "hi", expected: "Hi.")
        #expect(plain.destination == .plain)
        #expect(plain.mustBeginWith == nil)
        #expect(plain.mustEndWith == nil)
        #expect(plain.situation == .unknown)
    }

    @Test("the situation is the case's own destination, never the classifier's guess, with its caret")
    func situationIsTheCasesOwn() {
        let situation = shaped.situation
        #expect(situation.destination == .email)
        #expect(situation.app == slack)
        #expect(situation.insertion.sentenceState == .midSentence)
    }

    @Test("calendar and task apps use document capitalization with title stops removed")
    func titleAppsKeepDocumentCapitalizationWithoutFullStops() {
        let document = DestinationFormatter.standard(for: .document)
        for bundle in Self.quickEntryApps {
            let app = AppContext(bundleIdentifier: bundle)
            let situation = SituationResolver.resolve(from: app)
            let formatter = DestinationFormatter.standard(for: situation)
            #expect(DestinationClassifier.classify(app) == .document)
            #expect(formatter.firstWord == document.firstWord)
            #expect(formatter.terminalStop == .never)
            #expect(formatter.layout == document.layout)
            #expect(formatter.grammar == document.grammar)
        }
    }

    @Test("title pipelines remove an added period, keep a question mark, and leave other apps alone")
    func titlePipelinesProduceTheExpectedTerminalOutput() {
        for bundle in Self.quickEntryApps {
            let situation = SituationResolver.resolve(from: AppContext(bundleIdentifier: bundle))
            let formatter = DestinationFormatter.standard(for: situation)
            let pipeline = CleaningPipeline.standard(for: formatter, situation: situation)
            #expect(pipeline.run(Draft(text: "water the plants.")).text == "Water the plants")
            #expect(
                pipeline.run(Draft(text: "should we water the plants?")).text
                    == "Should we water the plants?"
            )
        }

        let situation = SituationResolver.resolve(from: AppContext(bundleIdentifier: "com.example.unknown"))
        let pipeline = CleaningPipeline.standard(
            for: DestinationFormatter.standard(for: situation), situation: situation)
        #expect(pipeline.run(Draft(text: "water the plants.")).text == "Water the plants.")
    }

    @Test("builds the request the bake-off hands an engine")
    func buildsTheRequest() {
        let request = shaped.transformationRequest()
        #expect(request.transcription.text == "on my way")
        #expect(request.transcription.detectedLanguage?.code == .english)
        #expect(request.context == slack)
        #expect(request.situation == shaped.situation)
    }

    @Test("withholding the screen withholds the situation with it")
    func withholdingContext() {
        let request = shaped.transformationRequest(withholdingContext: true)
        #expect(request.context == .unknown)
        #expect(request.situation == .unknown)
        #expect(request.transcription.text == "on my way")
    }

    /// The deterministic floor is what these cases are first measured against, and it has to pass all but the model's own.
    @Test("the rules engine passes every case that names its destination and is not the model's alone")
    func rulesPassDestinationCases() async throws {
        let cases = EvaluationCorpus.cases(in: .contextual).filter {
            $0.destination != .plain && !RulesCorpusTests.modelOnly.contains($0.id)
        }
        #expect(cases.count >= 15)
        for testCase in cases {
            let result = try await RuleBasedTransformer().transform(testCase.transformationRequest())
            let score = Scorer.score(result.text, against: testCase)
            #expect(
                score.passed,
                "\(testCase.id) produced \"\(result.text)\": \(score.brokeShape) \(score.invented)")
        }
    }

    @Test("every destination case says what shape it is checking for")
    func destinationCasesCheckTheirShape() {
        for testCase in EvaluationCorpus.all where testCase.destination != .plain {
            #expect(
                testCase.mustBeginWith != nil || testCase.mustEndWith != nil || testCase.expectedExact != nil,
                "\(testCase.id) measures nothing")
        }
    }
}
