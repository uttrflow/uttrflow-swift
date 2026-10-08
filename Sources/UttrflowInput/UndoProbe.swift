/// What the focused field holds and where its selection sits, in UTF-16 units.
public struct UndoFieldReading: Sendable, Equatable {
    /// Everything the field holds.
    public let value: String
    /// Where the selection starts.
    public let selectionLocation: Int
    /// How much is selected; zero is a bare caret.
    public let selectionLength: Int

    public init(value: String, selectionLocation: Int, selectionLength: Int) {
        self.value = value
        self.selectionLocation = selectionLocation
        self.selectionLength = selectionLength
    }
}

/// What one ⌘Z after an insertion did, the values of the `Undo` column in `Docs/compatibility.md`.
public enum UndoSteps: String, Sendable, Equatable, CaseIterable {
    /// The field is back to what it held before the insertion.
    case oneStep = "one step"
    /// Part of the insertion is gone and the text around it is untouched.
    case several
    /// The field still holds what the insertion left.
    case undoesNothing = "undoes nothing"
    /// Text the field held before the insertion changed too.
    case undoesMore = "undoes more than the dictation"
    /// The field would not report its value at one of the three readings.
    case unreadable
}

/// One recorded run: how far ⌘Z went, and whether a replaced selection came back.
public struct UndoReport: Sendable, Equatable {
    /// How far the one ⌘Z went.
    public let steps: UndoSteps
    /// Whether the selection matches the first reading, nil when nothing was selected or the field is not restored.
    public let selectionRestored: Bool?

    public init(steps: UndoSteps, selectionRestored: Bool?) {
        self.steps = steps
        self.selectionRestored = selectionRestored
    }
}

/// Inserts, presses ⌘Z once and reads the field back, so an `Undo` cell is a measurement. See `Docs/compatibility.md`.
public enum UndoProbe {
    /// Classifies the field read before the insertion, after it and after one ⌘Z, comparing contents exactly.
    public static func classify(
        before: UndoFieldReading?, afterInsert: UndoFieldReading?, afterUndo: UndoFieldReading?
    ) -> UndoReport {
        guard let before, let afterInsert, let afterUndo else {
            return UndoReport(steps: .unreadable, selectionRestored: nil)
        }
        if afterUndo.value == before.value {
            let restored =
                before.selectionLength == 0
                ? nil
                : afterUndo.selectionLocation == before.selectionLocation
                    && afterUndo.selectionLength == before.selectionLength
            return UndoReport(steps: .oneStep, selectionRestored: restored)
        }
        if afterUndo.value == afterInsert.value {
            return UndoReport(steps: .undoesNothing, selectionRestored: nil)
        }
        let steps: UndoSteps =
            keepsSurroundings(
                before: before.value, afterInsert: afterInsert.value, afterUndo: afterUndo.value)
            ? .several : .undoesMore
        return UndoReport(steps: steps, selectionRestored: nil)
    }

    /// Reads, inserts, settles, reads, undoes, settles and reads, in that order, then classifies.
    public static func run(
        read: () async -> UndoFieldReading?,
        insert: () async throws -> Void,
        undo: () throws -> Void,
        settle: () async throws -> Void
    ) async throws -> UndoReport {
        let before = await read()
        try await insert()
        try await settle()
        let afterInsert = await read()
        try undo()
        try await settle()
        let afterUndo = await read()
        return classify(before: before, afterInsert: afterInsert, afterUndo: afterUndo)
    }

    /// Whether the text the insertion left alone on either side is still there, in UTF-16 units.
    private static func keepsSurroundings(before: String, afterInsert: String, afterUndo: String) -> Bool {
        let old = Array(before.utf16)
        let new = Array(afterInsert.utf16)
        let undone = Array(afterUndo.utf16)
        let limit = min(old.count, new.count)
        var head = 0
        while head < limit, old[head] == new[head] { head += 1 }
        var tail = 0
        while tail < limit - head, old[old.count - 1 - tail] == new[new.count - 1 - tail] { tail += 1 }
        guard undone.count >= head + tail else { return false }
        return undone.prefix(head).elementsEqual(old.prefix(head))
            && undone.suffix(tail).elementsEqual(old.suffix(tail))
    }
}
