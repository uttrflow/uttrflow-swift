import AppKit
import Foundation
public import UttrflowCore

/// Owns the macOS addresses used when a recovery action sends the user to System Settings.
public struct SystemSettingsOpener: Sendable {
    private let openURL: @Sendable (URL) -> Void

    /// Uses the workspace that owns system URLs on this Mac.
    public init() {
        self.init(openURL: { NSWorkspace.shared.open($0) })
    }

    /// Substitutes the workspace boundary for tests.
    init(openURL: @escaping @Sendable (URL) -> Void) {
        self.openURL = openURL
    }

    /// Opens the requested pane.
    public func open(_ pane: SystemSettingsPane) {
        guard let url = Self.url(for: pane) else { return }
        openURL(url)
    }

    /// The stable system address for a recovery pane.
    static func url(for pane: SystemSettingsPane) -> URL? {
        let address =
            switch pane {
            case .microphone:
                "x-apple.systempreferences:com.apple.preference.security?Privacy_Microphone"
            case .accessibility:
                "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility"
            case .appleIntelligence:
                "x-apple.systempreferences:com.apple.Siri-Settings.extension"
            }
        return URL(string: address)
    }
}
