import ApplicationServices

/// Routes an Accessibility callback to actor-isolated UI state.
@MainActor
final class FocusedFieldValueObserverCallbackContext {
    private let onFocusedElementChanged: @MainActor () -> Void
    private let onNotification: @MainActor (String) -> Void
    private let onObserverReset: @MainActor () -> Void
    private let isCurrent: @MainActor () -> Bool

    init(
        onFocusedElementChanged: @escaping @MainActor () -> Void,
        onNotification: @escaping @MainActor (String) -> Void,
        onObserverReset: @escaping @MainActor () -> Void,
        isCurrent: @escaping @MainActor () -> Bool
    ) {
        self.onFocusedElementChanged = onFocusedElementChanged
        self.onNotification = onNotification
        self.onObserverReset = onObserverReset
        self.isCurrent = isCurrent
    }

    func received(_ notification: String) {
        guard isCurrent() else { return }
        if notification == kAXFocusedUIElementChangedNotification as String {
            onFocusedElementChanged()
        } else {
            onNotification(notification)
        }
    }

    func reset() {
        guard isCurrent() else { return }
        onObserverReset()
    }
}
