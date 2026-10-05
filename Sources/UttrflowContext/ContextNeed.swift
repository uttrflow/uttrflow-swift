/// The slice of a field's text one consumer needs, so the single reader fetches the union and no more.
public struct ContextNeed: Equatable, Sendable {
    /// The parts of the context a consumer reads.
    public struct Parts: OptionSet, Equatable, Sendable {
        public let rawValue: Int
        public init(rawValue: Int) { self.rawValue = rawValue }

        public static let caretEdges = Parts(rawValue: 1 << 0)
        public static let lineBefore = Parts(rawValue: 1 << 1)
        public static let sentenceBefore = Parts(rawValue: 1 << 2)
        public static let textAfter = Parts(rawValue: 1 << 3)
        public static let selection = Parts(rawValue: 1 << 4)
        public static let windowTitle = Parts(rawValue: 1 << 5)
        public static let document = Parts(rawValue: 1 << 6)
        public static let surroundingsNames = Parts(rawValue: 1 << 7)
    }

    /// What the consumer reads.
    public let parts: Parts
    /// UTF-16 units read before the caret.
    public let unitsBefore: Int
    /// UTF-16 units read after the selection's end.
    public let unitsAfter: Int
    /// UTF-16 units of the selection read from its start.
    public let selectionUnits: Int

    public init(parts: Parts, unitsBefore: Int, unitsAfter: Int, selectionUnits: Int) {
        self.parts = parts
        self.unitsBefore = max(0, unitsBefore)
        self.unitsAfter = max(0, unitsAfter)
        self.selectionUnits = max(0, selectionUnits)
    }

    /// What two consumers read together: every part either names, each cap the wider of the two.
    public func union(_ other: Self) -> Self {
        Self(
            parts: parts.union(other.parts), unitsBefore: max(unitsBefore, other.unitsBefore),
            unitsAfter: max(unitsAfter, other.unitsAfter),
            selectionUnits: max(selectionUnits, other.selectionUnits))
    }

    /// One character each side of the selection, two units so a surrogate pair fits, and a short selection.
    public static let caretEdges = Self(
        parts: [.caretEdges, .selection], unitsBefore: 2, unitsAfter: 2, selectionUnits: 12)

    /// What a turn reads today: the caret's line and the context before it, its line's end, and the selection.
    public static let turn = Self(
        parts: [.caretEdges, .lineBefore, .sentenceBefore, .textAfter, .selection],
        unitsBefore: ValueWindow.unitsBefore, unitsAfter: ValueWindow.unitsAfter,
        selectionUnits: ValueWindow.selectionLimit)
}
