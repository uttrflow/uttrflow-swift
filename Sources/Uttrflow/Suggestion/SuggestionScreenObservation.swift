import AppKit
import Foundation

/// Owns a screen-change registration and removes it from the center that created it.
@MainActor
final class SuggestionScreenObservation {
    private let center: NotificationCenter
    private let token: any NSObjectProtocol

    init(center: NotificationCenter, changed: @escaping @MainActor () -> Void) {
        self.center = center
        token = center.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: .main
        ) { _ in
            MainActor.assumeIsolated { changed() }
        }
    }

    isolated deinit { center.removeObserver(token) }
}
