import AppKit

/// Wires the opener to macOS; untestable, as it hands an address to the system to open.
extension SystemSettingsOpener {
    /// Uses the workspace that owns system URLs on this Mac.
    public init() {
        self.init(openURL: { NSWorkspace.shared.open($0) })
    }
}
