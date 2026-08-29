public import UttrflowCore

/// A ``TextInsertionEngine`` that records what it was asked to insert.
public actor FakeTextInsertionEngine: TextInsertionEngine {
    public let method: TextInsertionMethod
    public let insertedText = CallLog<String>()

    private var canInsertResult: Bool
    private var insertOutcome: ScriptedOutcome<Void, TextInsertionError>

    public init(
        method: TextInsertionMethod = .accessibility,
        canInsert: Bool = true,
        insertOutcome: ScriptedOutcome<Void, TextInsertionError> = .ok
    ) {
        self.method = method
        self.canInsertResult = canInsert
        self.insertOutcome = insertOutcome
    }

    public func canInsert() async -> Bool { canInsertResult }

    public func insert(_ text: String) async throws(TextInsertionError) {
        await insertedText.append(text)
        try insertOutcome.resolve()
    }

    // MARK: Scripting

    public func setCanInsert(_ value: Bool) {
        canInsertResult = value
    }

    public func setInsertOutcome(_ outcome: ScriptedOutcome<Void, TextInsertionError>) {
        insertOutcome = outcome
    }
}
