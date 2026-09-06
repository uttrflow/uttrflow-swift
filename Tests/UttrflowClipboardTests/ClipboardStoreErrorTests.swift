// Tests for the clipboard store's error.

import UttrflowCore
import Testing

@testable import UttrflowClipboard

/// The `FailureCatalogue` rule applied here, because this error lives in a module Core cannot see.
@Suite("What the clipboard says when the disk refuses")
struct ClipboardStoreErrorTests {
    @Test("has a sentence for the user with no implementation detail in it")
    func everyCaseCanExplainItself() {
        for failure in ClipboardStoreError.everyCase {
            #expect(failure.userMessage.hasSuffix("."))
            #expect(failure.userMessage.first?.isUppercase == true)
            #expect(failure.recovery == nil)
            #expect(failure.severity == .degraded)
        }
    }

    /// The chain must reach every case, which is why it is a `switch` the compiler checks.
    @Test("chains every case exactly once")
    func chainIsComplete() {
        #expect(ClipboardStoreError.everyCase == [.couldNotWrite])
    }
}
