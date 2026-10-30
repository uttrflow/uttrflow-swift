// Tests that a model on its first load shows a spinner where its answer would go, and nothing else does.

import AppKit
import Testing
import UttrflowContext
import UttrflowPredict
import UttrflowUX

@testable import Uttrflow

@MainActor
@Suite("The spinner while the model first loads", .serialized)
struct SuggestionWarmUpTests {
    private static let silent = SuggestionUpdate.quiet(because: .nothingOffered)

    private static func snapshot(caret: CGRect?) throws -> FocusedFieldSnapshot {
        let screen = try #require(NSScreen.screens.first).visibleFrame
        return FocusedFieldSnapshot(
            bundleIdentifier: "com.example.editor", applicationName: "Editor", role: "AXTextField",
            value: "meet", selection: NSRange(location: 4, length: 0), caret: caret,
            window: screen, field: CGRect(x: screen.minX + 100, y: screen.midY - 10, width: 500, height: 24))
    }

    private static func caret() throws -> CGRect {
        let screen = try #require(NSScreen.screens.first).visibleFrame
        return CGRect(x: screen.minX + 200, y: screen.midY - 5, width: 0, height: 17)
    }

    private static func warmUp() -> (SuggestionWarmUp, () -> Int) {
        let warmUp = SuggestionWarmUp()
        var fronted = 0
        warmUp.frontWindow = { _ in fronted += 1 }
        return (warmUp, { fronted })
    }

    @Test("Only a line the model would have answered, while it first loads, waits on the spinner")
    func onlyAFirstLoadWaits() {
        #expect(
            SuggestionWarmUp.waits(after: Self.silent, hasGenerator: true, isReady: false, isWarmingUp: true))
        #expect(
            !SuggestionWarmUp.waits(
                after: Self.silent, hasGenerator: true, isReady: false, isWarmingUp: false))
        #expect(
            !SuggestionWarmUp.waits(after: Self.silent, hasGenerator: true, isReady: true, isWarmingUp: true))
        #expect(
            !SuggestionWarmUp.waits(
                after: Self.silent, hasGenerator: false, isReady: false, isWarmingUp: true))
        #expect(
            !SuggestionWarmUp.waits(
                after: .quiet(because: .overBudget), hasGenerator: true, isReady: false, isWarmingUp: true))
        let held = SuggestionUpdate(suggestion: .certain("git status"), armed: [], silence: nil)
        #expect(!SuggestionWarmUp.waits(after: held, hasGenerator: true, isReady: false, isWarmingUp: true))
    }

    @Test("Only the load before the first ready since the feature was turned on counts as warming up")
    func onlyTheFirstLoadWarmsUp() {
        let (warmUp, _) = Self.warmUp()
        #expect(!warmUp.isWarmingUp)
        warmUp.modelIs(.loading)
        #expect(warmUp.isWarmingUp)
        warmUp.modelIs(.ready)
        #expect(!warmUp.isWarmingUp)
        warmUp.modelIs(.releasedForMemory)
        warmUp.modelIs(.loading)
        #expect(!warmUp.isWarmingUp)
        warmUp.modelIs(.notAsked)
        warmUp.modelIs(.loading)
        #expect(warmUp.isWarmingUp)
    }

    @Test("The spinner is drawn just past the caret, on the side the line runs, and goes when the load ends")
    func theSpinnerComesAndGoes() throws {
        let (warmUp, fronted) = Self.warmUp()
        let caret = try Self.caret()
        warmUp.modelIs(.loading)
        warmUp.settled(
            Self.silent, hasGenerator: true, isReady: false, blocked: false,
            in: try Self.snapshot(caret: caret))
        #expect(warmUp.isShowing)
        #expect(warmUp.panel.frame.minX == caret.maxX)
        #expect(fronted() == 1)
        warmUp.show(at: caret, direction: .rightToLeft)
        #expect(warmUp.panel.frame.maxX == caret.minX)
        warmUp.modelIs(.ready)
        #expect(!warmUp.isShowing)
        warmUp.hide()
        #expect(!warmUp.isShowing)
    }

    @Test("A drawn suggestion, secure input or a field with no caret takes the spinner away")
    func otherTurnsHideTheSpinner() throws {
        let (warmUp, _) = Self.warmUp()
        let caret = try Self.caret()
        warmUp.modelIs(.loading)
        let held = SuggestionUpdate(suggestion: .certain("meeting"), armed: [], silence: nil)
        for (update, blocked, at) in [
            (held, false, Optional(caret)), (Self.silent, true, Optional(caret)), (Self.silent, false, nil),
        ] {
            warmUp.show(at: caret, direction: .leftToRight)
            warmUp.settled(
                update, hasGenerator: true, isReady: false, blocked: blocked, in: try Self.snapshot(caret: at)
            )
            #expect(!warmUp.isShowing)
        }
    }

    @Test("A coordinator settles a turn the model was not asked about before handing it to the spinner")
    func theCoordinatorSettlesFirst() async throws {
        let container = FileManager.default.temporaryDirectory.appending(path: "warm-up-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: container, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: container) }
        let panel = SuggestionPanelController()
        let coordinator = try await SuggestionCoordinator(
            container: container, preferences: SuggestionPreferences(isEnabled: true),
            focusedFieldReader: { nil },
            frontmostBundleIdentifier: { "com.example.editor" }, panel: panel)
        defer { panel.hide() }
        var settled: [SuggestionUpdate] = []
        coordinator.settledWithoutModel(
            Self.silent, true, false, in: try Self.snapshot(caret: try Self.caret()),
            settle: { update, _ in settled.append(update) })
        #expect(settled == [Self.silent])
        #expect(!SuggestionWarmUp.shared.isShowing)
    }

    @Test("VoiceOver hears that suggestions are loading on the spinner")
    func theSpinnerIsLabelled() {
        #expect(SuggestionWarmUp.label == "AI suggestions are loading.")
        _ = SuggestionWarmUpView().body
    }
}
