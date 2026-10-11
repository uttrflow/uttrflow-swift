// The Settings clean-up rows show what the real rules do to each step's example.

import Testing
import UttrflowAI
import UttrflowCore
import UttrflowSettings
import UttrflowUX

@testable import Uttrflow

@Suite("The clean-up preview in Settings")
struct SettingsCleaningPreviewTests {
    private func explanations(_ steps: CleaningSteps) throws -> [String: String] {
        var settings = Settings.default
        settings.cleaning = steps
        let pane = SettingsPresenter.pane(
            for: .dictation, settings: settings, capabilities: SettingsCapabilities.thisMac())
        let group = try #require(pane.groups.first { $0.id == "cleaningSteps" })
        return Dictionary(uniqueKeysWithValues: group.rows.map { ($0.id, $0.explanation ?? "") })
    }

    @Test("every offered step's row carries the pipeline's output for its example, on and off")
    func rowsCarryThePipelineOutput() throws {
        let rows = try explanations(.default)
        for step in CleaningSteps.offered {
            let preview = CleaningStepPreview.of(step)
            let text = try #require(rows["step-\(step.id.rawValue)"])
            #expect(text.contains("\u{201C}\(preview.without)\u{201D}"), "\(step.name): off")
            #expect(text.contains("\u{201C}\(preview.with)\u{201D}"), "\(step.name): on")
        }
    }

    @Test("a step's example reads the same whichever way its own tick is, since it shows both")
    func ownTickDoesNotChangeIt() throws {
        let on = try explanations(CleaningSteps.default.setting(.fillers, isOn: true))
        let off = try explanations(CleaningSteps.default.setting(.fillers, isOn: false))
        #expect(on["step-fillers"] == off["step-fillers"])
    }
}
