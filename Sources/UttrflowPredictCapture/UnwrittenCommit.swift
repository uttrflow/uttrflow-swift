// A finished value on its way to the corpus, and what kind of line its ending made it.
import UttrflowPredict
import UttrflowPredictStore

import struct Foundation.Date

/// A finished value the corpus has not fully taken yet, and how far its write got.
struct UnwrittenCommit: Sendable {
    /// The value the field ended with.
    let text: String
    /// Where it was finished.
    let surface: Surface
    /// The draft it retires, until that supersede has landed.
    var superseded: String?
    /// The line it followed when it was finished.
    let previous: String?
    /// When it was finished.
    let moment: Date
    /// Whether the ending finished the line or only an idle left it standing.
    let origin: LineOrigin
    /// Which held entry this is, given when it is held and kept through every retry.
    var heldID: UInt64 = 0
}

/// A failed finished-value write, carrying what is left of it to retry.
struct CommitWriteFailure: Error {
    /// The value as far as its write got.
    let remaining: UnwrittenCommit
    /// What the sink threw.
    let underlying: any Error
}

extension CommitReason {
    /// Return and leaving the field finish a line; an idle or the application leaving only leave a draft.
    var origin: LineOrigin {
        switch self {
        case .returnPressed, .focusLeft: .finished
        case .wentIdle, .applicationDeactivated: .typed
        }
    }
}
