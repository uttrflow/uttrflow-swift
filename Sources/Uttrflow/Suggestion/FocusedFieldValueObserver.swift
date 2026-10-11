import AppKit
import ApplicationServices
import Foundation
private import Synchronization

/// Invalidates queued AX requests when a newer target or stop supersedes them.
private final class FocusedFieldAXRequestGate: Sendable {
    private let generation = Mutex<UInt64>(0)

    @discardableResult
    func advance() -> UInt64 {
        generation.withLock { value in
            value &+= 1
            return value
        }
    }

    func current() -> UInt64 { generation.withLock { $0 } }

    func isCurrent(_ expected: UInt64) -> Bool { generation.withLock { $0 == expected } }
}

@MainActor
protocol FocusedFieldValueObserving: AnyObject {
    func start(
        for target: FocusedFieldObservationTarget?,
        onValueChanged: @escaping @MainActor () -> Void,
        onNativeMenuVisibilityChanged: @escaping @MainActor (Bool) -> Void)
    func refresh(for target: FocusedFieldObservationTarget?)
    func stop()
}

/// A process the suggestion policy has allowed the observer to contact.
struct FocusedFieldObservationTarget: Sendable, Equatable {
    let processIdentifier: pid_t
    let bundleIdentifier: String
}

/// Tracks overlapping native menus independently of focused-element changes.
struct NativeMenuVisibilityState<Element: Hashable> {
    private(set) var focusedElement: Element?
    private var openMenuCount = 0

    var isOpen: Bool { openMenuCount > 0 }

    mutating func focusedElementChanged(to element: Element?) {
        focusedElement = element
    }

    mutating func menuOpened() {
        openMenuCount += 1
    }

    mutating func menuClosed() {
        guard openMenuCount > 0 else { return }
        openMenuCount -= 1
    }

    @discardableResult
    mutating func reset() -> Bool {
        let wasOpen = isOpen
        focusedElement = nil
        openMenuCount = 0
        return wasOpen
    }
}

/// Keeps open and close notifications registered as a pair.
@discardableResult
func registerPairedNativeMenuNotifications(
    registerOpened: () -> Bool,
    registerClosed: () -> Bool,
    removeOpened: () -> Void,
    removeClosed: () -> Void
) -> Bool {
    let openedWasRegistered = registerOpened()
    let closedWasRegistered = registerClosed()
    guard openedWasRegistered, closedWasRegistered else {
        if openedWasRegistered { removeOpened() }
        if closedWasRegistered { removeClosed() }
        return false
    }
    return true
}

/// Schedules all system Accessibility messages on one serial queue.
@MainActor
final class FocusedFieldValueObserver: FocusedFieldValueObserving {
    private let worker: any FocusedFieldAXWorking
    private let queue = DispatchQueue(label: "com.uttrflow.suggestions.focused-field-ax", qos: .utility)
    private let requestGate = FocusedFieldAXRequestGate()
    private let callbackEpoch = FocusedFieldAXRequestGate()
    private var callbackContext: FocusedFieldValueObserverCallbackContext?
    private var observationTarget: FocusedFieldObservationTarget?
    private var onValueChanged: (@MainActor () -> Void)?
    private var onNativeMenuVisibilityChanged: (@MainActor (Bool) -> Void)?
    private var nativeMenuState = NativeMenuVisibilityState<Int>()
    private var isStarted = false

    init() {
        worker = SystemFocusedFieldAXWorker()
    }

    init(worker: any FocusedFieldAXWorking) {
        self.worker = worker
    }

    isolated deinit { stop() }

    func start(
        for target: FocusedFieldObservationTarget?,
        onValueChanged: @escaping @MainActor () -> Void,
        onNativeMenuVisibilityChanged: @escaping @MainActor (Bool) -> Void
    ) {
        resetNativeMenuState()
        self.onValueChanged = onValueChanged
        self.onNativeMenuVisibilityChanged = onNativeMenuVisibilityChanged
        isStarted = true
        observationTarget = target
        let context = makeCallbackContext()
        callbackContext = context
        enqueueObservation(target, using: context, generation: requestGate.advance())
    }

    func refresh(for target: FocusedFieldObservationTarget?) {
        guard isStarted else { return }
        if target != observationTarget {
            observationTarget = target
            if nativeMenuState.reset() { onNativeMenuVisibilityChanged?(false) }
            callbackContext = makeCallbackContext()
        }
        guard let callbackContext else { return }
        enqueueObservation(target, using: callbackContext, generation: requestGate.advance())
    }

    func stop() {
        requestGate.advance()
        callbackEpoch.advance()
        isStarted = false
        observationTarget = nil
        callbackContext = nil
        if nativeMenuState.reset() { onNativeMenuVisibilityChanged?(false) }
        onValueChanged = nil
        onNativeMenuVisibilityChanged = nil
        queue.async { [worker] in worker.stop() }
    }

    private func enqueueObservation(
        _ target: FocusedFieldObservationTarget?,
        using context: FocusedFieldValueObserverCallbackContext,
        generation: UInt64
    ) {
        queue.async { [worker, requestGate] in
            guard requestGate.isCurrent(generation) else { return }
            worker.observe(
                target, callbackContext: context, isCurrent: { requestGate.isCurrent(generation) })
        }
    }

    private func scheduleFocusedElementRefresh() {
        guard isStarted else { return }
        let generation = requestGate.current()
        queue.async { [worker, requestGate] in
            guard requestGate.isCurrent(generation) else { return }
            worker.focusedElementChanged(isCurrent: { requestGate.isCurrent(generation) })
        }
    }

    private func makeCallbackContext() -> FocusedFieldValueObserverCallbackContext {
        let epoch = callbackEpoch.advance()
        return FocusedFieldValueObserverCallbackContext(
            onFocusedElementChanged: { [weak self] in self?.scheduleFocusedElementRefresh() },
            onNotification: { [weak self] in self?.received($0) },
            onObserverReset: { [weak self] in self?.resetNativeMenuState() },
            isCurrent: { [callbackEpoch] in callbackEpoch.isCurrent(epoch) })
    }

    private func received(_ notification: String) {
        if notification == kAXValueChangedNotification as String {
            onValueChanged?()
        } else if notification == kAXMenuOpenedNotification as String {
            let wasOpen = nativeMenuState.isOpen
            nativeMenuState.menuOpened()
            if !wasOpen { onNativeMenuVisibilityChanged?(true) }
        } else if notification == kAXMenuClosedNotification as String {
            let wasOpen = nativeMenuState.isOpen
            nativeMenuState.menuClosed()
            if wasOpen && !nativeMenuState.isOpen { onNativeMenuVisibilityChanged?(false) }
        }
    }

    private func resetNativeMenuState() {
        if nativeMenuState.reset() { onNativeMenuVisibilityChanged?(false) }
    }
}
