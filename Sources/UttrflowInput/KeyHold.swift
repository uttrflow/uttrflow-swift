internal import CoreGraphics
internal import Dispatch
internal import Synchronization

/// Keys pressed between a swallowed keystroke and its handling, kept back and replayed in order afterwards.
final class KeyHold: Sendable {
    /// How long a hold may last before keys pass through again, so a stalled handler never keeps the keyboard.
    static let limitNanoseconds: UInt64 = 1_000_000_000

    /// When the hold began, in uptime nanoseconds, or zero when nothing is held back.
    private let since = Atomic<UInt64>(0)
    /// The key-downs kept back, oldest first.
    private let kept = Mutex<[Kept]>([])

    /// A copied event, owned by the hold alone from the moment it is kept.
    private struct Kept: @unchecked Sendable {
        let event: CGEvent
    }

    /// Starts holding keys back, from the moment a keystroke is swallowed on the tap's thread.
    func begin(now: UInt64 = DispatchTime.now().uptimeNanoseconds) {
        since.store(max(now, 1), ordering: .releasing)
    }

    /// Keeps a copy of a key-down back and returns true while a hold is in force; false lets it through.
    func keep(_ event: CGEvent, now: UInt64 = DispatchTime.now().uptimeNanoseconds) -> Bool {
        let start = since.load(ordering: .acquiring)
        guard start != 0 else { return false }
        guard now &- start < Self.limitNanoseconds else {
            since.store(0, ordering: .releasing)
            return false
        }
        guard let copy = event.copy() else { return false }
        kept.withLock { $0.append(Kept(event: copy)) }
        return true
    }

    /// Ends the hold and hands every kept key-down to `post`, oldest first.
    func release(post: (CGEvent) -> Void = { $0.post(tap: .cghidEventTap) }) {
        since.store(0, ordering: .releasing)
        let events = kept.withLock { kept in
            defer { kept.removeAll() }
            return kept
        }
        for kept in events { post(kept.event) }
    }
}
