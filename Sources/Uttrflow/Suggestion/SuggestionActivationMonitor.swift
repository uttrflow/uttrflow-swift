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
