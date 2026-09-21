/// One word of a command line with the shell's quoting undone and `~` and `$HOME` expanded.
struct ShellWord: Equatable, Sendable {
    /// The word as the program receives it.
    let text: String
    /// Whether the shell would still rewrite it, as a glob, a variable or another user's home do, so no stat can settle it.
    let isUnresolved: Bool

    init(_ text: String, isUnresolved: Bool = false) {
        self.text = text
        self.isUnresolved = isUnresolved
    }
}

/// What ends a simple command, which decides whether a `cd` in it moves the commands after it.
enum ShellSeparator: Equatable, Sendable {
    /// The end of the line.
    case end
    /// `;` or a newline: the next command runs whatever happened.
    case sequence
    /// `&&`: the next command runs only after this one succeeded.
    case and
    /// `||`: the next command runs only after this one failed.
    case or
    /// `|`: the next command runs beside this one, in its own process.
    case pipe
    /// `&`: this command runs in the background.
    case background
}

/// One simple command: its words, the files it reads with `<`, and what ends it.
struct SimpleCommand: Equatable, Sendable {
    let words: [ShellWord]
    let inputs: [ShellWord]
    let separator: ShellSeparator
}

/// Splits a command line into simple commands the way a POSIX shell reads it, refusing whatever only running something could settle.
enum ShellWords {
    /// The line's simple commands, absent for a subshell, a substitution, a here-document or unbalanced quoting.
    static func commands(in line: String, home: String) -> [SimpleCommand]? {
        var reader = Reader(characters: Array(line), home: home)
        return reader.read()
    }

    /// The state of one pass over a line.
    private struct Reader {
        let characters: [Character]
        let home: String
        var index = 0
        var commands: [SimpleCommand] = []
        var words: [ShellWord] = []
        var inputs: [ShellWord] = []
        var text = ""
        var inWord = false
        var isQuoted = false
        var isUnresolved = false
        /// Whether the next word is a redirection's target, and whether that target is read.
        var redirection: Bool?

        init(characters: [Character], home: String) {
            self.characters = characters
            self.home = home
        }

        /// The character this many places ahead, absent past the end.
        func peek(_ offset: Int = 1) -> Character? {
            index + offset < characters.count ? characters[index + offset] : nil
        }

        mutating func read() -> [SimpleCommand]? {
            while index < characters.count {
                guard step() else { return nil }
            }
            guard endWord(), redirection == nil else { return nil }
            if !words.isEmpty || !inputs.isEmpty { end(.end) }
            return commands
        }

        /// Reads from the current character, false where the line cannot be settled without running it.
        mutating func step() -> Bool {
            let character = characters[index]
            switch character {
            case " ", "\t":
                index += 1
                return endWord()
            case "\n", ";":
                index += 1
                return close(.sequence)
            case "&":
                return ampersand()
            case "|":
                if peek() == "|" {
                    index += 2
                    return close(.or)
                }
                index += peek() == "&" ? 2 : 1
                return close(.pipe)
            case "<", ">":
                return redirect(character)
            case "(", ")", "`":
                return false
            case "#" where !inWord:
                index = characters.count
                return true
            case "'":
                return singleQuoted()
            case "\"":
                return doubleQuoted()
            case "\\":
                guard let next = peek() else { return false }
                inWord = true
                isQuoted = true
                if next != "\n" { text.append(next) }
                index += 2
                return true
            case "$":
                return variable()
            case "~" where !inWord:
                tilde()
                return true
            case "*", "?", "[", "]", "{", "}":
                inWord = true
                isUnresolved = true
                text.append(character)
                index += 1
                return true
            default:
                inWord = true
                text.append(character)
                index += 1
                return true
            }
        }

        /// `&&`, `&>` or a lone `&`.
        mutating func ampersand() -> Bool {
            if peek() == "&" {
                index += 2
                return close(.and)
            }
            if peek() == ">" {
                guard endWord() else { return false }
                index += peek(2) == ">" ? 3 : 2
                redirection = false
                return true
            }
            index += 1
            return close(.background)
        }

        /// A redirection: `<`, `>`, `>>`, `>|`, `<>` and a descriptor duplication, the target of `<` kept as a file the command reads.
        mutating func redirect(_ character: Character) -> Bool {
            // A here-document, a here-string and a process substitution are all text only the shell can produce.
            if peek() == "(" || (character == "<" && peek() == "<") { return false }
            // A descriptor number written against the redirection belongs to it, not to the command.
            if inWord, !isQuoted, !text.isEmpty, text.allSatisfy(\.isNumber) { resetWord() }
            guard endWord(), redirection == nil else { return false }
            index += 1
            redirection = character == "<"
            while let next = characters.dropFirst(index).first, next == ">" || next == "|" {
                redirection = false
                index += 1
            }
            if characters.dropFirst(index).first == "&" {
                index += 1
                while let next = characters.dropFirst(index).first, next.isNumber || next == "-" {
                    index += 1
                }
                redirection = nil
            }
            return true
        }

        mutating func singleQuoted() -> Bool {
            guard let close = characters[(index + 1)...].firstIndex(of: "'") else { return false }
            inWord = true
            isQuoted = true
            text.append(contentsOf: characters[(index + 1)..<close])
            index = close + 1
            return true
        }

        mutating func doubleQuoted() -> Bool {
            inWord = true
            isQuoted = true
            index += 1
            while index < characters.count {
                switch characters[index] {
                case "\"":
                    index += 1
                    return true
                case "`":
                    return false
                case "$":
                    guard variable() else { return false }
                case "\\":
                    guard let next = peek() else { return false }
                    if "$`\"\\".contains(next) {
                        text.append(next)
                    } else if next != "\n" {
                        text.append("\\")
                        text.append(next)
                    }
                    index += 2
                default:
                    text.append(characters[index])
                    index += 1
                }
            }
            return false
        }

        /// `$HOME` and `${HOME}` become the home directory; any other expansion leaves the word unresolved, and a substitution refuses the line.
        mutating func variable() -> Bool {
            inWord = true
            guard let next = peek() else {
                text.append("$")
                index += 1
                return true
            }
            if next == "(" || next == "'" { return false }
            let name: String
            if next == "{" {
                guard let close = characters[index...].firstIndex(of: "}") else { return false }
                name = String(characters[(index + 2)..<close])
                index = close + 1
            } else if next.isLetter || next == "_" {
                let identifier = characters[(index + 1)...].prefix { $0.isLetter || $0.isNumber || $0 == "_" }
                name = String(identifier)
                index += 1 + identifier.count
            } else if next == " " || next == "\t" || next == "\"" {
                text.append("$")
                index += 1
                return true
            } else {
                name = String(next)
                index += 2
            }
            if name == "HOME" {
                text.append(home)
            } else {
                text.append("$" + name)
                isUnresolved = true
            }
            return true
        }

        /// `~` alone or before a slash is the home directory; `~name`, `~+` and `~-` are left unresolved.
        mutating func tilde() {
            inWord = true
            let rest = characters[(index + 1)...].prefix { !" \t\n;&|<>/".contains($0) }
            if rest.isEmpty {
                text.append(home)
            } else {
                text.append("~" + String(rest))
                isUnresolved = true
            }
            index += 1 + rest.count
        }

        mutating func resetWord() {
            text = ""
            inWord = false
            isQuoted = false
            isUnresolved = false
        }

        /// Finishes the word being read, as a redirection's target or the command's next word; false where a group begins.
        mutating func endWord() -> Bool {
            guard inWord else { return true }
            // A brace group or a bare `{` is a compound command, whose inside is not one simple command.
            if !isQuoted, text == "{" || text == "}" { return false }
            // A test's brackets stand alone as words and are no glob.
            let isBracket = text == "[" || text == "]" || text == "[[" || text == "]]"
            let word = ShellWord(text, isUnresolved: isUnresolved && !isBracket)
            switch redirection {
            case true?: inputs.append(word)
            case false?: break
            case nil: words.append(word)
            }
            redirection = nil
            resetWord()
            return true
        }

        /// Finishes the word and the simple command, false where an operator stands with nothing before it or a redirection with no target.
        mutating func close(_ separator: ShellSeparator) -> Bool {
            guard endWord(), redirection == nil else { return false }
            guard !words.isEmpty || !inputs.isEmpty else { return separator == .sequence }
            end(separator)
            return true
        }

        mutating func end(_ separator: ShellSeparator) {
            commands.append(SimpleCommand(words: words, inputs: inputs, separator: separator))
            words = []
            inputs = []
        }
    }
}
