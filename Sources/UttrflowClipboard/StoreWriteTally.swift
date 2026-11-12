// A count of the files a clipboard store writes, for tests that bound writing without a clock.

package import Foundation
private import Synchronization

/// Counts the files a store writes while this is bound to `ClipboardStore.writes`.
package final class StoreWriteTally: Sendable {
    private let files = Mutex(0)
    private let bytes = Mutex<[Data]>([])

    package init() {}

    /// Answers how many files have been written or removed so far.
    package var count: Int { files.withLock { $0 } }

    /// Every encoded list written so far, in order; a removal adds nothing here.
    package var written: [Data] { bytes.withLock { $0 } }

    func record(_ data: Data? = nil) {
        files.withLock { $0 += 1 }
        if let data { bytes.withLock { $0.append(data) } }
    }
}
