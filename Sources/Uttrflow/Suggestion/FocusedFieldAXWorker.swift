import AppKit
import ApplicationServices
import Foundation

/// Owns the AX observer state; unchecked Sendable holds because only the observer's serial queue touches it.
final class FocusedFieldAXWorker<Client: FocusedFieldAXClient>: FocusedFieldAXWorking, @unchecked Sendable {
    private let client: Client
    private var observer: Client.Observer?
    private var application: Client.Element?
    private var focusedElement: Client.Element?
    private var target: FocusedFieldObservationTarget?
    private var retainedCallbackContext: UnsafeMutableRawPointer?
    private var callbackContext: FocusedFieldValueObserverCallbackContext?

    init(client: Client) { self.client = client }

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
        guard let created = client.observer(for: target.processIdentifier) else { return isCurrent() }
        guard isCurrent() else { return false }

        let application = client.application(for: target.processIdentifier)
        _ = client.setTimeout(application)
        guard isCurrent() else { return false }
        let context = Unmanaged.passRetained(callbackContext).toOpaque()
        observer = created
        self.application = application
        self.target = target
        retainedCallbackContext = context
        self.callbackContext = callbackContext
        client.addSource(created)
        guard isCurrent() else {
            removeObserver()
            return false
        }
        _ = client.addNotification(
            created, application, kAXFocusedUIElementChangedNotification as CFString, context)
        guard isCurrent() else {
            removeObserver()
            return false
        }
        let menuNotificationsRegistered = registerPairedNativeMenuNotifications(
            registerOpened: {
                guard isCurrent() else { return false }
                let result =
                    client.addNotification(
                        created, application, kAXMenuOpenedNotification as CFString, context) == .success
                return result && isCurrent()
            },
            registerClosed: {
                guard isCurrent() else { return false }
                let result =
                    client.addNotification(
                        created, application, kAXMenuClosedNotification as CFString, context) == .success
                return result && isCurrent()
            },
            removeOpened: {
                _ = client.removeNotification(
                    created, application, kAXMenuOpenedNotification as CFString)
            },
            removeClosed: {
                _ = client.removeNotification(
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
        let focused = client.focusedElement(of: application)
        guard isCurrent() else { return false }
        guard let focused else { return setFocusedElement(nil, isCurrent: isCurrent) }
        if let focusedElement, client.equal(focusedElement, focused) { return true }
        return setFocusedElement(focused, isCurrent: isCurrent)
    }

    private func setFocusedElement(
        _ focused: Client.Element?, isCurrent: @Sendable () -> Bool
    ) -> Bool {
        guard isCurrent() else { return false }
        guard let observer else { return true }
        if let focusedElement {
            _ = client.removeNotification(
                observer, focusedElement, kAXValueChangedNotification as CFString)
            guard isCurrent() else { return false }
        }
        focusedElement = focused
        if let focused, let retainedCallbackContext {
            _ = client.setTimeout(focused)
            guard isCurrent() else { return false }
            _ = client.addNotification(
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
            _ = client.removeNotification(
                observer, application, kAXFocusedUIElementChangedNotification as CFString)
            _ = client.removeNotification(
                observer, application, kAXMenuOpenedNotification as CFString)
            _ = client.removeNotification(
                observer, application, kAXMenuClosedNotification as CFString)
        }
        if let focusedElement {
            _ = client.removeNotification(
                observer, focusedElement, kAXValueChangedNotification as CFString)
        }
        client.removeSource(observer)
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

typealias SystemFocusedFieldAXWorker = FocusedFieldAXWorker<SystemFocusedFieldAXClient>

extension FocusedFieldAXWorker where Client == SystemFocusedFieldAXClient {
    convenience init() { self.init(client: SystemFocusedFieldAXClient()) }
}
