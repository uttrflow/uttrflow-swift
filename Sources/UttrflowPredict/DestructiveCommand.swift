/// Recognises command lines that destroy data or the machine, so they are never learned or auto-offered.
public enum DestructiveCommand {
    /// Whether taking this line as a completion could do irreversible harm, judged conservatively.
    public static func matches(_ text: String) -> Bool {
        let lower = text.lowercased()
        // A fork bomb carries no ordinary tokens, so it is matched on the whitespace-stripped text.
        if lower.filter({ !$0.isWhitespace }).contains(":(){:|:&};:") { return true }

        let tokens = lower.split { $0 == " " || $0 == "\t" }.map(String.init)
        guard let head = tokens.first else { return false }
        // sudo hides the real command one token along, so the command is read past it.
        let command = head == "sudo" ? (tokens.dropFirst().first ?? head) : head
        let words = Set(tokens)

        switch command {
        case "rm", "rmdir", "shred", "dd", "mkfs", "fdisk", "parted",
            "shutdown", "reboot", "halt", "poweroff":
            return true
        case "git":
            return matchesDestructiveGit(words)
        default:
            break
        }

        // SQL that drops or empties a table, wherever the verb sits in the line.
        if words.contains("drop"), words.contains(where: droppableObject) { return true }
        if words.contains("truncate") { return true }
        // Writing onto a raw device node overwrites the disk behind it.
        if lower.contains("of=/dev/") || lower.contains("/dev/sd") || lower.contains("/dev/disk") {
            return true
        }
        return false
    }

    /// Whether a git line force-pushes, hard-resets, or force-cleans, which cannot be undone.
    private static func matchesDestructiveGit(_ words: Set<String>) -> Bool {
        if words.contains("push"),
            words.contains(where: { $0 == "--force" || $0 == "-f" || $0.hasPrefix("+") })
        {
            return true
        }
        if words.contains("reset"), words.contains("--hard") { return true }
        if words.contains("clean"), words.contains(where: { $0.hasPrefix("-") && $0.contains("f") }) {
            return true
        }
        return false
    }

    /// The kinds of thing a DROP destroys, which is what makes the statement irreversible.
    private static func droppableObject(_ word: String) -> Bool {
        word == "table" || word == "database" || word == "schema" || word == "index"
    }
}
