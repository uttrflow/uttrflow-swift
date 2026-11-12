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

    @Test("a refused accept rechecks trust and reports only its loss, so returning grants again")
    func recheckReportsOnlyLostTrust() {
        let notifications = NotificationCenter()
        let accessibilityIsTrusted = Mutex(true)
        let observedTrust = Mutex([SuggestionActivationTrust]())
        let monitor = SuggestionActivationMonitor(
            notificationCenter: notifications,
            accessibilityIsTrusted: { accessibilityIsTrusted.withLock { $0 } },
            activated: { trust in observedTrust.withLock { $0.append(trust) } })

        accessibilityIsTrusted.withLock { $0 = false }
        monitor.recheckForLoss()
        #expect(observedTrust.withLock { $0 }.isEmpty)

        accessibilityIsTrusted.withLock { $0 = true }
        monitor.start()
        monitor.recheckForLoss()
        #expect(observedTrust.withLock { $0 }.isEmpty)

        accessibilityIsTrusted.withLock { $0 = false }
        monitor.recheckForLoss()
        accessibilityIsTrusted.withLock { $0 = true }
        notifications.post(name: NSWorkspace.didActivateApplicationNotification, object: nil)
        #expect(observedTrust.withLock { $0 } == [.denied, .granted])
        monitor.stop()
    }
}

@Suite("What an activation does to suggestions")
struct SuggestionTrustResponseTests {
    @Test(
        "secure keyboard entry on after the check holds every activation",
        arguments: [
            SuggestionActivationTrust.trusted, .granted, .denied,
        ])
    func secureInputHoldsEverything(trust: SuggestionActivationTrust) {
        #expect(SuggestionTrustResponse.to(trust, secureInput: .blocking) == .holdForSecureInput)
    }

    @Test("trust taken away stops watching, even as secure entry lifts")
    func deniedStopsWatching() {
        #expect(SuggestionTrustResponse.to(.denied, secureInput: .clear) == .stopWatching)
        #expect(SuggestionTrustResponse.to(.denied, secureInput: .lifted) == .stopWatching)
    }

    @Test("only trust just granted starts the tap, and not when secure entry's lift already started it")
    func grantedStartsTheTapOnce() {
        #expect(SuggestionTrustResponse.to(.granted, secureInput: .clear) == .follow(startsTap: true))
        #expect(SuggestionTrustResponse.to(.granted, secureInput: .lifted) == .follow(startsTap: false))
        #expect(SuggestionTrustResponse.to(.trusted, secureInput: .clear) == .follow(startsTap: false))
    }
}
