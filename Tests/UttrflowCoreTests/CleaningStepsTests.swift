import Foundation
import Testing

@testable import UttrflowCore

@Suite("Clean-up steps a user can switch off")
struct CleaningStepsTests {
    @Test("everything runs before the user touches anything")
    func everythingOnByDefault() {
        #expect(CleaningSteps.default.switchedOff.isEmpty)
        #expect(CleaningSteps.offered.allSatisfy { CleaningSteps.default.runs($0.id) })
    }

    @Test("switching one off leaves every other step running")
    func switchingOneOff() {
        let steps = CleaningSteps.default.setting(.fillers, isOn: false)
        #expect(!steps.runs(.fillers))
        #expect(steps.runs(.stammers))
        #expect(steps.setting(.fillers, isOn: true).runs(.fillers))
    }

    /// The first word's case and the final stop belong to the place the words are going.
    @Test(
        "a step the formatter owns cannot be switched off, however it arrives",
        arguments: [PassID.firstWord, .terminalStop, .caretEcho])
    func policyStepsStayOn(step: PassID) {
        #expect(!CleaningSteps.isOffered(step))
        #expect(CleaningSteps.default.setting(step, isOn: false).runs(step))
        #expect(CleaningSteps(switchedOff: [step]).runs(step))
    }

    @Test("the steps offered are the ones the pipeline runs, in the order it runs them")
    func offeredOrder() {
        #expect(
            CleaningSteps.offered.map(\.id) == [
                .fillers, .stammers, .repeatedPhrase, .selfCorrection, .spokenPunctuation,
                .layoutWords, .numberForms, .contractions, .spacing,
            ])
    }

    @Test("every step has a plain name and a line saying what it does")
    func everyStepIsExplained() {
        for step in CleaningSteps.offered {
            #expect(!step.name.isEmpty)
            #expect(step.detail.count > 20)
            #expect(CleaningSteps.name(of: step.id) == step.name)
        }
    }

    @Test("a step nobody offers is named by its identifier rather than by nothing")
    func unknownStepName() {
        #expect(CleaningSteps.step(.firstWord) == nil)
        #expect(CleaningSteps.name(of: .firstWord) == "firstWord")
    }

    @Test("what is stored survives a round trip, and drops a step this build holds to")
    func roundTrip() throws {
        let steps = CleaningSteps.default.setting(.spacing, isOn: false)
        let data = try JSONEncoder().encode(steps)
        #expect(try JSONDecoder().decode(CleaningSteps.self, from: data) == steps)

        let foreign = Data(#"{"switchedOff":["firstWord","fillers"]}"#.utf8)
        let decoded = try JSONDecoder().decode(CleaningSteps.self, from: foreign)
        #expect(decoded.switchedOff == [.fillers])
    }

    @Test("a blob that says nothing this build understands is everything on")
    func unreadableBlob() throws {
        #expect(try JSONDecoder().decode(CleaningSteps.self, from: Data("{}".utf8)) == .default)
        #expect(
            try JSONDecoder().decode(
                CleaningSteps.self, from: Data(#"{"switchedOff":"nonsense"}"#.utf8)) == .default)
    }

    @Test("a value that is not a keyed container decodes to the default rather than throwing")
    func notAContainer() throws {
        #expect(try JSONDecoder().decode(CleaningSteps.self, from: Data("[]".utf8)) == .default)
    }
}
