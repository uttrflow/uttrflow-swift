import AppKit
import ApplicationServices
import Foundation

/// Reports Accessibility trust whenever another application becomes active.
@MainActor
final class SuggestionActivationMonitor {
    private let notificationCenter: NotificationCenter
    private let accessibilityIsTrusted: @MainActor () -> Bool
    private let activated: @MainActor (SuggestionActivationTrust) -> Void
    private var observer: (any NSObjectProtocol)?
    private var wasTrusted: Bool?

    init(
        notificationCenter: NotificationCenter = NSWorkspace.shared.notificationCenter,
        accessibilityIsTrusted: @escaping @MainActor () -> Bool = { AXIsProcessTrusted() },
        activated: @escaping @MainActor (SuggestionActivationTrust) -> Void
    ) {
        self.notificationCenter = notificationCenter
        self.accessibilityIsTrusted = accessibilityIsTrusted
        self.activated = activated
    }

    func start() {
        guard observer == nil else { return }
        wasTrusted = accessibilityIsTrusted()
        observer = notificationCenter.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self else { return }
                let isTrusted = self.accessibilityIsTrusted()
                let change: SuggestionActivationTrust
                if !isTrusted {
                    change = .denied
                } else if self.wasTrusted == false {
                    change = .granted
                } else {
                    change = .trusted
                }
                self.wasTrusted = isTrusted
                self.activated(change)
            }
        }
    }

    /// Reads trust between activations and reports only its loss, so a refused accept withdraws as an activation would.
    func recheckForLoss() {
        guard observer != nil, !accessibilityIsTrusted() else { return }
        wasTrusted = false
        activated(.denied)
    }

    func stop() {
        guard let observer else { return }
        notificationCenter.removeObserver(observer)
        self.observer = nil
        wasTrusted = nil
    }
}

enum SuggestionActivationTrust: Equatable {
    case trusted
    case granted
    case denied
}

/// What an activation does to suggestions, given Accessibility trust and secure keyboard entry around it.
enum SuggestionTrustResponse: Equatable {
    /// Secure keyboard entry holds everything off, and its own lift restarts the tap.
    case holdForSecureInput
    /// Trust was taken away, so nothing is watched and the tap stops.
    case stopWatching
    /// The field is followed again, and the tap starts when trust was just granted outside a secure-entry lift.
    case follow(startsTap: Bool)

    static func to(_ trust: SuggestionActivationTrust, secureInput: SecureInputTransition) -> Self {
        guard secureInput != .blocking else { return .holdForSecureInput }
        guard trust != .denied else { return .stopWatching }
        return .follow(startsTap: secureInput == .clear && trust == .granted)
    }
}
