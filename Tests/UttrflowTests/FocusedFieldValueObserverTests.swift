import AppKit
import Foundation
import Testing
import UttrflowContext
import UttrflowPredict

@testable import Uttrflow

@MainActor
private final class FakeFocusedFieldValueObserver: FocusedFieldValueObserving {
    private var onValueChanged: (@MainActor () -> Void)?
    private var onNativeMenuVisibilityChanged: (@MainActor (Bool) -> Void)?

    func start(
        onValueChanged: @escaping @MainActor () -> Void,
        onNativeMenuVisibilityChanged: @escaping @MainActor (Bool) -> Void
    ) {
        self.onValueChanged = onValueChanged
        self.onNativeMenuVisibilityChanged = onNativeMenuVisibilityChanged
    }

    func refresh() {}
    func stop() {
        onValueChanged = nil
        onNativeMenuVisibilityChanged = nil
    }
    func simulateAXValueChange() { onValueChanged?() }
    func simulateNativeMenuOpened() { onNativeMenuVisibilityChanged?(true) }
}

@MainActor
@Suite("AX value changes withdraw stale suggestion offers", .serialized)
struct FocusedFieldValueObserverTests {
    @Test("a late field value change schedules a turn when no offer is armed")
    func aLateValueChangeWakesWithoutAGhost() {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let key = now.addingTimeInterval(-0.05)

        #expect(
            SuggestionCoordinator.accessibilityValueChangeAction(
                hasArmedOffer: false, lastKeystroke: key, at: now) == .wake)
        #expect(
            SuggestionCoordinator.accessibilityValueChangeAction(
                hasArmedOffer: true, lastKeystroke: key, at: now) == .ignore)
        #expect(
            SuggestionCoordinator.accessibilityValueChangeAction(
                hasArmedOffer: true, lastKeystroke: key, at: now.addingTimeInterval(0.2))
                == .withdrawAndWake)
    }

    @Test("an unsupported close notification removes its matching open subscription")
    func menuNotificationRegistrationRequiresAPair() {
        var operations: [String] = []
        let registered = registerPairedNativeMenuNotifications(
            registerOpened: {
                operations.append("open")
                return true
            },
            registerClosed: {
                operations.append("close")
                return false
            },
            removeOpened: { operations.append("remove open") },
            removeClosed: { operations.append("remove close") })

        #expect(!registered)
        #expect(operations == ["open", "close", "remove open"])
    }

    @Test("application menu notifications close across focus and AX source changes")
    func menuVisibilitySurvivesFocusAndSourceChanges() {
        var state = NativeMenuVisibilityState<Int>()
        state.focusedElementChanged(to: 1)
        state.menuOpened()
        state.focusedElementChanged(to: 2)

        #expect(state.isOpen)
        #expect(state.focusedElement == 2)

        state.menuClosed()

        #expect(!state.isOpen)
    }

    @Test("overlapping application menu notifications stay open until each closes")
    func overlappingMenusStayOpenUntilBothClose() {
        var state = NativeMenuVisibilityState<Int>()
        state.menuOpened()
        state.menuOpened()

        state.menuClosed()
        #expect(state.isOpen)

        state.menuClosed()
        #expect(!state.isOpen)
    }

    @Test("an unmatched close cannot underflow and teardown clears menu state")
    func teardownClearsNativeMenuState() {
        var state = NativeMenuVisibilityState<Int>()
        state.focusedElementChanged(to: 1)
        state.menuOpened()
        state.focusedElementChanged(to: 2)

        state.menuClosed()
        state.menuClosed()
        #expect(!state.isOpen)

        state.menuOpened()
        let wasOpen = state.reset()
        #expect(wasOpen)
        #expect(!state.isOpen)
        #expect(state.focusedElement == nil)
    }

    @Test("an AX SetValue change disarms and hides the current offer")
    func axValueChangeWithdrawsTheOffer() throws {
        let container = FileManager.default.temporaryDirectory.appending(
            path: "ax-value-change-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: container, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: container) }

        let observer = FakeFocusedFieldValueObserver()
        let panel = SuggestionPanelController()
        let coordinator = try SuggestionCoordinator(
            container: container, preferences: SuggestionPreferences(isEnabled: true),
            focusedFieldValueObserver: observer, focusedFieldReader: { nil },
            frontmostBundleIdentifier: { "com.example.editor" }, panel: panel)
        defer {
            coordinator.stop()
            panel.hide()
        }

        let screen = try #require(NSScreen.screens.first).visibleFrame
        // Inside its field, since a caret outside it cannot anchor a ghost.
        let caret = CGRect(x: screen.minX + 200, y: screen.midY - 5, width: 0, height: 17)
        let field = CGRect(x: screen.minX + 100, y: screen.midY - 10, width: 500, height: 24)
        let snapshot = FocusedFieldSnapshot(
            bundleIdentifier: "com.example.editor", applicationName: "Editor", role: "AXTextField",
            value: "meet", selection: NSRange(location: 4, length: 0), caret: caret,
            window: screen, field: field)

        coordinator.draw(
            SuggestionUpdate(suggestion: .certain("meet later"), armed: .tab, silence: nil),
            in: snapshot)
        #expect(coordinator.armedOffer == "meet later")
        #expect(panel.isShowing)

        coordinator.watchFocusedFieldValues()
        observer.simulateAXValueChange()

        #expect(coordinator.armedOffer == nil)
        #expect(!panel.isShowing)
    }

    @Test("an AX menu opening withdraws the offer before its Tab gesture")
    func axMenuOpeningWithdrawsTheOffer() throws {
        let container = FileManager.default.temporaryDirectory.appending(
            path: "ax-menu-open-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: container, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: container) }

        let observer = FakeFocusedFieldValueObserver()
        let panel = SuggestionPanelController()
        let coordinator = try SuggestionCoordinator(
            container: container, preferences: SuggestionPreferences(isEnabled: true),
            focusedFieldValueObserver: observer, focusedFieldReader: { nil },
            frontmostBundleIdentifier: { "com.example.editor" }, panel: panel)
        defer {
            coordinator.stop()
            panel.hide()
        }

        let screen = try #require(NSScreen.screens.first).visibleFrame
        // Inside its field, since a caret outside it cannot anchor a ghost.
        let caret = CGRect(x: screen.minX + 200, y: screen.midY - 5, width: 0, height: 17)
        let field = CGRect(x: screen.minX + 100, y: screen.midY - 10, width: 500, height: 24)
        let snapshot = FocusedFieldSnapshot(
            bundleIdentifier: "com.example.editor", applicationName: "Editor", role: "AXTextField",
            value: "meet", selection: NSRange(location: 4, length: 0), caret: caret,
            window: screen, field: field)

        coordinator.draw(
            SuggestionUpdate(suggestion: .certain("meet later"), armed: .tab, silence: nil),
            in: snapshot)
        coordinator.watchFocusedFieldValues()
        observer.simulateNativeMenuOpened()

        #expect(coordinator.armedOffer == nil)
        #expect(!panel.isShowing)
    }
}
