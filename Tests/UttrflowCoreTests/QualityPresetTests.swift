import Foundation
import Testing

@testable import UttrflowCore

@Suite("Quality presets as bundles of the existing choices")
struct QualityPresetTests {
    @Test("standard changes nothing the user or the place chose", arguments: Destination.allCases)
    func standardIsIdentity(destination: Destination) {
        let formatter = DestinationFormatter.standard(for: destination)
        let steps = CleaningSteps.default.setting(.spacing, isOn: false)
        #expect(QualityPreset.standard.applied(to: formatter) == formatter)
        #expect(QualityPreset.standard.applied(to: steps) == steps)
    }

    @Test("a preset never switches a step back on", arguments: QualityPreset.offered)
    func neverEnablesAStep(preset: QualityPreset) {
        for step in CleaningSteps.offered {
            let off = CleaningSteps.default.setting(step.id, isOn: false)
            #expect(!preset.applied(to: off).runs(step.id))
        }
    }

    @Test("a preset cannot switch off a step the formatter owns")
    func cannotReachPolicySteps() {
        let preset = QualityPreset(
            id: .standard, name: "", detail: "", switchedOff: [.firstWord, .terminalStop, .fillers])
        #expect(preset.switchedOff == [.fillers])
    }

    @Test("verbatim keeps every spoken word and leaves the formatter alone")
    func verbatimKeepsWords() {
        let steps = QualityPreset.verbatim.applied(to: .default)
        for step in [PassID.fillers, .repeatedPhrase, .stammers, .selfCorrection] {
            #expect(!steps.runs(step))
        }
        #expect(steps.runs(.spokenPunctuation))
        let plain = DestinationFormatter.standard(for: .plain)
        #expect(QualityPreset.verbatim.applied(to: plain) == plain)
    }

    @Test("code chooses existing policies and keeps the place's other fields")
    func codeChoosesPolicies() {
        let email = DestinationFormatter.standard(for: .email)
        let formatter = QualityPreset.code.applied(to: email)
        #expect(formatter.firstWord == .asSpoken)
        #expect(formatter.numbers == .always)
        #expect(formatter.layout == .preserveNewlines)
        #expect(formatter.terminalStop == .never)
        #expect(formatter.destination == email.destination)
        #expect(formatter.grammar == email.grammar)
        #expect(formatter.consequence == email.consequence)
    }

    @Test("only the identifier is stored, and it round-trips", arguments: QualityPreset.ID.allCases)
    func roundTrips(id: QualityPreset.ID) throws {
        let data = try JSONEncoder().encode(id)
        #expect(try JSONDecoder().decode(QualityPreset.ID.self, from: data) == id)
        #expect(QualityPreset.preset(id).id == id)
    }

    @Test(
        "an identifier this build does not know reads as standard",
        arguments: ["\"dramatic\"", "7", "null"])
    func unknownDecodesToStandard(json: String) throws {
        let id = try JSONDecoder().decode(QualityPreset.ID.self, from: Data(json.utf8))
        #expect(id == .standard)
    }
}
