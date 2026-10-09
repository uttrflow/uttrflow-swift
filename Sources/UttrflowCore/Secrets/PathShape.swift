// Recognises a path to a file or folder on this Mac.

/// A path to a file or folder on this Mac, and only when the whole clip is the path.
package enum PathShape {
    /// The prefixes that make a path a path; bare `Users/x` is how people write most things with slashes.
    package static let starts = ["/", "~/", "./", "../"]

    package static func matches(_ text: String) -> Bool {
        // One line: a path with a newline in it is a list or a paragraph.
        guard !text.contains(where: \.isNewline) else { return false }
        guard text.count <= 4096 else { return false }
        guard starts.contains(where: text.hasPrefix) else { return false }
        // `~` alone, or `/` alone, is a shell shorthand rather than a clip worth filing.
        guard text.count > 2 else { return false }

        // A flag in any component makes this look like a command, not a copied path.
        let parts = text.split(separator: " ", omittingEmptySubsequences: false)
        guard !parts.contains(where: { $0.hasPrefix("-") }) else { return false }
        // `./` and `../` carry their own slash; a rooted path needs a second one to name more than a top folder.
        guard !text.hasPrefix("/") || text.dropFirst().contains("/") else { return false }
        guard !isSentenceOrCommand(text) else { return false }

        // Characters no filesystem path carries, which code and prose use constantly.
        let forbidden: Set<Character> = ["|", "*", "<", ">", "\"", "\n", "\t"]
        return !text.contains(where: forbidden.contains)
    }

    /// Spaces belong to a file name only until its extension, and nothing in a `bin` folder is a file worth naming.
    private static func isSentenceOrCommand(_ text: String) -> Bool {
        guard let slash = text.lastIndex(of: "/") else { return false }
        let words = text[text.index(after: slash)...].split(separator: " ")
        guard words.count > 1 else { return false }
        let folder = text[..<slash]
        if folder.hasSuffix("/bin") || folder.hasSuffix("/sbin") { return true }
        return words.dropLast().contains { $0.contains(/\.[A-Za-z][A-Za-z0-9]{0,4}$/) }
    }
}
