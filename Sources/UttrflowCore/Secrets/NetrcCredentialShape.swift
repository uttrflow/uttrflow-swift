// Recognises passwords in a netrc machine or default block.

/// Reads one netrc line in the context of the preceding machine or default block.
enum NetrcCredentialShape {
    /// Context carried between directives in one netrc machine or default block.
    struct State {
        var inEntry = false
        var inMacro = false
    }

    /// Collects raw netrc lines while the command scanner reads the same characters.
    struct Scanner {
        private var state = State()
        private var line = ""

        /// Adds a character and checks a netrc line at its newline.
        mutating func consume(_ character: Character, read: inout Int) -> Bool {
            guard character.isNewline else {
                line.append(character)
                return false
            }
            let matched = NetrcCredentialShape.matches(line, state: &state, read: &read)
            line = ""
            return matched
        }

        /// Checks the final line when the text has no trailing newline.
        mutating func finish(read: inout Int) -> Bool {
            NetrcCredentialShape.matches(line, state: &state, read: &read)
        }
    }

    /// Whether one netrc line has a password in the current machine or default block.
    private static func matches(_ line: String, state: inout State, read: inout Int) -> Bool {
        read += line.count
        if line.isEmpty {
            if state.inMacro { state.inMacro = false }
            state.inEntry = false
            return false
        }
        let fields = fields(in: line)
        guard !fields.isEmpty else {
            if state.inMacro { state.inMacro = false }
            state.inEntry = false
            return false
        }
        guard let first = fields.first, !first.hasPrefix("#"), !state.inMacro else { return false }
        guard var index = directiveStart(fields, state: &state) else { return false }
        while index < fields.count {
            read += 1
            let directive = fields[index].lowercased()
            if directive == "macdef" {
                guard index + 1 < fields.count else {
                    state.inEntry = false
                    return false
                }
                state.inMacro = true
                return false
            }
            guard isDirective(directive), index + 1 < fields.count else {
                state.inEntry = false
                return false
            }
            let value = fields[index + 1]
            if directive == "password", isCredential(value) { return true }
            index += 2
        }
        return false
    }

    /// Reads whitespace-delimited netrc fields without treating password punctuation as shell syntax.
    private static func fields(in line: String) -> [String] {
        var fields: [String] = []
        var field = ""
        var hasField = false
        var quote: Character?
        var escaped = false
        func endField() {
            if hasField { fields.append(field) }
            field = ""
            hasField = false
        }
        for character in line {
            if escaped {
                field.append(character)
                escaped = false
            } else if let open = quote {
                if character == open {
                    quote = nil
                } else {
                    field.append(character)
                }
            } else {
                switch character {
                case "\\": escaped = true
                case "\"", "'":
                    quote = character
                    hasField = true
                default:
                    if character.isWhitespace {
                        endField()
                    } else {
                        field.append(character)
                        hasField = true
                    }
                }
            }
        }
        endField()
        return fields
    }

    /// Selects the first directive after a block selector or on its own line.
    private static func directiveStart(_ fields: [String], state: inout State) -> Int? {
        switch fields[0].lowercased() {
        case "machine":
            guard fields.count > 1 else {
                state.inEntry = false
                return nil
            }
            state.inEntry = true
            return 2
        case "default":
            state.inEntry = true
            return 1
        default:
            guard state.inEntry, isDirective(fields[0]) else {
                state.inEntry = false
                return nil
            }
            return 0
        }
    }

    /// Whether a field is one of the supported directives.
    private static func isDirective(_ field: String) -> Bool {
        let directive = field.lowercased()
        return directive == "macdef" || CredentialWords.netrcValueDirectives.contains(directive)
    }

    /// Whether a nonempty value is literal text rather than a shell placeholder.
    private static func isCredential(_ value: String) -> Bool {
        guard !value.isEmpty else { return false }
        if value.hasPrefix("$"), value.count > 1 {
            let reference = value.dropFirst()
            if reference.first == "{", value.last == "}" { return false }
            if reference.first == "(", value.last == ")" { return false }
            if reference.allSatisfy({ $0.isLetter || $0.isNumber || $0 == "_" }) { return false }
        }
        if value.first == "{", value.last == "}" { return false }
        if value.first == "<", value.last == ">" { return false }
        return true
    }
}
