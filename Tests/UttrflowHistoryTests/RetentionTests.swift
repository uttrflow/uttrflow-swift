import Foundation
import Testing

@testable import UttrflowCore
@testable import UttrflowHistory

@Suite("The window, and what the store can refuse")
struct RetentionTests {
    private let noon = Date(timeIntervalSince1970: 1_700_000_000)

    @Test("carries the window and the moment it is measured from")
    func carriesBoth() {
        let retention = Retention(days: 7, now: noon)
        #expect(retention.days == 7)
        #expect(retention.now == noon)
        #expect(retention == Retention(days: 7, now: noon))
        #expect(retention != Retention(days: 30, now: noon))
    }

    /// A failure the user cannot act on must still say something they can understand,
    /// and must not overstate what it cost them.
    @Test("a refused write explains itself without offering a button that would not help")
    func failureIsPresentable() {
        let failure = HistoryStoreError.couldNotWrite
        #expect(failure.userMessage == "Your dictation history could not be updated on this Mac.")
        #expect(failure.recovery == nil)
        #expect(failure.severity == .degraded)
    }
}
