import Foundation
import Testing
import UttrflowContext
import UttrflowPredict

@testable import Uttrflow

@Suite("AX selection changes while a suggestion is armed")
struct SuggestionSelectionGuardTests {
    @Test("a rotor-only caret move withdraws the offer without a key event")
    func rotorMoveWithdrawsOffer() {
        var guardrail = ArmedSelectionGuard(expectedRange: NSRange(location: 12, length: 0))
        let focusedField = FocusedFieldSelection(
            processIdentifier: 41, elementHash: 900, range: NSRange(location: 12, length: 0))
        var armedOffer: String? = "completion"

        let initialSelectionChanged = guardrail.observe(focusedField)
        #expect(!initialSelectionChanged)

        let rotorSelection = FocusedFieldSelection(
            processIdentifier: 41, elementHash: 900, range: NSRange(location: 28, length: 0))
        if guardrail.observe(rotorSelection) { armedOffer = nil }

        #expect(armedOffer == nil)
    }

    @Test("a focused field change withdraws even when the range is unchanged")
    func fieldChangeWithdrawsOffer() {
        var guardrail = ArmedSelectionGuard(expectedRange: NSRange(location: 12, length: 0))
        let initialSelectionChanged = guardrail.observe(
            FocusedFieldSelection(
                processIdentifier: 41, elementHash: 900, range: NSRange(location: 12, length: 0)))
        let focusedFieldChanged = guardrail.observe(
            FocusedFieldSelection(
                processIdentifier: 41, elementHash: 901, range: NSRange(location: 12, length: 0)))
        #expect(!initialSelectionChanged)
        #expect(focusedFieldChanged)
    }

    @Test("a field change before the first poll withdraws even when the range is unchanged")
    func fieldChangeBeforeFirstPollWithdrawsOffer() {
        var guardrail = ArmedSelectionGuard(
            expectedRange: NSRange(location: 0, length: 0),
            identity: FocusedFieldIdentity(processIdentifier: 41, elementHash: 900))
        let newlyFocusedField = FocusedFieldSelection(
            processIdentifier: 41, elementHash: 901, range: NSRange(location: 0, length: 0))

        let shouldWithdraw = guardrail.observe(newlyFocusedField)
        #expect(shouldWithdraw)
    }

    @Test("text typed through the ghost advances its expected caret")
    func typedTextAdvancesExpectedCaret() {
        var guardrail = ArmedSelectionGuard(expectedRange: NSRange(location: 12, length: 0))
        guardrail.typedThrough("é🐕")

        let selectionChanged = guardrail.observe(
            FocusedFieldSelection(
                processIdentifier: 41, elementHash: 900, range: NSRange(location: 15, length: 0)))
        #expect(!selectionChanged)
    }

    @Test("typing past Int.max withdraws the armed offer instead of overflowing")
    func typedTextOverflowInvalidatesExpectedCaret() {
        for location in [NSNotFound, Int.max, Int.max - 1, Int.min, -1, 0] {
            for text in ["x", "ab", "🐕"] {
                var guardrail = ArmedSelectionGuard(
                    expectedRange: NSRange(location: location, length: 0))
                let (expected, overflow) = location.addingReportingOverflow(text.utf16.count)
                guardrail.typedThrough(text)
                #expect(guardrail.expectedRange == (overflow ? nil : NSRange(location: expected, length: 0)))
                if overflow {
                    let observed = guardrail.observe(nil)
                    #expect(observed)
                }
            }
        }
    }

    @Test("an unavailable AX selection fails closed")
    func unavailableSelectionWithdrawsOffer() {
        var guardrail = ArmedSelectionGuard(expectedRange: NSRange(location: 12, length: 0))
        let shouldWithdraw = guardrail.observe(nil)
        #expect(shouldWithdraw)
    }
}

private actor FakeFocusedSelectionReader {
    private var result: FocusedFieldSelectionRead
    private var readCount = 0

    init(_ result: FocusedFieldSelectionRead) {
        self.result = result
    }

    func read() -> FocusedFieldSelectionRead {
        readCount += 1
        return result
    }

    func move(to result: FocusedFieldSelectionRead) {
        self.result = result
    }

    func reads() -> Int { readCount }
}

@MainActor
@Suite("Coordinator AX selection polling")
struct SuggestionCoordinatorSelectionPollingTests {
    @Test("a rotor-only selection change withdraws the armed offer without an NSEvent")
    func rotorChangeWithdrawsArmedOffer() async throws {
        let focused = FocusedFieldSelection(
            processIdentifier: 41, elementHash: 900, range: NSRange(location: 12, length: 0))
        let reader = FakeFocusedSelectionReader(.selection(focused))
        let container = FileManager.default.temporaryDirectory
            .appending(path: "uttrflow-2648-\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: container, withIntermediateDirectories: true)
        let coordinator = try SuggestionCoordinator(
            container: container, preferences: SuggestionPreferences(isEnabled: true),
            focusedSelectionReader: { await reader.read() })
        defer {
            coordinator.stop()
            try? FileManager.default.removeItem(at: container)
        }
        coordinator.armSelectionMonitor(for: .certain("completion"), at: focused.range)

        await coordinator.pollFocusedSelection()
        #expect(coordinator.armedOffer == "completion")

        await reader.move(
            to: .timedOut)
        await coordinator.pollFocusedSelection()
        #expect(coordinator.armedOffer == "completion")

        await reader.move(
            to: .selection(
                FocusedFieldSelection(
                    processIdentifier: 41, elementHash: 900, range: NSRange(location: 28, length: 0)))
        )
        await coordinator.pollFocusedSelection()

        #expect(coordinator.armedOffer == nil)
        #expect(await reader.reads() == 3)
    }

    @Test("an unavailable field still withdraws the armed offer")
    func unavailableSelectionWithdrawsArmedOffer() async throws {
        let focused = FocusedFieldSelection(
            processIdentifier: 41, elementHash: 900, range: NSRange(location: 12, length: 0))
        let reader = FakeFocusedSelectionReader(.unavailable)
        let container = FileManager.default.temporaryDirectory
            .appending(
                path: "uttrflow-unavailable-selection-\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: container, withIntermediateDirectories: true)
        let coordinator = try SuggestionCoordinator(
            container: container, preferences: SuggestionPreferences(isEnabled: true),
            focusedSelectionReader: { await reader.read() })
        defer {
            coordinator.stop()
            try? FileManager.default.removeItem(at: container)
        }
        coordinator.armSelectionMonitor(for: .certain("completion"), at: focused.range)

        await coordinator.pollFocusedSelection()

        #expect(coordinator.armedOffer == nil)
    }
}
