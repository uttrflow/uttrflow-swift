import UttrflowCore
import Testing

@testable import UttrflowClipboard

/// The rule `FailureCatalogue` exists to enforce, applied here because this error cannot
/// yet be in the catalogue: it lives in this module rather than in `UttrflowCore`, and
/// `UttrflowCore` cannot reach upwards into a module that depends on it. The chain is
/// written anyway, so that moving the file is all the catalogue needs.
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

    /// The chain has to reach every case, which is the whole reason it is written as a
    /// `switch` the compiler checks rather than as an array somebody maintains.
    @Test("chains every case exactly once")
    func chainIsComplete() {
        #expect(ClipboardStoreError.everyCase == [.couldNotWrite])
    }
}
