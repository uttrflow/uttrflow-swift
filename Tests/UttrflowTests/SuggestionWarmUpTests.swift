// Tests that a model on its first load shows a spinner where its answer would go, and nothing else does.

import AppKit
import Testing
import UttrflowPredict

@testable import Uttrflow

@MainActor
@Suite("The spinner while the model first loads", .serialized)
struct SuggestionWarmUpTests {
    @Test("Only a line the model would have answered, while it first loads, waits on the spinner")
    func onlyAFirstLoadWaits() {
        let silent = SuggestionUpdate.quiet(because: .nothingOffered)
        #expect(
            SuggestionCoordinator.waitsForWarmUp(
                after: silent, hasGenerator: true, isReady: false, isWarmingUp: true))
        #expect(
            !SuggestionCoordinator.waitsForWarmUp(
                after: silent, hasGenerator: true, isReady: false, isWarmingUp: false))
        #expect(
            !SuggestionCoordinator.waitsForWarmUp(
                after: silent, hasGenerator: true, isReady: true, isWarmingUp: true))
        #expect(
            !SuggestionCoordinator.waitsForWarmUp(
                after: silent, hasGenerator: false, isReady: false, isWarmingUp: true))
        #expect(
            !SuggestionCoordinator.waitsForWarmUp(
                after: .quiet(because: .overBudget), hasGenerator: true, isReady: false, isWarmingUp: true))
        let held = SuggestionUpdate(suggestion: .certain("git status"), armed: [], silence: nil)
        #expect(
            !SuggestionCoordinator.waitsForWarmUp(
                after: held, hasGenerator: true, isReady: false, isWarmingUp: true))
    }

    @Test(
        "The spinner is drawn at the caret, claims no key, and goes when the load ends or a ghost replaces it"
    )
    func theSpinnerComesAndGoes() throws {
        let screen = try #require(NSScreen.screens.first).visibleFrame
        let caret = CGRect(x: screen.minX + 200, y: screen.midY, width: 0, height: 17)
        let panel = SuggestionPanelController.shared
        panel.showWarmingUp(
            caret: caret, direction: .leftToRight, window: nil, field: nil, fieldPointSize: nil)
        #expect(panel.showsWarmUp)
        #expect(!panel.isShowing)
        panel.stopWarmingUp()
        #expect(!panel.showsWarmUp)

        panel.showWarmingUp(
            caret: caret, direction: .leftToRight, window: nil, field: nil, fieldPointSize: nil)
        panel.show(.certain("meeting"), placement: .inlineGhost, caret: caret)
        #expect(!panel.showsWarmUp)
        #expect(panel.isShowing)
        panel.stopWarmingUp()
        #expect(panel.isShowing)
        panel.hide()
        #expect(!panel.isShowing)
    }

    @Test("VoiceOver hears that suggestions are loading on the spinner")
    func theSpinnerIsLabelled() {
        #expect(SuggestionView.warmingUpLabel == "AI suggestions are loading.")
    }
}
