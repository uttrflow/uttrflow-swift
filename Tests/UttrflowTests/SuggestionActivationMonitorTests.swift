import AppKit
import Foundation
import Synchronization
import Testing

@testable import Uttrflow

@MainActor
@Suite("Suggestion activation checks Accessibility trust")
struct SuggestionActivationMonitorTests {
    @Test("rechecks trust as the app becomes active")
    func checksTrustOnEveryActivation() {
        let notifications = NotificationCenter()
        let accessibilityIsTrusted = Mutex(false)
        let observedTrust = Mutex([SuggestionActivationTrust]())
        let monitor = SuggestionActivationMonitor(
            notificationCenter: notifications,
            accessibilityIsTrusted: { accessibilityIsTrusted.withLock { $0 } },
            activated: { trust in observedTrust.withLock { $0.append(trust) } })
        monitor.start()

        notifications.post(name: NSWorkspace.didActivateApplicationNotification, object: nil)
        accessibilityIsTrusted.withLock { $0 = true }
        notifications.post(name: NSWorkspace.didActivateApplicationNotification, object: nil)
        accessibilityIsTrusted.withLock { $0 = false }
        notifications.post(name: NSWorkspace.didActivateApplicationNotification, object: nil)
        accessibilityIsTrusted.withLock { $0 = true }
        notifications.post(name: NSWorkspace.didActivateApplicationNotification, object: nil)

        #expect(observedTrust.withLock { $0 } == [.denied, .granted, .denied, .granted])
        monitor.stop()
        accessibilityIsTrusted.withLock { $0 = false }
        notifications.post(name: NSWorkspace.didActivateApplicationNotification, object: nil)
        #expect(observedTrust.withLock { $0 } == [.denied, .granted, .denied, .granted])
    }
}
