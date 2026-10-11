extension ShellPrompt {
    /// Who owns the line the caret sits on; unknown in a heredoc body and where no prompt is recognised.
    package static func lineOwner(in value: String, before caret: String.Index) -> LineOwner {
        if isHereDocumentBody(in: value, before: caret) { return .unknown }
        let line = value[..<caret].split(separator: "\n", omittingEmptySubsequences: false).last
        return lineOwner(of: line.map(String.init) ?? "")
    }

    /// Who owns a single terminal line, from its prompt text only.
    package static func lineOwner(of line: String) -> LineOwner {
        if let language = replLanguage(of: line) { return .repl(language) }
        if afterArrowPrompt(in: line) != nil { return .shell(.zsh) }
        guard let end = promptEnd(in: line) else { return .unknown }
        switch line[end] {
        case "%": return .shell(.zsh)
        case "$", "#": return .shell(.posix)
        case ">" where line.hasPrefix("PS "): return .shell(.powerShell)
        default: return .shell(.unspecified)
        }
    }

    /// The language of an interpreter prompt that begins the line.
    private static func replLanguage(of line: String) -> ReplLanguage? {
        let word = line.prefix { !$0.isWhitespace }
        // A prompt stands alone: the line ends there or a space follows, so a marker glued to text is not one.
        let rest = line.dropFirst(word.count)
        guard rest.isEmpty || rest.first == " " else { return nil }
        if isPythonPrompt(word, rest: rest) { return .python }
        if isSQLPrompt(word, rest: rest) { return .sql }
        if isIRBPrompt(word) { return .ruby }
        return nil
    }

    /// `>>>` exactly, `(Pdb)`, or IPython's `In [3]:`.
    private static func isPythonPrompt(_ word: Substring, rest: Substring) -> Bool {
        if word == ">>>" || word == "(Pdb)" { return true }
        guard word == "In", rest.hasPrefix(" [") else { return false }
        let numbered = rest.dropFirst(2)
        guard let close = numbered.firstIndex(of: "]") else { return false }
        let number = numbered[..<close]
        let tail = numbered[numbered.index(after: close)...]
        return !number.isEmpty && number.allSatisfy(isDigit) && (tail == ":" || tail.hasPrefix(": "))
    }

    /// `mysql>`, `mariadb>`, `sqlite>`, `MariaDB [name]>`, and psql's `name=#`, `name=>`, `name-#` or `name(#`.
    private static func isSQLPrompt(_ word: Substring, rest: Substring) -> Bool {
        if ["mysql>", "mariadb>", "sqlite>"].contains(word) { return true }
        if word == "MariaDB" { return isMariaDBPrompt(rest) }
        return isPsqlPrompt(word)
    }

    /// The bracketed database after `MariaDB`, then `>`.
    private static func isMariaDBPrompt(_ rest: Substring) -> Bool {
        guard rest.hasPrefix(" ["), let close = rest.firstIndex(of: "]") else { return false }
        let name = rest.dropFirst(2)[..<close]
        let tail = rest[rest.index(after: close)...]
        return !name.isEmpty && !name.contains("[") && (tail == ">" || tail.hasPrefix("> "))
    }

    /// A database name that starts with a letter, an optional transaction mark, then the psql marker.
    private static func isPsqlPrompt(_ word: Substring) -> Bool {
        guard let first = word.first, first.isASCII, first.isLetter else { return false }
        let name = word.prefix { $0.isASCII && ($0.isLetter || $0.isNumber || $0 == "_") }
        var tail = word.dropFirst(name.count)
        if tail.hasPrefix("=") || tail.hasPrefix("-") || tail.hasPrefix("(") {
            let marker = tail.removeFirst()
            if marker == "=", let mark = tail.first, "*!^".contains(mark) { tail.removeFirst() }
            return marker == "=" ? tail == "#" || tail == ">" : tail == "#"
        }
        return false
    }

    /// `irb(main):001>` with an optional nesting count before the `>`.
    private static func isIRBPrompt(_ word: Substring) -> Bool {
        guard word.hasPrefix("irb("), word.hasSuffix(">"), let close = word.firstIndex(of: ")") else {
            return false
        }
        let counts = word[word.index(after: close)...].dropLast()
        guard counts.hasPrefix(":") else { return false }
        let numbers = counts.dropFirst().split(separator: ":", omittingEmptySubsequences: false)
        return !numbers.isEmpty && numbers.allSatisfy { !$0.isEmpty && $0.allSatisfy(isDigit) }
    }

    /// Whether this is one of the ten ASCII digits.
    private static func isDigit(_ character: Character) -> Bool {
        character.isASCII && character.isNumber
    }
}
