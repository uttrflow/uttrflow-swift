/// Recognises SQL statements that remove database objects or rows.
enum SQLDestructiveCommand {
    /// Database objects whose removal is destructive.
    private static let droppableObjects: Set<String> = [
        "table", "database", "schema", "index", "keyspace", "view", "user", "role", "type", "function",
        "procedure",
    ]

    /// Whether an SQL command drops an object, deletes rows or truncates a table.
    static func matches(command: String, arguments: [String]) -> Bool {
        let sql = ([command] + arguments).joined(separator: " ")
        let sequence = ([command] + arguments).flatMap {
            $0.split(whereSeparator: { !$0.isLetter && !$0.isNumber && $0 != "_" }).map(String.init)
        }.map { $0.lowercased() }
        let words = Set(sequence)
        if words.contains("drop"), words.contains(where: droppableObject) { return true }
        if let delete = sequence.firstIndex(of: "delete"), sequence[delete...].contains("from") {
            return true
        }
        if matchesAlterTableMutation(sequence) { return true }
        let mysqlStyleHashComments = command == "mysql" || command == "mariadb"
        return words.contains("truncate")
            || hasUpdateWithoutWhere(in: sql, mysqlStyleHashComments: mysqlStyleHashComments)
    }

    /// Whether an UPDATE statement lacks its own WHERE clause, ignoring comments and quoted text.
    private static func hasUpdateWithoutWhere(in sql: String, mysqlStyleHashComments: Bool) -> Bool {
        var scanner = SQLUpdateScanner(sql: sql, mysqlStyleHashComments: mysqlStyleHashComments)
        return scanner.matches()
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

/// Reads UPDATE statements without mistaking quoted values or comments for SQL clauses.
private struct SQLUpdateScanner {
    private let bytes: [UInt8]
    private let mysqlStyleHashComments: Bool
    private var depth = 0
    private var updatesWithoutWhere: [Int] = []
    private var index = 0

    init(sql: String, mysqlStyleHashComments: Bool) {
        bytes = Array(sql.utf8)
        self.mysqlStyleHashComments = mysqlStyleHashComments
    }

    mutating func matches() -> Bool {
        while index < bytes.count {
            let byte = bytes[index]
            if skipQuotedValue(startingWith: byte) || skipComment(startingWith: byte) || skipDollarQuote() {
                continue
            }
            if byte == 59 {
                if !updatesWithoutWhere.isEmpty { return true }
                resetStatement()
                continue
            }
            if byte == 41, updatesWithoutWhere.contains(depth) { return true }
            if consumeParenthesis(byte) || consumeWord() { continue }
            index += 1
        }
        return !updatesWithoutWhere.isEmpty
    }

    private mutating func skipQuotedValue(startingWith byte: UInt8) -> Bool {
        guard byte == 39 || byte == 34 || byte == 96 || byte == 91 else { return false }
        let closing: UInt8 = byte == 91 ? 93 : byte
        index += 1
        while index < bytes.count {
            if bytes[index] == 92, index + 1 < bytes.count {
                index += 2
            } else if bytes[index] == closing, advancePastQuoteOrEscape(closing: closing) {
                break
            } else {
                index += 1
            }
        }
        return true
    }

    private mutating func advancePastQuoteOrEscape(closing: UInt8) -> Bool {
        if index + 1 < bytes.count, bytes[index + 1] == closing { index += 2; return false }
        index += 1
        return true
    }

    private mutating func skipComment(startingWith byte: UInt8) -> Bool {
        if byte == 45, hasNext(45) { skipLineComment(from: 2); return true }
        if byte == 35, mysqlStyleHashComments { skipLineComment(from: 1); return true }
        guard byte == 47, hasNext(42) else { return false }
        skipBlockComment()
        return true
    }

    private mutating func skipLineComment(from offset: Int) {
        index += offset
        while index < bytes.count, bytes[index] != 10, bytes[index] != 13 { index += 1 }
    }

    private mutating func skipBlockComment() {
        index += 2
        var commentDepth = 1
        while index < bytes.count, commentDepth > 0 {
            if hasNext(42), bytes[index] == 47 {
                commentDepth += 1; index += 2
            } else if hasNext(47), bytes[index] == 42 {
                commentDepth -= 1; index += 2
            } else {
                index += 1
            }
        }
    }

    private mutating func skipDollarQuote() -> Bool {
        guard current == 36, index == 0 || !Self.isIdentifierByte(bytes[index - 1]) else { return false }
        let delimiterEnd = dollarDelimiterEnd()
        guard delimiterEnd < bytes.count, bytes[delimiterEnd] == 36 else { return false }
        let delimiter = Array(bytes[index...delimiterEnd])
        index = findClosing(delimiter, after: delimiterEnd + 1)
        return true
    }

    private func dollarDelimiterEnd() -> Int {
        var end = index + 1
        guard end < bytes.count else { return bytes.count }
        if bytes[end] == 36 { return end }
        guard Self.isDollarTagStart(bytes[end]) else { return bytes.count }
        end += 1
        while end < bytes.count, Self.isIdentifierByte(bytes[end]), bytes[end] != 36 { end += 1 }
        return end
    }

    private func findClosing(_ delimiter: [UInt8], after start: Int) -> Int {
        var closing = start
        while closing + delimiter.count <= bytes.count {
            if Array(bytes[closing..<(closing + delimiter.count)]) == delimiter {
                return closing + delimiter.count
            }
            closing += 1
        }
        return bytes.count
    }

    private mutating func resetStatement() {
        updatesWithoutWhere.removeAll(keepingCapacity: true)
        depth = 0
        index += 1
    }

    private mutating func consumeParenthesis(_ byte: UInt8) -> Bool {
        if byte == 40 { depth += 1; index += 1; return true }
        guard byte == 41 else { return false }
        updatesWithoutWhere.removeAll { $0 == depth }
        depth = max(0, depth - 1)
        index += 1
        return true
    }

    private mutating func consumeWord() -> Bool {
        guard Self.isIdentifierByte(current) else { return false }
        let start = index
        while index < bytes.count, Self.isIdentifierByte(bytes[index]) { index += 1 }
        let word = String(decoding: bytes[start..<index], as: UTF8.self).lowercased()
        if word == "update" { updatesWithoutWhere.append(depth) }
        if word == "where", let update = updatesWithoutWhere.lastIndex(of: depth) {
            updatesWithoutWhere.remove(at: update)
        }
        return true
    }

    private var current: UInt8 { index < bytes.count ? bytes[index] : 0 }

    private func hasNext(_ byte: UInt8) -> Bool {
        index + 1 < bytes.count && bytes[index + 1] == byte
    }

    private static func isDollarTagStart(_ byte: UInt8) -> Bool {
        byte == 95 || (65...90).contains(byte) || (97...122).contains(byte)
    }

    private static func isIdentifierByte(_ byte: UInt8) -> Bool {
        (65...90).contains(byte) || (97...122).contains(byte)
            || (48...57).contains(byte) || byte == 95 || byte == 36
    }
}
