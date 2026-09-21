// Whether a dictation is under way, so discretionary model work stays off the GPU it needs.

private import Synchronization

/// Set while a dictation records, recognises, tidies or inserts; suggestion passes ask it before they run.
public final class DictationInProgress: Sendable {
    /// The one the app sets and every suggestion pass reads.
    public static let shared = DictationInProgress()

    private let busy = Mutex(false)

    public init() {}

    /// Whether a dictation is under way right now.
    public var isDictating: Bool { busy.withLock { $0 } }

    /// Records a change of dictation state.
    public func set(dictating: Bool) {
        busy.withLock { $0 = dictating }
    }
}
