/// How the statement already before the caret is laid out, read from the text: clause lines or one line, and the indent it uses.
package struct SQLLayout: Sendable, Equatable {
    /// How the last statement places its clauses.
    package enum Convention: Sendable, Equatable {
        /// Fewer than two clauses to compare, or no text: nothing to follow.
        case unknown
        /// Two or more clauses share a line.
        case oneLine
        /// A clause after the first opens its own line.
        case clauseLines
    }

    /// What a word does to the layout of a statement it opens.
    package enum Opening: Sendable, Equatable {
        /// Begins a statement or counts as a clause but takes no line break of its own.
        case start
        /// A clause that begins a line when clauses have lines.
        case clause
        /// A join, which begins an indented line.
        case join
    }

    package let convention: Convention
    /// The indent of a clause line.
    package let clauseIndent: String
    /// The indent of a join line.
    package let joinIndent: String
    /// The caret's line before the caret; `nil` when the field holds no text.
    package let caretLine: String?
    /// A clause is open at the caret and no string or comment holds it.
    package let isMidStatement: Bool
    /// Parentheses the last statement opened and did not close.
    package let depth: Int

    /// Nothing known: the answer for a missing or empty field.
    package static let unknown = SQLLayout(
        convention: .unknown, clauseIndent: "", joinIndent: "  ", caretLine: nil, isMidStatement: false,
        depth: 0)

    /// The indent two spaces deep, for a script that shows none.
    private static let defaultUnit = "  "

    /// What the word `key` opens, given the words either side of it in the statement; `nil` opens nothing.
    package static func opening(_ key: String, next: String?, previous: String?) -> Opening? {
        switch key {
        case "select", "update", "delete": return .start
        case "from": return previous == "delete" ? nil : .clause
        case "where", "having", "limit", "set", "values", "group by", "order by": return .clause
        case "group", "order": return next == "by" ? .clause : nil
        case "join": return .join
        default: return nil
        }
    }

    /// Whether `key` may stand before `join` as part of a join's name.
    package static func isJoinModifier(_ key: String) -> Bool { SQLWords.joinModifiers.contains(key) }

    /// Reads the layout at the end of `precedingText`; `nil` text, as a field that will not say, is `unknown`.
    package static func at(_ precedingText: String?) -> SQLLayout {
        guard let precedingText else { return .unknown }
        let text = InsertionPoint.visibleText(precedingText)
        guard !text.isEmpty else { return .unknown }
        let masked = mask(text)
        let statement = lastStatement(of: masked)
        let reading = Reading(statement: statement)
        let unit = indentUnit(of: text)
        let clauseIndent = reading.clauseIndent
        return SQLLayout(
            convention: reading.convention, clauseIndent: clauseIndent,
            joinIndent: reading.joinIndent ?? clauseIndent + unit,
            caretLine: String(text.split(separator: "\n", omittingEmptySubsequences: false).last ?? ""),
            isMidStatement: SQLPosition.at(precedingText).isMidStatement, depth: reading.depth)
    }

    /// The indent a clause line takes; a join line takes the join indent.
    package func indent(for opening: Opening) -> String {
        opening == .join ? joinIndent : clauseIndent
    }

    /// The text with every string, quoted name and comment turned to `#`, line breaks and length kept.
    private static func mask(_ text: String) -> [Character] {
        let characters = Array(text)
        var masked = characters
        var index = 0
        while index < characters.count {
            let character = characters[index]
            let next = index + 1 < characters.count ? characters[index + 1] : nil
            var end = index + 1
            if character == "-", next == "-" {
                while end < characters.count, !characters[end].isNewline { end += 1 }
            } else if character == "/", next == "*" {
                end = index + 2
                while end < characters.count, !(characters[end - 1] == "*" && characters[end] == "/") {
                    end += 1
                }
                end = min(end + 1, characters.count)
            } else if character == "'" || character == "\"" || character == "`" {
                while end < characters.count, characters[end] != character { end += 1 }
                end = min(end + 1, characters.count)
            } else {
                index += 1
                continue
            }
            for position in index..<end where !characters[position].isNewline { masked[position] = "#" }
            index = end
        }
        return masked
    }

    /// The characters after the last `;` that holds anything, or the whole text when only the last statement is there.
    private static func lastStatement(of masked: [Character]) -> [Character] {
        var statements = masked.split(separator: ";", omittingEmptySubsequences: false)
        while statements.count > 1, statements.last?.allSatisfy({ $0.isWhitespace || $0 == "#" }) == true {
            statements.removeLast()
        }
        return Array(statements.last ?? [])
    }

    /// The smallest run of leading spaces in the text, or a tab when a line opens with one.
    private static func indentUnit(of text: String) -> String {
        let leading = text.split(separator: "\n", omittingEmptySubsequences: false)
            .map { $0.prefix(while: { $0 == " " || $0 == "\t" }) }
        if leading.contains(where: { $0.first == "\t" }) { return "\t" }
        let widths = leading.map(\.count).filter { $0 > 0 }
        return widths.min().map { String(repeating: " ", count: $0) } ?? defaultUnit
    }

    private init(
        convention: Convention, clauseIndent: String, joinIndent: String, caretLine: String?,
        isMidStatement: Bool, depth: Int
    ) {
        self.convention = convention
        self.clauseIndent = clauseIndent
        self.joinIndent = joinIndent
        self.caretLine = caretLine
        self.isMidStatement = isMidStatement
        self.depth = depth
    }

    /// The clauses one statement opens at its top level and what the lines around them look like.
    private struct Reading {
        /// One word of the statement and where it stands.
        struct Token {
            let key: String
            let line: Int
            let isFirstOnLine: Bool
        }

        /// A clause opening: its place in the tokens, and whether a join opens it.
        struct Clause {
            let token: Token
            let isJoin: Bool
        }

        var clauses: [Clause] = []
        var indents: [Int: String] = [:]
        var depth = 0

        init(statement: [Character]) {
            let lines = String(statement).split(separator: "\n", omittingEmptySubsequences: false)
            for (line, text) in lines.enumerated() {
                indents[line] = String(text.prefix(while: { $0 == " " || $0 == "\t" }))
            }
            read(lines.map(String.init))
        }

        private mutating func read(_ lines: [String]) {
            var tokens: [Token] = []
            var depths: [Int] = []
            for (line, text) in lines.enumerated() {
                var first = true
                var word = ""
                func flush() {
                    guard !word.isEmpty else { return }
                    tokens.append(Token(key: word.lowercased(), line: line, isFirstOnLine: first))
                    depths.append(depth)
                    first = false
                    word = ""
                }
                for character in text {
                    if character.isLetter || character.isNumber || character == "_" {
                        word.append(character)
                        continue
                    }
                    flush()
                    if character == "(" { depth += 1 }
                    if character == ")" { depth = max(0, depth - 1) }
                    if !character.isWhitespace { first = false }
                }
                flush()
            }
            collect(tokens, depths)
        }

        private mutating func collect(_ tokens: [Token], _ depths: [Int]) {
            for (index, token) in tokens.enumerated() where depths[index] == 0 {
                let next = index + 1 < tokens.count ? tokens[index + 1].key : nil
                let previous = index > 0 ? tokens[index - 1].key : nil
                guard let opening = SQLLayout.opening(token.key, next: next, previous: previous) else {
                    continue
                }
                if opening == .join {
                    var start = index
                    while start > 0, SQLLayout.isJoinModifier(tokens[start - 1].key) { start -= 1 }
                    clauses.append(Clause(token: tokens[start], isJoin: true))
                } else {
                    clauses.append(Clause(token: token, isJoin: false))
                }
            }
        }

        var convention: Convention {
            guard clauses.count >= 2 else { return .unknown }
            return clauses.dropFirst().contains { $0.token.isFirstOnLine } ? .clauseLines : .oneLine
        }

        /// The indent of the lines the non-join clauses open, the first of them when none opens a line after the first.
        var clauseIndent: String {
            let opened = clauses.dropFirst().filter { !$0.isJoin && $0.token.isFirstOnLine }
            guard let clause = opened.first ?? clauses.first(where: { !$0.isJoin }) else { return "" }
            return indents[clause.token.line] ?? ""
        }

        /// The indent of a line a join opens, if one does.
        var joinIndent: String? {
            clauses.first(where: { $0.isJoin && $0.token.isFirstOnLine }).flatMap { indents[$0.token.line] }
        }
    }
}
