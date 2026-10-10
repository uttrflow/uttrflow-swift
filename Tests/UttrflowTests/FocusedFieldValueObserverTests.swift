import AppKit
import Dispatch
import Foundation
import Synchronization
import Testing
import UttrflowContext
import UttrflowInput
import UttrflowPredict

@testable import Uttrflow

private func wait(
    for semaphore: DispatchSemaphore, until deadline: DispatchTime
) async -> DispatchTimeoutResult {
    await withCheckedContinuation { continuation in
        DispatchQueue.global(qos: .utility).async {
            continuation.resume(returning: semaphore.wait(timeout: deadline))
        }
    }
}

/// Releases a blocked worker after ten seconds, so a failing test cannot hang the run; built off the main actor to run on a global queue.
private func releaseWatchdog(for worker: BlockingFocusedFieldAXWorker) -> DispatchWorkItem {
    DispatchWorkItem {
        guard worker.watchdogArmed.wait(timeout: .now() + .seconds(10)) == .success else { return }
        if worker.cancelWatchdog.wait(timeout: .now() + .seconds(10)) == .timedOut {
            worker.release.signal()
        }
    }
}

@MainActor
private final class FakeFocusedFieldValueObserver: FocusedFieldValueObserving {
    private var onValueChanged: (@MainActor () -> Void)?
    private var onNativeMenuVisibilityChanged: (@MainActor (Bool) -> Void)?

    func start(
        for target: FocusedFieldObservationTarget?,
        onValueChanged: @escaping @MainActor () -> Void,
        onNativeMenuVisibilityChanged: @escaping @MainActor (Bool) -> Void
    ) {
        self.onValueChanged = onValueChanged
        self.onNativeMenuVisibilityChanged = onNativeMenuVisibilityChanged
    }

    func refresh(for target: FocusedFieldObservationTarget?) {}
    func stop() {
        onValueChanged = nil
        onNativeMenuVisibilityChanged = nil
    }
    func simulateAXValueChange() { onValueChanged?() }
    func simulateNativeMenuOpened() { onNativeMenuVisibilityChanged?(true) }
}

/// Blocks one chosen queued AX operation so the caller's return can be observed; NSLock guards its tallies.
private final class BlockingFocusedFieldAXWorker: FocusedFieldAXWorking, @unchecked Sendable {
    let entered = DispatchSemaphore(value: 0)
    let observed = DispatchSemaphore(value: 0)
    let release = DispatchSemaphore(value: 0)
    let finishedBlocking = DispatchSemaphore(value: 0)
    let watchdogArmed = DispatchSemaphore(value: 0)
    let cancelWatchdog = DispatchSemaphore(value: 0)
    let cancelled = DispatchSemaphore(value: 0)
    let completed = DispatchSemaphore(value: 0)
    let stopped = DispatchSemaphore(value: 0)
    private let lock = NSLock()
    private let blockingObservation: Int
    private var observationCount = 0
    private var targets: [FocusedFieldObservationTarget?] = []
    private var contexts: [FocusedFieldValueObserverCallbackContext] = []
    private var completedTargets: [FocusedFieldObservationTarget?] = []

    init(blockingObservation: Int = 1) {
        self.blockingObservation = blockingObservation
    }

    var observedTargets: [FocusedFieldObservationTarget?] { lock.withLock { targets } }
    var observedContexts: [FocusedFieldValueObserverCallbackContext] { lock.withLock { contexts } }
    var completedObservations: [FocusedFieldObservationTarget?] { lock.withLock { completedTargets } }

    func observe(
        _ target: FocusedFieldObservationTarget?,
        callbackContext: FocusedFieldValueObserverCallbackContext,
        isCurrent: @Sendable () -> Bool
    ) {
        let shouldBlock = lock.withLock {
            observationCount += 1
            targets.append(target)
            contexts.append(callbackContext)
            return observationCount == blockingObservation
        }
        observed.signal()
        if shouldBlock {
            entered.signal()
            watchdogArmed.signal()
            release.wait()
            finishedBlocking.signal()
        }
        guard isCurrent() else {
            cancelled.signal()
            return
        }
        lock.withLock { completedTargets.append(target) }
        completed.signal()
    }

    func focusedElementChanged(isCurrent: @Sendable () -> Bool) {}
    func stop() { stopped.signal() }
}

@MainActor
@Suite("AX value changes withdraw stale suggestion offers", .serialized)
struct FocusedFieldValueObserverTests {
    @Test("a mouse refresh returns while the AX worker is blocked")
    func mouseRefreshReturnsBeforeBlockingAccessibilityWork() async {
        let worker = BlockingFocusedFieldAXWorker(blockingObservation: 2)
        let observer = FocusedFieldValueObserver(worker: worker)
        let target = FocusedFieldObservationTarget(
            processIdentifier: 123, bundleIdentifier: "com.example.editor")
        observer.start(for: target, onValueChanged: {}, onNativeMenuVisibilityChanged: { _ in })
        #expect(await wait(for: worker.completed, until: .now() + 1) == .success)

        let watchdog = releaseWatchdog(for: worker)
        DispatchQueue.global(qos: .utility).async(execute: watchdog)

        observer.refresh(for: target)
        #expect(await wait(for: worker.entered, until: .now() + 1) == .success)

        let returnedBeforeWorkerFinished =
            await wait(for: worker.finishedBlocking, until: .now()) == .timedOut
        worker.release.signal()
        worker.cancelWatchdog.signal()
        watchdog.cancel()
        #expect(await wait(for: worker.finishedBlocking, until: .now() + 1) == .success)
        #expect(returnedBeforeWorkerFinished)
        observer.stop()
    }

    @Test("a click or app switch refresh returns while the AX worker is blocked")
    func coordinatorRefreshReturnsBeforeBlockingAccessibilityWork() async throws {
        let container = FileManager.default.temporaryDirectory.appending(
            path: "ax-coordinator-refresh-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: container, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: container) }

        let worker = BlockingFocusedFieldAXWorker(blockingObservation: 2)
        let observer = FocusedFieldValueObserver(worker: worker)
        let coordinator = try await SuggestionCoordinator(
            container: container, preferences: SuggestionPreferences(isEnabled: true),
            focusedFieldValueObserver: observer, focusedFieldReader: { nil },
            frontmostBundleIdentifier: { "com.example.editor" })
        defer {
            worker.release.signal()
            coordinator.stop()
        }

        coordinator.watchFocusedFieldValues()
        #expect(await wait(for: worker.completed, until: .now() + 1) == .success)

        let watchdog = releaseWatchdog(for: worker)
        DispatchQueue.global(qos: .utility).async(execute: watchdog)
        coordinator.refreshFocusedFieldObservation()
        #expect(await wait(for: worker.entered, until: .now() + 1) == .success)

        let returnedBeforeWorkerFinished =
            await wait(for: worker.finishedBlocking, until: .now()) == .timedOut
        worker.release.signal()
        worker.cancelWatchdog.signal()
        watchdog.cancel()
        #expect(await wait(for: worker.finishedBlocking, until: .now() + 1) == .success)
        #expect(returnedBeforeWorkerFinished)
    }

    @Test("turning suggestions off in the front app hands the observer no target")
    func turningTheFrontAppOffStopsObservingIt() async throws {
        let container = FileManager.default.temporaryDirectory.appending(
            path: "ax-coordinator-off-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: container, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: container) }

        let worker = BlockingFocusedFieldAXWorker(blockingObservation: 0)
        let observer = FocusedFieldValueObserver(worker: worker)
        let coordinator = try await SuggestionCoordinator(
            container: container, preferences: SuggestionPreferences(isEnabled: true),
            focusedFieldValueObserver: observer, focusedFieldReader: { nil },
            frontmostBundleIdentifier: { "com.example.editor" })
        defer { coordinator.stop() }

        coordinator.watchFocusedFieldValues()
        #expect(await wait(for: worker.observed, until: .now() + 1) == .success)
        coordinator.follow(SuggestionPreferences(isEnabled: true, turnedOff: ["com.example.editor"]))
        #expect(await wait(for: worker.observed, until: .now() + 1) == .success)

        #expect(worker.observedTargets.last == .some(nil))
        #expect(coordinator.focusedFieldObservationTarget() == nil)
    }

    @Test("disabled applications produce no Accessibility observation target")
    func disabledApplicationsAreNotObserved() async {
        let moment = Date(timeIntervalSince1970: 1_800_000_000)
        let preferences = SuggestionPreferences(isEnabled: true, turnedOff: ["com.example.editor"])

        let target = SuggestionCoordinator.focusedFieldObservationTarget(
            processIdentifier: 123, bundleIdentifier: "com.example.editor", ownBundleIdentifier: nil,
            preferences: preferences, at: moment)
        #expect(target == nil)

        let worker = BlockingFocusedFieldAXWorker()
        let observer = FocusedFieldValueObserver(worker: worker)
        observer.start(for: target, onValueChanged: {}, onNativeMenuVisibilityChanged: { _ in })
        #expect(await wait(for: worker.observed, until: .now() + 1) == .success)
        #expect(worker.observedTargets == [nil])
        observer.stop()

        let globallyDisabled = SuggestionCoordinator.focusedFieldObservationTarget(
            processIdentifier: 123, bundleIdentifier: "com.example.editor", ownBundleIdentifier: nil,
            preferences: SuggestionPreferences(isEnabled: false), at: moment)
        #expect(globallyDisabled == nil)
    }

    @Test("a disabled target invalidates an enabled observation queued behind AX work")
    func disablingTargetSkipsQueuedAXObservation() async {
        let inFlight = FocusedFieldObservationTarget(
            processIdentifier: 123, bundleIdentifier: "com.example.editor")
        let queuedEnabled = FocusedFieldObservationTarget(
            processIdentifier: 456, bundleIdentifier: "com.example.other-editor")
        let disabled = SuggestionCoordinator.focusedFieldObservationTarget(
            processIdentifier: queuedEnabled.processIdentifier,
            bundleIdentifier: queuedEnabled.bundleIdentifier, ownBundleIdentifier: nil,
            preferences: SuggestionPreferences(isEnabled: true, turnedOff: [queuedEnabled.bundleIdentifier]),
            at: Date())
        #expect(disabled == nil)

        let worker = BlockingFocusedFieldAXWorker()
        let observer = FocusedFieldValueObserver(worker: worker)
        observer.start(for: inFlight, onValueChanged: {}, onNativeMenuVisibilityChanged: { _ in })
        #expect(await wait(for: worker.entered, until: .now() + 1) == .success)
        #expect(await wait(for: worker.observed, until: .now() + 1) == .success)

        observer.refresh(for: queuedEnabled)
        observer.refresh(for: disabled)
        worker.release.signal()

        #expect(await wait(for: worker.finishedBlocking, until: .now() + 1) == .success)
        #expect(await wait(for: worker.observed, until: .now() + 1) == .success)
        #expect(worker.observedTargets == [inFlight, nil])
        observer.stop()
    }

    @Test("an in-flight observation stops before its next AX step when the target changes")
    func inFlightObservationStopsAfterTargetInvalidation() async {
        let first = FocusedFieldObservationTarget(
            processIdentifier: 123, bundleIdentifier: "com.example.first")
        let second = FocusedFieldObservationTarget(
            processIdentifier: 456, bundleIdentifier: "com.example.second")
        let worker = BlockingFocusedFieldAXWorker()
        let observer = FocusedFieldValueObserver(worker: worker)
        var valueChanges = 0
        var menuChanges: [Bool] = []
        observer.start(
            for: first,
            onValueChanged: { valueChanges += 1 },
            onNativeMenuVisibilityChanged: { menuChanges.append($0) })
        #expect(await wait(for: worker.entered, until: .now() + 1) == .success)
        let oldContext = worker.observedContexts[0]

        observer.refresh(for: second)
        oldContext.received(kAXValueChangedNotification as String)
        #expect(valueChanges == 0)
        worker.release.signal()

        #expect(await wait(for: worker.finishedBlocking, until: .now() + 1) == .success)
        #expect(await wait(for: worker.cancelled, until: .now() + 1) == .success)
        #expect(await wait(for: worker.completed, until: .now() + 1) == .success)
        #expect(worker.observedTargets == [first, second])
        #expect(worker.completedObservations == [second])
        let currentContext = worker.observedContexts[1]
        currentContext.received(kAXMenuOpenedNotification as String)
        oldContext.reset()
        #expect(menuChanges == [true])
        observer.stop()
    }

    @Test("an old observer callback cannot reach a restarted session")
    func oldCallbackIsIgnoredAfterStopAndRestart() async {
        let target = FocusedFieldObservationTarget(
            processIdentifier: 123, bundleIdentifier: "com.example.editor")
        let worker = BlockingFocusedFieldAXWorker()
        let observer = FocusedFieldValueObserver(worker: worker)
        var newSessionValueChanges = 0
        observer.start(for: target, onValueChanged: {}, onNativeMenuVisibilityChanged: { _ in })
        #expect(await wait(for: worker.entered, until: .now() + 1) == .success)
        let oldContext = worker.observedContexts[0]

        observer.stop()
        observer.start(
            for: target,
            onValueChanged: { newSessionValueChanges += 1 },
            onNativeMenuVisibilityChanged: { _ in })
        oldContext.received(kAXValueChangedNotification as String)
        #expect(newSessionValueChanges == 0)

        worker.release.signal()
        #expect(await wait(for: worker.finishedBlocking, until: .now() + 1) == .success)
        #expect(await wait(for: worker.cancelled, until: .now() + 1) == .success)
        #expect(await wait(for: worker.completed, until: .now() + 1) == .success)
        #expect(worker.completedObservations == [target])
        observer.stop()
    }

    @Test("stop invalidates enabled observations still queued behind AX work")
    func stoppingObserverSkipsQueuedAXObservation() async {
        let inFlight = FocusedFieldObservationTarget(
            processIdentifier: 123, bundleIdentifier: "com.example.editor")
        let queued = FocusedFieldObservationTarget(
            processIdentifier: 456, bundleIdentifier: "com.example.other-editor")
        let worker = BlockingFocusedFieldAXWorker()
        let observer = FocusedFieldValueObserver(worker: worker)
        observer.start(for: inFlight, onValueChanged: {}, onNativeMenuVisibilityChanged: { _ in })
        #expect(await wait(for: worker.entered, until: .now() + 1) == .success)
        #expect(await wait(for: worker.observed, until: .now() + 1) == .success)

        observer.refresh(for: queued)
        observer.stop()
        worker.release.signal()

        #expect(await wait(for: worker.finishedBlocking, until: .now() + 1) == .success)
        #expect(await wait(for: worker.stopped, until: .now() + 1) == .success)
        #expect(worker.observedTargets == [inFlight])
    }

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
    func axValueChangeWithdrawsTheOffer() async throws {
        let container = FileManager.default.temporaryDirectory.appending(
            path: "ax-value-change-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: container, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: container) }

        let observer = FakeFocusedFieldValueObserver()
        let panel = SuggestionPanelController()
        let coordinator = try await SuggestionCoordinator(
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
    func secureInputStartingWithoutActivationDrawsNothing() async throws {
        let container = FileManager.default.temporaryDirectory.appending(
            path: "secure-input-starts-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: container, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: container) }

        let secure = Mutex(false)
        let panel = SuggestionPanelController()
        let coordinator = try await SuggestionCoordinator(
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
        let coordinator = try await SuggestionCoordinator(
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
    func axMenuOpeningWithdrawsTheOffer() async throws {
        let container = FileManager.default.temporaryDirectory.appending(
            path: "ax-menu-open-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: container, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: container) }

        let observer = FakeFocusedFieldValueObserver()
        let panel = SuggestionPanelController()
        let coordinator = try await SuggestionCoordinator(
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
