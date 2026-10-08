import Foundation
import UttrflowContext

/// Detects a moved caret or a different focused element while an offer is armed.
struct ArmedSelectionGuard {
    private static let accessibilityEchoGracePeriod: TimeInterval = 0.5

    private(set) var expectedRange: NSRange?
    private var identity: FocusedFieldIdentity?
    private var previousExpectedRange: NSRange?
    private var lastTypedThroughUptime: TimeInterval?

    init(expectedRange: NSRange?, identity: FocusedFieldIdentity? = nil) {
        self.expectedRange = expectedRange
        self.identity = identity
    }

    /// Answers whether the current Accessibility selection invalidates the offer.
    mutating func observe(
        _ selection: FocusedFieldSelection?,
        at uptime: TimeInterval = ProcessInfo.processInfo.systemUptime
    ) -> Bool {
        guard let selection, let expectedRange else { return true }
        if let identity, identity != selection.identity {
            return true
        }

        if selection.range == expectedRange {
            previousExpectedRange = nil
            lastTypedThroughUptime = nil
            identity = selection.identity
            return false
        }

        guard let previousExpectedRange, selection.range == previousExpectedRange,
            let lastTypedThroughUptime,
            uptime >= lastTypedThroughUptime,
            uptime - lastTypedThroughUptime <= Self.accessibilityEchoGracePeriod
        else { return true }

        identity = selection.identity
        return false
    }

    /// Advances the expected caret for text that the armed suggestion allows through.
    mutating func typedThrough(
        _ text: String,
        at uptime: TimeInterval = ProcessInfo.processInfo.systemUptime
    ) {
        guard let expectedRange else { return }
        previousExpectedRange = expectedRange
        lastTypedThroughUptime = uptime
        let (location, overflow) = expectedRange.location.addingReportingOverflow(text.utf16.count)
        self.expectedRange = overflow ? nil : NSRange(location: location, length: 0)
    }
}
