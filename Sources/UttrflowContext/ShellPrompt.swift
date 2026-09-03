/// The user's own input on a terminal line, which Accessibility reports with the shell prompt in front of it.
public enum ShellPrompt {
    /// A stretch of one line, which is what the evidence for a prompt is read out of.
    private typealias Line = ArraySlice<Character>

    /// The characters a prompt ends with, every one of which a command may also legitimately contain.
    private static let terminators: Set<Character> = ["%", "$", "#", ">", "✗", "✔", "✓", "❯"]

    /// What the user typed on this line, or the whole line where no prompt stands in front of it.
    public static func input(in line: String) -> String {
        let characters = Array(line)
        guard let terminator = promptEnd(in: characters) else { return line }
        return String(characters[(terminator + 1)...].drop(while: \.isWhitespace))
    }

    /// The first terminator that is outside every quote and carries the evidence its character needs.
    private static func promptEnd(in characters: [Character]) -> Int? {
        var quote: Character?
        var index = 0
        while index < characters.count {
            let character = characters[index]
            if let open = quote {
                if character == open { quote = nil }
            } else if character == "'" || character == "\"" {
                quote = character
            } else if character == "\\" {
                index += 1
            } else if endsAPrompt(characters, at: index) {
                return index
            }
            index += 1
        }
        return nil
    }

    /// Whether this character ends a prompt, which takes a space after it and the right company before it.
    private static func endsAPrompt(_ characters: [Character], at index: Int) -> Bool {
        guard terminators.contains(characters[index]) else { return false }
        let next = index + 1 < characters.count ? characters[index + 1] : nil
        guard next?.isWhitespace ?? true else { return false }
        return isPlausible(characters[index], after: characters[..<index])
    }

    /// What each terminator demands of the text before it, since each is typed for other reasons too.
    private static func isPlausible(_ terminator: Character, after prefix: Line) -> Bool {
        switch terminator {
        // zsh puts a space before its `%`, and a percentage never does.
        case "%": prefix.last?.isWhitespace ?? true
        // A shell expands a bare `$` before a name, so one before a space is a prompt rather than a sigil.
        case "$": !(prefix.last?.isWhitespace ?? false)
        // A root prompt names a host or a database, which is what tells it from a trailing comment.
        case "#": prefix.allSatisfy(\.isWhitespace) || prefix.last == "=" || prefix.contains("@")
        // A `>` is a redirection unless it is a run of them, or the tail of a `=>` prompt.
        case ">": prefix.allSatisfy { $0 == ">" || $0.isWhitespace } || prefix.last == "="
        // A tick, a cross and a chevron are drawn by prompt themes and typed by nobody.
        default: true
        }
    }
}
