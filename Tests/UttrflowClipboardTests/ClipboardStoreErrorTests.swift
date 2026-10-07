// Tests for the clipboard store's error.

import Foundation
import UttrflowCore
import Testing

@testable import UttrflowClipboard

/// The `FailureCatalogue` rule applied here, because this error lives in a module Core cannot see.
@Suite("What the clipboard says when a change is refused")
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
        #expect(
            ClipboardStoreError.everyCase == [
                .couldNotWrite, .diskFull, .aliasAlreadyInUse, .unsupportedFormat,
                .keptPicturesFull,
            ])
    }

    @Test("recognizes ENOSPC and keeps other write failures generic")
    func mapsDiskFull() {
        let diskFull = NSError(domain: NSPOSIXErrorDomain, code: Int(ENOSPC))
        let denied = NSError(domain: NSPOSIXErrorDomain, code: Int(EACCES))

        #expect(ClipboardStore.writeFailure(diskFull) == .diskFull)
        #expect(ClipboardStore.writeFailure(denied) == .couldNotWrite)
        #expect(
            ClipboardStoreError.diskFull.userMessage
                .contains("Free some space and try again"))
    }
}
