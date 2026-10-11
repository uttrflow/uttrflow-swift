// A clipboard held in memory, so no test reads or depends on what the person running it has copied.

import Foundation
import Synchronization
import UttrflowClipboard
import UttrflowCore

/// A clipboard that starts empty and changes only when a test copies to it.
final class InMemoryClipboardSource: ClipboardSource {
    private struct State {
        var count = 0
        var text: String?
    }

    private let state = Mutex(State())

    /// Copies as another application would: the text changes and the count goes up.
    func copy(_ text: String?) {
        state.withLock {
            $0.count += 1
            $0.text = text
        }
    }

    func changeCount() -> Int { state.withLock(\.count) }
    func text() -> String? { state.withLock(\.text) }
    func html() -> String? { nil }
    func markers() -> PasteboardMarkers { [] }
    func image() -> (data: Data, width: Int, height: Int)? { nil }
    func frontmostApplicationName() -> String? { nil }
}
