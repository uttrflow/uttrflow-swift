/// Where the caret stands in a SQL statement, read from the text before it: grammar position, not prose position.
package struct SQLPosition: Sendable, Equatable {
    /// The clause the caret continues; each case is opened by the keyword or keywords it names.
    package enum Clause: String, Sendable, Equatable {
        case select, from, join, on, `where`, groupBy, having, orderBy, limit
        case insertInto, values, update, set, delete
    }

    /// How the statement writes the keywords it already holds.
    package enum KeywordCase: String, Sendable, Equatable {
        case upper, lower, mixed, unknown
    }

    /// The clause the caret is in, or `nil` between statements or when nothing is known.
    package let openClause: Clause?
    package let keywordCase: KeywordCase
    /// Table names in the order the statement names them, as written (a schema prefix is kept).
    package let tables: [String]
    /// Alias names in the order the statement binds them.
    package let aliases: [String]
    /// The caret is inside an unterminated string literal.
    package let inString: Bool
    /// The caret is inside a line comment or an unterminated block comment.
    package let inComment: Bool
    /// The window began inside a statement, so nothing above is known.
    package let isCut: Bool

    /// Nothing known: the answer for a missing or cut window.
    package static let unknown = SQLPosition(isCut: true)

    private init(
        openClause: Clause? = nil, keywordCase: KeywordCase = .unknown, tables: [String] = [],
        aliases: [String] = [], inString: Bool = false, inComment: Bool = false, isCut: Bool = false
    ) {
        self.openClause = openClause
        self.keywordCase = keywordCase
        self.tables = tables
        self.aliases = aliases
        self.inString = inString
        self.inComment = inComment
        self.isCut = isCut
    }

    /// Whether the caret continues a statement as code: a clause is open and no string or comment holds the caret.
    package var isMidStatement: Bool { openClause != nil && !inString && !inComment }

    /// Reads the position at the end of `precedingText`; `nil` text, as a field that will not say, is `unknown`.
    package static func at(_ precedingText: String?) -> SQLPosition {
        guard let precedingText else { return .unknown }
        let text = InsertionPoint.visibleText(precedingText)
        let window = Array(text)
        let isWindowFull = text.utf16.count >= InsertionPoint.precedingLimit
        var reader = Reader(characters: window, mayBeCut: isWindowFull)
        return reader.read()
    }

    // MARK: Reading

    private struct Level {
        var clause: Clause?
        var expectsTable = false
        var expectsAlias = false
        var afterAs = false
        var pendingGroupOrder: String?
        var pendingInsert = false
        var continuesName = false
        var lastBoundWasTable = false
    }

    private struct Reader {
        let characters: [Character]
        let mayBeCut: Bool
        var levels = [Level()]
        var tables: [String] = []
        var aliases: [String] = []
        var upper = 0
        var lower = 0
        var sawStatementStart = false
        var sawTerminator = false

        init(characters: [Character], mayBeCut: Bool) {
            self.characters = characters
            self.mayBeCut = mayBeCut
        }

        mutating func read() -> SQLPosition {
            var index = 0
            var inString = false
            var inComment = false
            while index < characters.count {
                let character = characters[index]
                let next = index + 1 < characters.count ? characters[index + 1] : nil
                inString = false
                inComment = false
                if character == "-", next == "-" {
                    index += 2
                    while index < characters.count, !characters[index].isNewline { index += 1 }
                    if index >= characters.count { inComment = true }
                    continue
                }
                if character == "/", next == "*" {
                    index += 2
                    var closed = false
                    while index < characters.count {
                        if characters[index] == "*", index + 1 < characters.count,
                            characters[index + 1] == "/"
                        {
                            index += 2
                            closed = true
                            break
                        }
                        index += 1
                    }
                    if !closed { inComment = true }
                    continue
                }
                if character == "'" || character == "\"" || character == "`" {
                    let end = skipQuoted(from: index, quote: character)
                    if end.closed {
                        if character != "'" {
                            identifier(String(characters[index..<end.index]))
                        } else {
                            value()
                        }
                        index = end.index
                        continue
                    }
                    inString = true
                    index = characters.count
                    break
                }
                if character.isLetter || character == "_" {
                    var end = index
                    while end < characters.count,
                        characters[end].isLetter || characters[end].isNumber || characters[end] == "_"
                            || characters[end] == "$"
                    {
                        end += 1
                    }
                    word(String(characters[index..<end]))
                    index = end
                    continue
                }
                switch character {
                case ";": terminate()
                case "(": open()
                case ")": close()
                case ",": comma()
                case ".": dot()
                default:
                    if !character.isWhitespace { other() }
                }
                index += 1
            }
            return result(inString: inString, inComment: inComment)
        }

        private func skipQuoted(from start: Int, quote: Character) -> (index: Int, closed: Bool) {
            var index = start + 1
            while index < characters.count {
                if characters[index] == quote {
                    // A doubled quote is an escaped quote, not the end.
                    if index + 1 < characters.count, characters[index + 1] == quote {
                        index += 2
                        continue
                    }
                    return (index + 1, true)
                }
                index += 1
            }
            return (index, false)
        }

        private var depth: Int { levels.count - 1 }

        private mutating func terminate() {
            levels = [Level()]
            tables = []
            aliases = []
            upper = 0
            lower = 0
            sawTerminator = true
            sawStatementStart = false
        }

        private mutating func open() {
            // The outer level keeps its clause; a subquery starts its own at its `select`.
            levels[depth].expectsTable = false
            levels[depth].expectsAlias = false
            levels.append(Level())
        }

        private mutating func close() {
            guard levels.count > 1 else { return }
            levels.removeLast()
            // A parenthesised source in a from or join takes an alias after it.
            let clause = levels[depth].clause
            levels[depth].expectsAlias = clause == .from || clause == .join
            levels[depth].afterAs = false
        }

        private mutating func comma() {
            levels[depth].expectsAlias = false
            levels[depth].afterAs = false
            if levels[depth].clause == .from { levels[depth].expectsTable = true }
        }

        /// A dot after a table name makes it a schema prefix, so the next name continues the same table.
        private mutating func dot() {
            if levels[depth].expectsAlias, !tables.isEmpty, levels[depth].lastBoundWasTable {
                levels[depth].continuesName = true
            }
        }

        private mutating func other() {
            levels[depth].expectsTable = false
            levels[depth].expectsAlias = false
            levels[depth].afterAs = false
        }

        private mutating func value() { other() }

        private mutating func identifier(_ name: String) {
            bind(String(name.filter { $0 != "\"" && $0 != "`" }))
        }

        private mutating func bind(_ name: String) {
            if levels[depth].continuesName {
                tables[tables.count - 1] += "." + name
                levels[depth].continuesName = false
            } else if levels[depth].expectsTable {
                tables.append(name)
                levels[depth].lastBoundWasTable = true
                levels[depth].expectsTable = false
                levels[depth].expectsAlias = true
            } else if levels[depth].expectsAlias || levels[depth].afterAs {
                aliases.append(name)
                levels[depth].lastBoundWasTable = false
                levels[depth].expectsAlias = false
                levels[depth].afterAs = false
            }
        }

        private static let aliasStoppers: Set<String> = [
            "where", "on", "join", "inner", "left", "right", "full", "outer", "cross", "natural", "group",
            "order", "having", "limit", "union", "set", "using", "values", "select", "from", "as", "and",
            "or", "not", "into", "offset", "returning", "intersect", "except", "lateral",
        ]

        private mutating func word(_ text: String) {
            let key = text.lowercased()
            // A keyword counts toward the statement's case when it has a cased spelling at all.
            if Self.keywords.contains(key), text.count > 1 {
                if text == text.uppercased() { upper += 1 } else if text == key { lower += 1 }
            }
            if let clause = clause(for: key) {
                sawStatementStart = true
                let expectsTable = [.from, .join, .insertInto, .update].contains(clause)
                levels[depth].clause = clause
                levels[depth].expectsTable = expectsTable
                levels[depth].expectsAlias = false
                levels[depth].afterAs = false
                return
            }
            if key == "as", levels[depth].expectsAlias {
                levels[depth].afterAs = true
                levels[depth].expectsAlias = false
                return
            }
            if Self.aliasStoppers.contains(key) {
                other()
                return
            }
            bind(text)
        }

        /// Opens a clause where this word completes one; `group`, `order`, `insert` and `delete` wait for their second word.
        private mutating func clause(for key: String) -> Clause? {
            switch key {
            case "select": return .select
            case "from": return .from
            case "join": return .join
            case "on": return .on
            case "where": return .where
            case "having": return .having
            case "limit": return .limit
            case "values": return .values
            case "update": return .update
            case "set": return .set
            case "delete": return .delete
            case "into": return levels[depth].pendingInsert ? .insertInto : nil
            case "by":
                switch levels[depth].pendingGroupOrder {
                case "group": return .groupBy
                case "order": return .orderBy
                default: return nil
                }
            default:
                break
            }
            levels[depth].pendingGroupOrder = (key == "group" || key == "order") ? key : nil
            levels[depth].pendingInsert = key == "insert"
            return nil
        }

        private func result(inString: Bool, inComment: Bool) -> SQLPosition {
            // A full window with no statement end in it may have begun inside a statement.
            if mayBeCut, !sawTerminator { return .unknown }
            let keywordCase: KeywordCase
            switch (upper, lower) {
            case (0, 0): keywordCase = .unknown
            case (_, 0): keywordCase = .upper
            case (0, _): keywordCase = .lower
            default: keywordCase = .mixed
            }
            return SQLPosition(
                openClause: sawStatementStart ? levels[depth].clause : nil, keywordCase: keywordCase,
                tables: tables, aliases: aliases, inString: inString, inComment: inComment)
        }

        private static let keywords: Set<String> = [
            "select", "from", "where", "join", "inner", "left", "right", "outer", "on", "group", "by",
            "order", "having", "limit", "insert", "into", "values", "update", "set", "delete", "and",
            "or", "not", "as", "union", "distinct", "in", "like", "between", "is", "null",
        ]
    }
}
