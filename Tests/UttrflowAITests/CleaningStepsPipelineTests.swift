import Testing
import UttrflowCore

@testable import UttrflowAI

@Suite("A clean-up step the user switched off")
struct CleaningStepsPipelineTests {
    private let formatter = DestinationFormatter.standard(for: .plain)

    @Test("the default set is today's order, first word and final stop last")
    func defaultOrder() {
        let built = CleaningPipeline.standard(for: formatter, situation: .unknown).ids
        #expect(built == CleaningPipeline.standard.ids)
        #expect(
            built == [
                .fillers, .stammers, .repeatedPhrase, .selfCorrection, .spokenPunctuation,
                .layoutWords, .numberForms, .spacing, .firstWord, .terminalStop,
            ])
    }

    @Test("a pipeline built with fillers off keeps um")
    func fillersOff() {
        let steps = CleaningSteps.default.setting(.fillers, isOn: false)
        let pipeline = CleaningPipeline.standard(for: formatter, situation: .unknown, steps: steps)
        #expect(!pipeline.ids.contains(.fillers))
        #expect(pipeline.run(Draft(text: "um we ship on friday")).text == "Um we ship on friday.")
    }

    @Test("with fillers on the same words lose the um")
    func fillersOn() {
        let pipeline = CleaningPipeline.standard(for: formatter, situation: .unknown)
        #expect(pipeline.run(Draft(text: "um we ship on friday")).text == "We ship on friday.")
    }

    /// They carry the formatter's decisions about the place, not a cleaning the user asked for.
    @Test("the first word and the final stop stay whatever the user switched off")
    func policyPassesStay() {
        let steps = CleaningSteps(switchedOff: Set(CleaningSteps.offered.map(\.id)))
        let pipeline = CleaningPipeline.standard(for: formatter, situation: .unknown, steps: steps)
        #expect(pipeline.ids == [.firstWord, .terminalStop])
    }

    @Test("the passes handed to a model drop the same step and keep the finishing two out")
    func beforeModel() {
        let steps = CleaningSteps.default.setting(.numberForms, isOn: false)
        let pipeline = CleaningPipeline.beforeModel(steps: steps)
        #expect(!pipeline.ids.contains(.numberForms))
        #expect(!pipeline.ids.contains(.firstWord))
        #expect(!pipeline.ids.contains(.terminalStop))
        #expect(CleaningPipeline.beforeModel(steps: .default).ids == CleaningPipeline.beforeModel.ids)
    }

    @Test("the deterministic transformer reports what it did and what was off")
    func rulesTransformerRecords() async throws {
        let steps = CleaningSteps.default.setting(.spacing, isOn: false)
        let result = try await RuleBasedTransformer(steps: steps).transform(
            TransformationRequest(transcription: Transcription(text: "um we ship")))
        let record = try #require(result.cleaning)
        #expect(record.changes.first { $0.step == .fillers }?.removed == ["um"])
        #expect(record.switchedOff == [.spacing])
    }

    @Test("a transformer given a pipeline of its own still reports against that pipeline")
    func givenPipeline() async throws {
        let result = try await RuleBasedTransformer(
            pipeline: CleaningPipeline(passes: [FillersPass()])
        ).transform(TransformationRequest(transcription: Transcription(text: "um we ship")))
        let record = try #require(result.cleaning)
        #expect(record.changes.map(\.step) == [.fillers])
        #expect(record.switchedOff.contains(.spacing))
    }

    @Test("the transformers a build contains are all built with the user's steps")
    func transformersHonourTheSteps() async throws {
        let steps = CleaningSteps.default.setting(.fillers, isOn: false)
        let engines = TextTransformers.all(steps: steps)
        let floor = try #require(engines.first { $0.kind == .rules })
        let result = try await floor.transform(
            TransformationRequest(transcription: Transcription(text: "um we ship")))
        #expect(result.text == "Um we ship.")
    }
}
