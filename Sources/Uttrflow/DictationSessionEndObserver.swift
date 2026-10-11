import AppKit

enum DictationSessionEndObserver {
    static let screenIsLocked = Notification.Name("com.apple.screenIsLocked")

    static let notices = [
        NSWorkspace.sessionDidResignActiveNotification,
        NSWorkspace.screensDidSleepNotification,
        NSWorkspace.willSleepNotification,
    ]

    static func observe(
        in center: NotificationCenter, onEnd: @escaping @Sendable () -> Void
    )
        -> [any NSObjectProtocol]
    {
        notices.map { name in
            center.addObserver(forName: name, object: nil, queue: .main) { _ in onEnd() }
        }
    }

    static func observeScreenLock(
        in center: NotificationCenter, onEnd: @escaping @Sendable () -> Void
    ) -> any NSObjectProtocol {
        center.addObserver(forName: screenIsLocked, object: nil, queue: .main) { _ in onEnd() }
    }
}
