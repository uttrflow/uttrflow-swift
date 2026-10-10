private import Synchronization
import Foundation

/// How many characters were read while this was bound to `ShellPrompt.tally`.
package final class CharacterTally: Sendable {
    private let read = Mutex(0)

    package init() {}

    /// The characters read so far.
    package var count: Int { read.withLock { $0 } }

    func record(_ characters: Int) { read.withLock { $0 += characters } }
}

/// Removes recognized POSIX, fish, Starship, Nushell and PowerShell prompt shapes without parsing shell commands.
public enum ShellPrompt {
    /// The characters a prompt ends with, every one of which a command may also legitimately contain.
    private static let terminators: Set<Character> = [
        "%", "$", "#", ">", "✗", "✔", "✓", "❯", "➜", "➤", "\u{e0b0}",
    ]

    /// Named interactive prompts whose final `>` is not shell redirection.
    private static let interactivePromptLabels: Set<String> = ["mysql", "mongosh", "sqlite", "test"]

    /// How far into a line a prompt is looked for, since a prompt is short and a pasted line need not be.
    package static let searchLimit = 4_096

    /// Whether the caret sits in the body of an unfinished shell heredoc.
    package static func isHereDocumentBody(in value: String, before caret: String.Index) -> Bool {
        let prefix = value[..<caret]
        let lines = prefix.split(separator: "\n", omittingEmptySubsequences: false)
        guard lines.count > 1 else { return false }
        var delimiters: [HereDocumentDelimiter] = []
        for line in lines.dropLast() {
            if let delimiter = delimiters.first {
                if delimiter.matches(String(line)) { delimiters.removeFirst() }
            } else {
                delimiters.append(contentsOf: hereDocumentDelimiters(in: line))
            }
        }
        if let delimiter = delimiters.first, lines.last.map(String.init).map(delimiter.matches) == true {
            delimiters.removeFirst()
        }
        return !delimiters.isEmpty
    }

    /// The delimiter words opened by shell or Ruby heredoc syntax on one command line.
    private static func hereDocumentDelimiters(in line: Substring) -> [HereDocumentDelimiter] {
        let characters = Array(line)
        var delimiters: [HereDocumentDelimiter] = []
        var index = 0
        while index < characters.count {
            if characters[index] == "\\" {
                index = min(index + 2, characters.count)
            } else if characters[index] == "'" || characters[index] == "\"" {
                index = endOfQuotedText(in: characters, startingAt: index) ?? characters.count
            } else if characters[index] == "#",
                index == 0 || characters[index - 1].isWhitespace
            {
                break
            } else if isHereDocumentOperator(characters, at: index),
                let parsed = hereDocumentDelimiter(in: characters, afterOperatorAt: index)
            {
                delimiters.append(parsed.delimiter)
                index = parsed.nextIndex
            } else {
                index += 1
            }
        }
        return delimiters
    }

    /// Whether two angle brackets begin a heredoc operator rather than a here-string.
    private static func isHereDocumentOperator(_ characters: [Character], at index: Int) -> Bool {
        index + 1 < characters.count && characters[index] == "<" && characters[index + 1] == "<"
            && (index == 0 || characters[index - 1] != "<")
            && (index + 2 == characters.count || characters[index + 2] != "<")
    }

    /// Parses the modifier and quote-removed delimiter following an unquoted heredoc operator.
    private static func hereDocumentDelimiter(
        in characters: [Character], afterOperatorAt index: Int
    ) -> (delimiter: HereDocumentDelimiter, nextIndex: Int)? {
        var cursor = index + 2
        var modifier: Character?
        if cursor < characters.count, characters[cursor] == "-" || characters[cursor] == "~" {
            modifier = characters[cursor]
            cursor += 1
        }
        while cursor < characters.count, characters[cursor].isWhitespace { cursor += 1 }
        let start = cursor
        var tag = ""
        while cursor < characters.count {
            let character = characters[cursor]
            if character == "'" || character == "\"" {
                guard let end = endOfQuotedText(in: characters, startingAt: cursor) else { return nil }
                tag += quoteRemoved(in: characters, from: cursor + 1, to: end - 1, quote: character)
                cursor = end
            } else if character == "\\", cursor + 1 < characters.count {
                tag.append(characters[cursor + 1])
                cursor += 2
            } else if character.isWhitespace || ";|&<>".contains(character) {
                break
            } else {
                tag.append(character)
                cursor += 1
            }
        }
        guard cursor > start, !tag.isEmpty else { return nil }
        return (HereDocumentDelimiter(tag: tag, modifier: modifier), cursor)
    }

    /// The position after a closed quote, respecting escaped characters in double quotes.
    private static func endOfQuotedText(in characters: [Character], startingAt start: Int) -> Int? {
        let quote = characters[start]
        var index = start + 1
        while index < characters.count {
            if quote == "\"", characters[index] == "\\" {
                index = min(index + 2, characters.count)
            } else if characters[index] == quote {
                return index + 1
            } else {
                index += 1
            }
        }
        return nil
    }

    /// Removes the quote and the backslashes that shell quote removal consumes.
    private static func quoteRemoved(
        in characters: [Character], from start: Int, to end: Int, quote: Character
    ) -> String {
        guard quote == "\"" else { return String(characters[start..<end]) }
        var result = ""
        var index = start
        while index < end {
            if characters[index] == "\\", index + 1 < end,
                "$`\"\\".contains(characters[index + 1]) || characters[index + 1].isNewline
            {
                index += 1
            }
            result.append(characters[index])
            index += 1
        }
        return result
    }

    /// One heredoc terminator, with the indentation rule selected by its opener.
    private struct HereDocumentDelimiter {
        let tag: String
        let modifier: Character?

        func matches(_ line: String) -> Bool {
            switch modifier {
            case "-": String(line.drop(while: { $0 == "\t" })) == tag
            case "~": line.drop(while: \.isWhitespace).elementsEqual(tag)
            default: line == tag
            }
        }
    }

    /// Counts the characters read while bound, so a test can bound the work without a clock.
    @TaskLocal package static var tally: CharacterTally?

    /// What the user typed on this line, or the whole line where no prompt stands in front of it.
    public static func input(in line: String) -> String {
        if let typed = afterArrowPrompt(in: line) { return typed }
        guard let terminator = promptEnd(in: line) else { return line }
        return String(line[line.index(after: terminator)...].drop(while: \.isWhitespace))
    }

    /// Whether a terminal line is asking for a credential rather than a shell command.
    static func isCredentialPrompt(in line: String) -> Bool {
        CredentialPrompt.matches(line)
    }

    /// The marks an arrow prompt draws after the branch when the tree has changes, or has none.
    private static let changeMarks: Set<Character> = ["✗", "✔", "✓"]

    /// What follows a leading `➜  directory` prompt, with the `git:(branch)` and change mark a repository adds; absent where the line does not begin with one.
    private static func afterArrowPrompt(in line: String) -> String? {
        var rest = line.drop(while: \.isWhitespace)
        guard rest.first == "➜" else { return nil }
        rest = rest.dropFirst()
        // The theme draws the arrow and then two spaces, which a lone arrow typed as text never has.
        guard rest.prefix(while: \.isWhitespace).count >= 2 else { return nil }
        rest = rest.drop(while: \.isWhitespace).drop { !$0.isWhitespace }.drop(while: \.isWhitespace)
        let branch = rest.prefix { !$0.isWhitespace }
        if branch.hasSuffix(")"), let open = branch.firstIndex(of: "("), branch[..<open].hasSuffix(":"),
            branch[..<open].dropLast().allSatisfy(\.isLetter)
        {
            rest = rest.dropFirst(branch.count).drop(while: \.isWhitespace)
        }
        if let mark = rest.first, changeMarks.contains(mark), rest.dropFirst().first?.isWhitespace ?? true {
            rest = rest.dropFirst().drop(while: \.isWhitespace)
        }
        return String(rest)
    }

    /// What has been read of the line so far, carried forward so no terminator rereads the text before it.
    private struct Prefix {
        /// The character just before the one being read.
        var last: Character?
        /// Whether everything so far is whitespace.
        var isBlank = true
        /// Whether everything so far is whitespace or a chevron.
        var isChevrons = true
        /// Whether an at sign has been seen outside every quote.
        var hasAt = false
        /// Whether the prefix contains characters outside quotes and substitutions.
        var outsideSubstitution = true

        /// Takes one more character into what has been read, noting whether a quote holds it.
        mutating func append(_ character: Character, quoted: Bool) {
            last = character
            isBlank = isBlank && character.isWhitespace
            isChevrons = isChevrons && (character == ">" || character.isWhitespace)
            hasAt = hasAt || (outsideSubstitution && !quoted && character == "@")
        }
    }

    /// The first terminator within the search limit that is outside every quote and carries the evidence its character needs.
    private static func promptEnd(in line: String) -> String.Index? {
        var prefix = Prefix()
        var quote: Character?
        var escaped = false
        // One count of open parentheses per enclosing `$(`, innermost last; `$(` pushes 0 and its `(` counts as one.
        var substitutions: [Int] = []
        var read = 0
        let isPowerShell = line.hasPrefix("PS ")
        defer { tally?.record(read) }
        var index = line.startIndex
        while index < line.endIndex, read < searchLimit {
            let character = line[index]
            let next = line.index(after: index)
            read += 1
            if escaped {
                escaped = false
            } else if let open = quote {
                if character == open {
                    quote = nil
                } else if open == "\"",
                    character == "\\" || (isPowerShell && character == "`")
                {
                    escaped = true
                }
            } else if character == "$", next < line.endIndex, line[next] == "(" {
                substitutions.append(0)
            } else if !substitutions.isEmpty {
                if character == "'" || character == "\"" {
                    quote = character
                } else if character == "(" {
                    substitutions[substitutions.count - 1] += 1
                } else if character == ")" {
                    substitutions[substitutions.count - 1] -= 1
                    if substitutions[substitutions.count - 1] == 0 { substitutions.removeLast() }
                }
            } else if character == "'" || character == "\"" {
                quote = character
            } else if character == "\\" || (isPowerShell && character == "`") {
                escaped = true
            } else if terminators.contains(character),
                next == line.endIndex || line[next].isWhitespace,
                isPlausible(character, after: prefix, linePrefix: line[..<index])
            {
                return index
            }
            prefix.outsideSubstitution = substitutions.isEmpty
            prefix.append(character, quoted: quote != nil)
            index = next
        }
        return nil
    }

    /// What each terminator demands of the text before it, since each is typed for other reasons too.
    private static func isPlausible(
        _ terminator: Character, after prefix: Prefix, linePrefix: Substring
    ) -> Bool {
        switch terminator {
        // zsh puts a space before its `%`, and its prompt names a host, directory or shell.
        case "%": (prefix.last?.isWhitespace ?? true) && isZshPromptPrefix(linePrefix)
        // A dollar ends a prompt only when its prefix is a host, directory or shell name, not command text.
        case "$":
            prefix.isBlank || isBarePromptName(linePrefix) || isPromptMarkerPrefix(linePrefix)
        // A root prompt ends a directory, host, or shell name with a hash; a spaced comment does not.
        case "#":
            prefix.isBlank || prefix.last == "="
                || (prefix.hasAt && !(prefix.last?.isWhitespace ?? true))
                || isDirectoryPrompt(linePrefix, allowsMarkerSpacing: true)
                || isNamedPromptWithDirectory(linePrefix) || isBarePromptName(linePrefix)
        // A `>` is a redirection unless it is a run of them, the tail of a `=>` prompt, or fish glues it to a path token in a `user@host` prompt.
        case ">":
            prefix.isChevrons || prefix.last == "="
                || (prefix.hasAt && !(prefix.last?.isWhitespace ?? true))
                || isPowerShellDirectoryPrompt(linePrefix)
                || isDirectoryPrompt(linePrefix)
                || isInteractiveShellPrompt(linePrefix)
        // Theme glyphs, like shell markers, need a prompt-shaped prefix.
        case "➜", "➤", "\u{e0b0}":
            isPromptMarkerPrefix(linePrefix)
                || isStarshipPromptPrefix(linePrefix, allowsBareBranch: true)
        case "✗", "✔", "✓", "❯":
            prefix.isBlank || isPromptMarkerPrefix(linePrefix)
                || isStarshipPromptPrefix(linePrefix, allowsBareBranch: terminator == "❯")
        default: false
        }
    }

    /// A zsh prompt prefix is empty, a shell or directory name, or a host with its current directory.
    private static func isZshPromptPrefix(_ prefix: Substring) -> Bool {
        let parts = prefix.split(whereSeparator: \.isWhitespace)
        guard !parts.isEmpty else { return true }
        let promptParts =
            parts.first?.hasPrefix("(") == true && parts.first?.hasSuffix(")") == true
            ? Array(parts.dropFirst()) : Array(parts)
        guard let first = promptParts.first else { return false }
        if promptParts.count == 1 {
            return first == "zsh" || isZshHost(first) || isZshDirectory(first)
        }
        guard promptParts.count == 2, isZshHost(first), let directory = promptParts.last else {
            return false
        }
        return isZshDirectory(directory)
    }

    /// A zsh hostname has a non-empty user and host separated by `@`, which may be escaped in the line.
    static func isZshHost(_ name: Substring) -> Bool {
        let unescapedAt = Substring(name.replacingOccurrences(of: #"\@"#, with: "@"))
        guard
            isBarePromptName(unescapedAt), let at = unescapedAt.firstIndex(of: "@"),
            at > unescapedAt.startIndex
        else {
            return false
        }
        return unescapedAt.index(after: at) < unescapedAt.endIndex
    }

    /// A zsh current directory is a path or a simple directory name.
    static func isZshDirectory(_ name: Substring) -> Bool {
        name.hasPrefix("~") || name.hasPrefix("/") || name.hasPrefix("./")
            || name.hasPrefix("../") || isBarePromptName(name)
    }

    /// A PowerShell prompt starts with `PS ` and ends its current-directory token at `>`.
    private static func isPowerShellDirectoryPrompt(_ prefix: Substring) -> Bool {
        guard prefix.hasPrefix("PS ") else { return false }
        let path = prefix.dropFirst(3)
        return !path.isEmpty && !(path.last?.isWhitespace ?? true)
    }

    /// A username/host followed by a path, as shown by prompts such as `user@host ~/project $`.
    static func isNamedPromptWithDirectory(_ prefix: Substring) -> Bool {
        let words = prefix.split(whereSeparator: \.isWhitespace)
        guard words.count == 2, isBarePromptName(words[0]), let directory = words.last else { return false }
        return directory.hasPrefix("~") || directory.hasPrefix("/") || directory.hasPrefix("./")
            || directory.hasPrefix("../")
    }

    /// A single host or versioned shell name immediately before its prompt marker.
    static func isBarePromptName(_ prefix: Substring) -> Bool {
        let words = prefix.split(whereSeparator: \.isWhitespace)
        guard words.count == 1, let name = words.first,
            name.contains(where: \.isLetter), !name.contains(where: { $0 == "/" || $0 == "\\" })
        else { return false }
        return name.allSatisfy { $0.isASCII && ($0.isLetter || $0.isNumber || ".-_@".contains($0)) }
    }

    /// Whether a `>` follows one of the known interactive database or language shell labels.
    private static func isInteractiveShellPrompt(_ prefix: Substring) -> Bool {
        guard let last = prefix.last, !last.isWhitespace else { return false }
        let label = String(prefix).lowercased()
        if interactivePromptLabels.contains(label) { return true }
        if label.hasPrefix("irb(main):") {
            let lineNumber = label.dropFirst("irb(main):".count)
            return !lineNumber.isEmpty && lineNumber.allSatisfy(\.isNumber)
        }
        guard label.hasPrefix("psql ("), label.hasSuffix(")") else { return false }
        let database = label.dropFirst("psql (".count).dropLast()
        return !database.isEmpty && !database.contains(where: { $0 == "(" || $0 == ")" })
    }

    /// A directory-bearing prompt ends at its path marker rather than treating `>` as a redirection.
    static func isDirectoryPrompt(_ prefix: Substring, allowsMarkerSpacing: Bool = false) -> Bool {
        let trailingWhitespace = prefix.reversed().prefix(while: \.isWhitespace).count
        let whitespaceSuffix = prefix.suffix(trailingWhitespace)
        guard
            allowsMarkerSpacing || trailingWhitespace == 0 || whitespaceSuffix.contains("\n")
                || whitespaceSuffix.contains("\r")
        else {
            return false
        }
        let path = prefix.dropLast(trailingWhitespace)
        return path.hasPrefix("~") || path.hasPrefix("/") || path.hasPrefix("./") || path.hasPrefix("../")
    }
}
