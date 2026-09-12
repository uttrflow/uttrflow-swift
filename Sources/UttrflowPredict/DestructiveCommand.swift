/// Recognises command lines that destroy data or the machine, so they are never learned or auto-offered.
public enum DestructiveCommand {
    /// Whether taking this line as a completion could do irreversible harm, judged conservatively.
    public static func matches(_ text: String) -> Bool {
        let lower = text.lowercased()
        // A fork bomb carries no ordinary tokens, so it is matched on the whitespace-stripped text.
        if lower.filter({ !$0.isWhitespace }).contains(":(){:|:&};:") { return true }
        // Each clause is judged on its own words, so a later command is read and an earlier one's flags are not borrowed.
        return clauses(of: lower).contains(where: destroys)
    }

    /// The line cut where one command ends and the next begins.
    private static func clauses(of lower: String) -> [String] {
        lower.split(whereSeparator: { $0 == ";" || $0 == "&" || $0 == "|" || $0.isNewline })
            .map(String.init)
    }

    /// Whether one clause destroys data or the machine.
    private static func destroys(_ clause: String) -> Bool {
        let tokens = clause.split { $0 == " " || $0 == "\t" }.map(String.init)
        guard let head = tokens.first else { return false }
        // sudo hides the real command one token along, so the command is read past it.
        let command = head == "sudo" ? (tokens.dropFirst().first ?? head) : head
        let words = Set(tokens)

        switch command {
        case "rm", "rmdir", "shred", "dd", "mkfs", "fdisk", "parted",
            "shutdown", "reboot", "halt", "poweroff":
            return true
        case "git":
            return matchesDestructiveGit(tokens)
        default:
            break
        }

        // SQL that drops or empties a table, wherever the verb sits in the clause.
        if words.contains("drop"), words.contains(where: droppableObject) { return true }
        if words.contains("truncate") { return true }
        // Writing onto a raw device node overwrites the disk behind it.
        if clause.contains("of=/dev/") || clause.contains("/dev/sd") || clause.contains("/dev/disk") {
            return true
        }
        return false
    }

    /// Whether a git clause force-pushes, hard-resets, or force-cleans, which cannot be undone.
    private static func matchesDestructiveGit(_ tokens: [String]) -> Bool {
        // The flag has to stand after the subcommand it belongs to, so a word quoted elsewhere is not one.
        func flags(after subcommand: String) -> ArraySlice<String>? {
            tokens.firstIndex(of: subcommand).map { tokens[($0 + 1)...] }
        }
        if let flags = flags(after: "push"),
            flags.contains(where: { $0 == "--force" || $0 == "-f" || $0.hasPrefix("+") })
        {
            return true
        }
        if let flags = flags(after: "reset"), flags.contains("--hard") { return true }
        if let flags = flags(after: "clean"),
            flags.contains(where: { $0.hasPrefix("-") && $0.contains("f") })
        {
            return true
        }
        return false
    }

    /// The kinds of thing a DROP destroys, which is what makes the statement irreversible.
    private static func droppableObject(_ word: String) -> Bool {
        word == "table" || word == "database" || word == "schema" || word == "index"
    }
}
