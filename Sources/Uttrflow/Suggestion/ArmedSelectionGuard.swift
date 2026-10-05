import Foundation
import UttrflowContext

/// Detects a moved caret or a different focused element while an offer is armed.
struct ArmedSelectionGuard {
    private(set) var expectedRange: NSRange?
    private var identity: FocusedFieldIdentity?

    init(expectedRange: NSRange?, identity: FocusedFieldIdentity? = nil) {
        self.expectedRange = expectedRange
        self.identity = identity
    }

    /// Answers whether the current Accessibility selection invalidates the offer.
    mutating func observe(_ selection: FocusedFieldSelection?) -> Bool {
        guard let selection, let expectedRange, selection.range == expectedRange else { return true }
        if let identity, identity != selection.identity {
            return true
        }
        identity = selection.identity
        return false
    }

    /// Advances the expected caret for text that the armed suggestion allows through.
    mutating func typedThrough(_ text: String) {
        guard let expectedRange else { return }
        let (location, overflow) = expectedRange.location.addingReportingOverflow(text.utf16.count)
        self.expectedRange = overflow ? nil : NSRange(location: location, length: 0)
    }
}
