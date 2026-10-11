import ApplicationServices
import Foundation

/// The platform calls the observer state machine needs; test handles need no running application.
protocol FocusedFieldAXClient {
    associatedtype Observer
    associatedtype Element
    func observer(for process: pid_t) -> Observer?
    func application(for process: pid_t) -> Element
    func setTimeout(_ element: Element) -> AXError
    func addSource(_ observer: Observer)
    func removeSource(_ observer: Observer)
    func addNotification(
        _ observer: Observer, _ element: Element, _ name: CFString, _ context: UnsafeMutableRawPointer
    ) -> AXError
    func removeNotification(_ observer: Observer, _ element: Element, _ name: CFString) -> AXError
    func focusedElement(of application: Element) -> Element?
    func equal(_ first: Element, _ second: Element) -> Bool
}

/// Adapts the native AX handles without changing observer registration or its run-loop ownership.
struct SystemFocusedFieldAXClient: FocusedFieldAXClient {
    func observer(for process: pid_t) -> AXObserver? {
        var observer: AXObserver?
        guard AXObserverCreate(process, focusedFieldAXObserverCallback, &observer) == .success else {
            return nil
        }
        return observer
    }
    func application(for process: pid_t) -> AXUIElement { AXUIElementCreateApplication(process) }
    func setTimeout(_ element: AXUIElement) -> AXError { AXUIElementSetMessagingTimeout(element, 0.2) }
    func addSource(_ observer: AXObserver) {
        CFRunLoopAddSource(CFRunLoopGetMain(), AXObserverGetRunLoopSource(observer), .commonModes)
    }
    func removeSource(_ observer: AXObserver) {
        CFRunLoopRemoveSource(CFRunLoopGetMain(), AXObserverGetRunLoopSource(observer), .commonModes)
    }
    func addNotification(
        _ observer: AXObserver, _ element: AXUIElement, _ name: CFString, _ context: UnsafeMutableRawPointer
    ) -> AXError {
        AXObserverAddNotification(observer, element, name, context)
    }
    func removeNotification(_ observer: AXObserver, _ element: AXUIElement, _ name: CFString) -> AXError {
        AXObserverRemoveNotification(observer, element, name)
    }
    func focusedElement(of application: AXUIElement) -> AXUIElement? {
        var value: CFTypeRef?
        guard
            AXUIElementCopyAttributeValue(application, kAXFocusedUIElementAttribute as CFString, &value)
                == .success,
            let value, CFGetTypeID(value) == AXUIElementGetTypeID()
        else { return nil }
        return unsafeDowncast(value, to: AXUIElement.self)
    }
    func equal(_ first: AXUIElement, _ second: AXUIElement) -> Bool { CFEqual(first, second) }
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
