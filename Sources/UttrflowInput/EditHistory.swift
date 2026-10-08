// Keeps the last few spoken edits undoable for a short window, in memory only.
private import Synchronization
public import UttrflowCore

/// The undoable edits in one field, newest last, never persisted and never sent. See `Docs/insertion.md`.
public final class EditHistory: Sendable {
    /// How many edits can be undone in a row.
    public static let depth = 8
    /// How long an edit stays undoable.
    public static let window: Duration = .seconds(120)

    private struct Entry: Sendable {
        let undo: EditUndo
        let madeAt: UInt64
    }

    private let entries = Mutex<[Entry]>([])
    private let clock: ElapsedClock

    public init() { clock = ElapsedClock() }

    init<C: Clock<Duration>>(clock: C) { self.clock = ElapsedClock(clock) }

    /// Records an edit just made; an edit in another field forgets every earlier one.
    public func note(_ undo: EditUndo) {
        let now = clock.nanoseconds
        entries.withLock { entries in
            if entries.last?.undo.written.field != undo.written.field { entries.removeAll() }
            entries.append(Entry(undo: undo, madeAt: now))
            if entries.count > Self.depth { entries.removeFirst(entries.count - Self.depth) }
        }
    }

    /// Takes the newest edit in `field` still inside the window; asking from any other field forgets them all.
    public func take(in field: FieldIdentity?) -> EditUndo? {
        let (seconds, attoseconds) = Self.window.components
        let window = UInt64(seconds) * 1_000_000_000 + UInt64(attoseconds / 1_000_000_000)
        let now = clock.nanoseconds
        return entries.withLock { entries in
            guard let field, entries.last?.undo.written.field == field else {
                entries.removeAll()
                return nil
            }
            entries.removeAll { now - $0.madeAt > window }
            return entries.popLast()?.undo
        }
    }

    /// Whether an edit in `field` is still inside the window, without taking it.
    func holdsEdit(in field: FieldIdentity?) -> Bool {
        let now = clock.nanoseconds
        let (seconds, attoseconds) = Self.window.components
        let window = UInt64(seconds) * 1_000_000_000 + UInt64(attoseconds / 1_000_000_000)
        return entries.withLock { entries in
            guard let field, entries.last?.undo.written.field == field else { return false }
            return entries.contains { now - $0.madeAt <= window }
        }
    }

    /// Forgets every edit.
    public func clear() {
        entries.withLock { $0.removeAll() }
    }
}

extension SelectionWriter {
    /// Undoes the newest edit in `history`, recording the inverse so a second undo re-applies it.
    func undo(
        from history: EditHistory, focused: FieldIdentity?, isSecure: Bool
    ) throws(TextInsertionError) {
        guard let undo = history.take(in: focused) else {
            throw .insertionRejected(description: "there is no recent edit to undo")
        }
        do {
            let redo = try edit(undo.target(focused: focused, isSecure: isSecure), to: undo.removed)
            history.note(redo)
        } catch {
            history.clear()
            throw error
        }
    }
}
