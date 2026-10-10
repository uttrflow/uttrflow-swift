import AppKit
import ApplicationServices
import Foundation

/// Owns the AX observer state; unchecked Sendable holds because only the observer's serial queue touches it.
final class SystemFocusedFieldAXWorker: FocusedFieldAXWorking, @unchecked Sendable {
    private var observer: AXObserver?
    private var application: AXUIElement?
    private var focusedElement: AXUIElement?
    private var target: FocusedFieldObservationTarget?
    private var retainedCallbackContext: UnsafeMutableRawPointer?
    private var callbackContext: FocusedFieldValueObserverCallbackContext?

    func observe(
        _ target: FocusedFieldObservationTarget?,
        callbackContext: FocusedFieldValueObserverCallbackContext,
        isCurrent: @Sendable () -> Bool
    ) {
        guard isCurrent() else { return }
        guard let target else {
            removeObserver()
            return
        }
        if self.target != target || self.callbackContext !== callbackContext,
            !installObserver(for: target, callbackContext: callbackContext, isCurrent: isCurrent)
        {
            return
        }
        guard isCurrent(), updateFocusedElement(isCurrent: isCurrent) else {
            removeObserver()
            return
        }
    }

    func focusedElementChanged(isCurrent: @Sendable () -> Bool) {
        guard isCurrent(), updateFocusedElement(isCurrent: isCurrent) else {
            removeObserver()
            return
        }
    }

    func stop() {
        removeObserver()
    }

    private func installObserver(
        for target: FocusedFieldObservationTarget,
        callbackContext: FocusedFieldValueObserverCallbackContext,
        isCurrent: @Sendable () -> Bool
    ) -> Bool {
        removeObserver()
        guard isCurrent() else { return false }
        var created: AXObserver?
        guard
            AXObserverCreate(
                target.processIdentifier, focusedFieldAXObserverCallback, &created) == .success,
            let created
        else { return isCurrent() }
        guard isCurrent() else { return false }

        let application = AXUIElementCreateApplication(target.processIdentifier)
        _ = AXUIElementSetMessagingTimeout(application, 0.2)
        guard isCurrent() else { return false }
        let context = Unmanaged.passRetained(callbackContext).toOpaque()
        observer = created
        self.application = application
        self.target = target
        retainedCallbackContext = context
        self.callbackContext = callbackContext
        CFRunLoopAddSource(CFRunLoopGetMain(), AXObserverGetRunLoopSource(created), .commonModes)
        guard isCurrent() else {
            removeObserver()
            return false
        }
        _ = AXObserverAddNotification(
            created, application, kAXFocusedUIElementChangedNotification as CFString, context)
        guard isCurrent() else {
            removeObserver()
            return false
        }
        let menuNotificationsRegistered = registerPairedNativeMenuNotifications(
            registerOpened: {
                guard isCurrent() else { return false }
                let result =
                    AXObserverAddNotification(
                        created, application, kAXMenuOpenedNotification as CFString, context) == .success
                return result && isCurrent()
            },
            registerClosed: {
                guard isCurrent() else { return false }
                let result =
                    AXObserverAddNotification(
                        created, application, kAXMenuClosedNotification as CFString, context) == .success
                return result && isCurrent()
            },
            removeOpened: {
                _ = AXObserverRemoveNotification(
                    created, application, kAXMenuOpenedNotification as CFString)
            },
            removeClosed: {
                _ = AXObserverRemoveNotification(
                    created, application, kAXMenuClosedNotification as CFString)
            })
        guard isCurrent(), menuNotificationsRegistered else {
            removeObserver()
            return false
        }
        return true
    }

    private func updateFocusedElement(isCurrent: @Sendable () -> Bool) -> Bool {
        guard isCurrent() else { return false }
        guard observer != nil, let application else { return true }
        var value: CFTypeRef?
        let result = AXUIElementCopyAttributeValue(
            application, kAXFocusedUIElementAttribute as CFString, &value)
        guard isCurrent() else { return false }
        guard result == .success, let value, CFGetTypeID(value) == AXUIElementGetTypeID() else {
            return setFocusedElement(nil, isCurrent: isCurrent)
        }
        let focused = unsafeDowncast(value, to: AXUIElement.self)
        if let focusedElement, CFEqual(focusedElement, focused) { return true }
        return setFocusedElement(focused, isCurrent: isCurrent)
    }

    private func setFocusedElement(
        _ focused: AXUIElement?, isCurrent: @Sendable () -> Bool
    ) -> Bool {
        guard isCurrent() else { return false }
        guard let observer else { return true }
        if let focusedElement {
            _ = AXObserverRemoveNotification(
                observer, focusedElement, kAXValueChangedNotification as CFString)
            guard isCurrent() else { return false }
        }
        focusedElement = focused
        if let focused, let retainedCallbackContext {
            _ = AXUIElementSetMessagingTimeout(focused, 0.2)
            guard isCurrent() else { return false }
            _ = AXObserverAddNotification(
                observer, focused, kAXValueChangedNotification as CFString, retainedCallbackContext)
            guard isCurrent() else { return false }
        }
        return true
    }

    private func removeObserver() {
        guard let observer else {
            application = nil
            focusedElement = nil
            target = nil
            return
        }
        if let application {
            _ = AXObserverRemoveNotification(
                observer, application, kAXFocusedUIElementChangedNotification as CFString)
            _ = AXObserverRemoveNotification(
                observer, application, kAXMenuOpenedNotification as CFString)
            _ = AXObserverRemoveNotification(
                observer, application, kAXMenuClosedNotification as CFString)
        }
        if let focusedElement {
            _ = AXObserverRemoveNotification(
                observer, focusedElement, kAXValueChangedNotification as CFString)
        }
        CFRunLoopRemoveSource(CFRunLoopGetMain(), AXObserverGetRunLoopSource(observer), .commonModes)
        self.observer = nil
        application = nil
        focusedElement = nil
        target = nil
        if let callbackContext {
            DispatchQueue.main.async { @MainActor in callbackContext.reset() }
        }
        self.callbackContext = nil
        if let retainedCallbackContext {
            let address = UInt(bitPattern: retainedCallbackContext)
            DispatchQueue.main.async {
                guard let pointer = UnsafeMutableRawPointer(bitPattern: address) else { return }
                Unmanaged<FocusedFieldValueObserverCallbackContext>.fromOpaque(pointer).release()
            }
        }
        retainedCallbackContext = nil
    }
}

private func focusedFieldAXObserverCallback(
    _ observer: AXObserver, _ element: AXUIElement, _ notification: CFString,
    _ context: UnsafeMutableRawPointer?
) {
    guard let context else { return }
    let callbackContext = Unmanaged<FocusedFieldValueObserverCallbackContext>
        .fromOpaque(context).takeUnretainedValue()
    let notificationName = notification as String
    MainActor.assumeIsolated { callbackContext.received(notificationName) }
}
