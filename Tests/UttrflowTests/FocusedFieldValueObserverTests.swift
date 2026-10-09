import AppKit
import Foundation
import Synchronization
import Testing
import UttrflowContext
import UttrflowInput
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

    @Test("secure keyboard entry starting in the same app draws no ghost, without an activation")
    func secureInputStartingWithoutActivationDrawsNothing() throws {
        let container = FileManager.default.temporaryDirectory.appending(
            path: "secure-input-starts-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: container, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: container) }

        let secure = Mutex(false)
        let panel = SuggestionPanelController()
        let coordinator = try SuggestionCoordinator(
            container: container, preferences: SuggestionPreferences(isEnabled: true),
            secureInput: SecureInputWatch(isSecureInputOn: { secure.withLock { $0 } }),
            focusedFieldReader: { nil }, frontmostBundleIdentifier: { "com.example.editor" },
            panel: panel)
        defer {
            coordinator.stop()
            panel.hide()
        }
        let snapshot = try Self.editorSnapshot()
        let update = SuggestionUpdate(suggestion: .certain("meet later"), armed: .tab, silence: nil)

        coordinator.draw(update, in: snapshot)
        #expect(coordinator.armedOffer == "meet later" && panel.isShowing)

        secure.withLock { $0 = true }
        coordinator.draw(update, in: snapshot)

        #expect(coordinator.isSecureInputBlocking)
        #expect(coordinator.armedOffer == nil)
        #expect(!panel.isShowing)
        #expect(coordinator.isSecureInputRecheckScheduled)
    }

    @Test("secure keyboard entry ending in the same app lifts the pause, without an activation")
    func secureInputEndingWithoutActivationLiftsThePause() async throws {
        let container = FileManager.default.temporaryDirectory.appending(
            path: "secure-input-ends-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: container, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: container) }

        let secure = Mutex(true)
        let panel = SuggestionPanelController()
        let coordinator = try SuggestionCoordinator(
            container: container, preferences: SuggestionPreferences(isEnabled: true),
            secureInput: SecureInputWatch(isSecureInputOn: { secure.withLock { $0 } }),
            focusedFieldReader: { nil }, frontmostBundleIdentifier: { "com.example.editor" },
            panel: panel)
        defer {
            coordinator.stop()
            panel.hide()
        }
        let (changes, changed) = AsyncStream.makeStream(of: Bool.self)
        coordinator.onSecureInputChanged = { changed.yield($0) }
        // A pause that never lifts ends the stream rather than hanging the suite.
        let deadline = Task {
            try await Task.sleep(for: .seconds(5))
            changed.finish()
        }
        defer {
            deadline.cancel()
            changed.finish()
        }

        coordinator.draw(
            SuggestionUpdate(suggestion: .certain("meet later"), armed: .tab, silence: nil),
            in: try Self.editorSnapshot())
        var heard = changes.makeAsyncIterator()
        #expect(await heard.next() == true)

        secure.withLock { $0 = false }

        #expect(await heard.next() == false)
        #expect(!coordinator.isSecureInputBlocking)
        #expect(!coordinator.isSecureInputRecheckScheduled)
    }

    /// A field in an editor whose caret can anchor a ghost on the first screen.
    private static func editorSnapshot() throws -> FocusedFieldSnapshot {
        let screen = try #require(NSScreen.screens.first).visibleFrame
        return FocusedFieldSnapshot(
            bundleIdentifier: "com.example.editor", applicationName: "Editor", role: "AXTextField",
            value: "meet", selection: NSRange(location: 4, length: 0),
            caret: CGRect(x: screen.minX + 200, y: screen.midY - 5, width: 0, height: 17),
            window: screen, field: CGRect(x: screen.minX + 100, y: screen.midY - 10, width: 500, height: 24))
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
