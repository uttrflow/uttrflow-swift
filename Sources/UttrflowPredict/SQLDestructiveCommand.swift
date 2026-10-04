/// Recognises SQL statements that remove database objects or rows.
enum SQLDestructiveCommand {
    /// Database objects whose removal is destructive.
    private static let droppableObjects: Set<String> = [
        "table", "database", "schema", "index", "keyspace", "view", "user", "role", "type", "function",
        "procedure",
    ]

    /// Whether an SQL command drops an object, deletes rows or truncates a table.
    static func matches(command: String, arguments: [String]) -> Bool {
        let sequence = ([command] + arguments).flatMap {
            $0.split(whereSeparator: { !$0.isLetter && !$0.isNumber && $0 != "_" }).map(String.init)
        }
        let words = Set(sequence)
        if words.contains("drop"), words.contains(where: droppableObject) { return true }
        if let delete = sequence.firstIndex(of: "delete"), sequence[delete...].contains("from") {
            return true
        }
        if matchesAlterTableMutation(sequence) { return true }
        return words.contains("truncate")
    }

    /// Whether an ALTER TABLE statement runs a row or schema deletion mutation.
    private static func matchesAlterTableMutation(_ sequence: [String]) -> Bool {
        guard let alter = sequence.firstIndex(of: "alter") else { return false }
        let table = sequence.index(after: alter)
        guard table < sequence.endIndex, sequence[table] == "table" else { return false }
        let mutationStart = sequence.index(after: table)
        return sequence[mutationStart...].contains { $0 == "delete" || $0 == "drop" }
    }

    /// Whether the object named after DROP is one the command irreversibly removes.
    private static func droppableObject(_ word: String) -> Bool {
        droppableObjects.contains(word)
    }
}
