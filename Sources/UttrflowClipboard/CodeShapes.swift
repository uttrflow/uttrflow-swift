// Recognises source code and shell commands.

import Foundation

/// Recognises code by two independent code-shaped signals, or by one unmistakable one.
enum CodeShapes {
    /// Counts the UTF-8 bytes handed to the signals while bound, so a test can bound the reading without a clock.
    @TaskLocal package static var tally: ScanTally?

    static func matches(_ text: String) -> Bool {
        if text.hasPrefix("#!") { return true }
        if isImportHeader(text) { return true }
        if isShellCommand(text) { return true }
        return hasTwoSignals(in: CodeSample.of(text))
    }

    // MARK: - The signals

    /// Whether the text carries two independent hints of code, read cheapest first and stopping at the second.
    private static func hasTwoSignals(in text: String) -> Bool {
        tally?.record(text.utf8.count)
        // A pattern runs only when the bytes hold a literal it cannot match without.
        func has(_ pattern: Regex<Substring>, needing literals: [StaticString]) -> Bool {
            ClipBytes.containsAny(text, literals) && text.firstMatch(of: pattern) != nil
        }
        let signals: [() -> Bool] = [
            { text.contains("{") && text.contains("}") },
            { hasStatementEnding(text) },
            { isIndented(text) },
            { has(invocation, needing: ["("]) },
            { has(commentLine, needing: ["//", "/*", "*", "#", "--"]) },
            { text.firstMatch(of: query) != nil },
            { has(shellFragment, needing: ["|", "&&", "$(", ">", "-"]) },
            {
                has(
                    controlFlow,
                    needing: ["(", "return", "throw", "break", "continue", "yield", "else", "elif", "endif"])
            },
            { has(codeOperator, needing: ["=>", "->", "::", "==", "&&", "||", "+=", "-=", "++", "!="]) },
            {
                has(
                    declaration,
                    needing: [
                        "func", "def", "fn", "sub", "class", "struct", "enum", "interface", "trait",
                        "protocol",
                        "actor", "let", "var", "const", "val", "public", "private", "internal", "static",
                        "async",
                        "await", "import", "from", "package", "using", "require", "#include",
                    ])
            },
        ]
        var found = 0
        for signal in signals where signal() {
            found += 1
            if found == 2 { return true }
        }
        return false
    }

    /// A line that ends in a semicolon or a brace; mid-line, a semicolon is punctuation people use.
    static func hasStatementEnding(_ text: String) -> Bool {
        text.split(whereSeparator: \.isNewline).contains { line in
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            return trimmed.hasSuffix(";") || trimmed.hasSuffix("{") || trimmed.hasSuffix("}")
        }
    }

    /// A continuation line that begins indented; a wrapped paragraph does not indent its second line.
    static func isIndented(_ text: String) -> Bool {
        text.split(whereSeparator: \.isNewline).dropFirst().contains { line in
            line.hasPrefix("\t") || line.hasPrefix("  ")
        }
    }

    /// Something being declared: a function, a type, a binding with a value, an import with a module.
    nonisolated(unsafe) static let declaration =
        #/
        \b(?: func | function | def | fn | sub )\s+\w+\s*\(
        | \b(?: class | struct | enum | interface | trait | protocol | actor )\s+\w+
        | \b(?: let | var | const | val )\s+\w+\s*[:=]
        | \b(?: public | private | internal | fileprivate | static | async | await )\s+\w
        | ^\h*(?: import | from | package | using | require | \#include | \#import )\s+\S
        /#
        .anchorsMatchLineEndings()

    /// Control flow, independent of declarations, written so it cannot match the English word.
    nonisolated(unsafe) static let controlFlow =
        #/
        \b(?: if | for | while | switch | catch | foreach )\s*\(
        | ^\h*(?: return | throw | break | continue | yield | else | elif | endif )\b
        /#
        .anchorsMatchLineEndings()

    /// Operators that only occur in code; `=` and `==` are left out because prose about equations has them.
    nonisolated(unsafe) static let codeOperator = #/=>|->|::|!==|===|&&|\|\||\+=|-=|\+\+|!=/#

    /// A name immediately followed by an opening bracket: a call, or a definition.
    nonisolated(unsafe) static let invocation = #/\w\(\S/#

    /// A line that opens with a comment marker in one of the usual spellings.
    nonisolated(unsafe) static let commentLine = #/^\h*(?://|/\*|\*\s|\#\s|--\s)/#
        .anchorsMatchLineEndings()

    /// SQL, which has none of the punctuation the other signals look for.
    nonisolated(unsafe) static let query =
        #/(?i)^\h*(?:select|insert\s+into|update|delete\s+from|create\s+table|alter\s+table|drop\s+table)\s+/#
        .anchorsMatchLineEndings()

    /// Shell punctuation: a pipe, a chained command, a substitution, a redirect, a flag.
    nonisolated(unsafe) static let shellFragment = #/\s\|\s|\&\&|\$\(|\s>>?\s|\s--?[a-zA-Z]/#

    // MARK: - The two that stand alone

    /// A clip that opens by importing something, which carries no punctuation for a score to reach.
    nonisolated(unsafe) static let importHeader =
        #/
        ^(?: import | from | package | using | require | \#include | \#import )
        \s+ ["'<]? [\w.:/*-]+ [">']? ;?$
        /#
        .anchorsMatchLineEndings()

    /// The words an import header opens with, checked before its first line is copied out.
    private static let importKeywords = [
        "import", "from", "package", "using", "require", "#include", "#import",
    ]

    static func isImportHeader(_ text: String) -> Bool {
        guard importKeywords.contains(where: text.hasPrefix) else { return false }
        return String(text.prefix(while: { !$0.isNewline })).wholeMatch(of: importHeader) != nil
    }

    /// Whether a one-line clip is a command or a pipeline; the command name is the only signal there is.
    static func isShellCommand(_ text: String) -> Bool {
        ClipBytes.read(text) { _, bytes in asciiShellCommand(bytes) } ?? isShellCommandByCharacter(text)
    }

    /// `isShellCommand` read character by character, which any clip can be.
    static func isShellCommandByCharacter(_ text: String) -> Bool {
        guard !text.contains(where: \.isNewline) else { return false }
        if text.hasPrefix("$ ") || text.hasPrefix("./") { return true }
        var start = text.startIndex
        while start <= text.endIndex {
            let end = text[start...].firstIndex(where: { "|&;".contains($0) }) ?? text.endIndex
            let segment = text[start..<end].drop(while: \.isWhitespace)
            let word = segment.prefix(while: { !$0.isWhitespace })
            let piped = end < text.endIndex && text[end] == "|"
            if !word.isEmpty, isCommand(String(word), rest: segment[word.endIndex...], piped: piped) {
                return true
            }
            guard end < text.endIndex else { break }
            start = text.index(after: end)
        }
        return false
    }

    /// `isShellCommand` read over the bytes of an ASCII clip, where a byte is a character; `nil` for any other clip.
    private static func asciiShellCommand(_ bytes: UnsafeBufferPointer<UInt8>) -> Bool? {
        guard ClipBytes.isASCII(bytes) else { return nil }
        guard !bytes.contains(where: { (0x0A...0x0D).contains($0) }) else { return false }
        if bytes.starts(with: "$ ".utf8) || bytes.starts(with: "./".utf8) { return true }
        func isSpace(_ byte: UInt8) -> Bool { byte == 0x20 || byte == 0x09 }
        func text(_ range: Range<Int>) -> String {
            String(decoding: UnsafeBufferPointer(rebasing: bytes[range]), as: UTF8.self)
        }
        var start = 0
        for offset in 0...bytes.count {
            guard offset == bytes.count || "|&;".utf8.contains(bytes[offset]) else { continue }
            var wordStart = start
            while wordStart < offset, isSpace(bytes[wordStart]) { wordStart += 1 }
            var wordEnd = wordStart
            while wordEnd < offset, !isSpace(bytes[wordEnd]) { wordEnd += 1 }
            // No command is longer than twelve letters, so a longer word is never copied to be looked up.
            if wordEnd > wordStart, wordEnd - wordStart <= 12 {
                let word = text(wordStart..<wordEnd)
                let piped = offset < bytes.count && bytes[offset] == UInt8(ascii: "|")
                // The rest is copied out only for a word that is also English, which needs it read.
                if commands.contains(word),
                    ambiguous[word] == nil
                        || isCommand(word, rest: Substring(text(wordEnd..<offset)), piped: piped)
                {
                    return true
                }
            }
            start = offset + 1
        }
        return false
    }

    /// Whether a segment opening with `word` is a command; a word that is also English needs the rest to look like one.
    static func isCommand(_ word: String, rest: Substring, piped: Bool) -> Bool {
        guard commands.contains(word) else { return false }
        guard let subcommands = ambiguous[word] else { return true }
        if piped { return true }
        let tokens = rest.split(whereSeparator: \.isWhitespace)
        if tokens.contains(where: looksLikeArgument) { return true }
        // `pip install requests` is a command and `pip install is slow today` is a sentence.
        guard let first = tokens.first, subcommands.contains(String(first)) else { return false }
        return !tokens.dropFirst().contains { proseWords.contains($0.lowercased()) }
    }

    /// Words a sentence is held together with, which an argument list never contains.
    private static let proseWords: Set<String> = [
        "is", "are", "was", "were", "be", "been", "the", "a", "an", "to", "of", "and", "or", "but", "for",
        "with", "my", "me", "i", "you", "we", "it", "this", "that", "so", "too", "very", "not", "by", "in",
        "on", "at", "again", "today",
    ]

    /// A flag, a path, an assignment, a redirect or a file name, which prose does not put after a word.
    private static func looksLikeArgument(_ token: Substring) -> Bool {
        if token.count > 1, token.hasPrefix("-") { return true }
        if token.contains("/") || token.contains("=") || token.hasPrefix("~") || token.hasPrefix(".") {
            return true
        }
        if token.hasPrefix(">") || token.hasPrefix("<") { return true }
        // `notes.txt`, `app.js`: a name, a full stop and a short lowercase extension.
        guard let dot = token.lastIndex(of: "."), dot > token.startIndex else { return false }
        let fileExtension = token[token.index(after: dot)...]
        return (1...4).contains(fileExtension.count)
            && fileExtension.allSatisfy { $0.isASCII && ($0.isLowercase || $0.isNumber) }
    }

    /// Command words that are also everyday English, each with the subcommands that make it a command alone.
    static let ambiguous: [String: Set<String>] = [
        "git": [
            "status", "add", "commit", "push", "pull", "clone", "checkout", "switch", "branch", "merge",
            "rebase", "log", "diff", "fetch", "stash", "reset", "init", "remote", "tag", "show", "restore",
            "cherry-pick", "worktree", "bisect", "blame", "config",
        ],
        "sudo": commands,
        "pip": ["install", "uninstall", "freeze", "list", "show"],
        "apt": ["install", "update", "upgrade", "remove", "search", "purge", "autoremove"],
        "cargo": [
            "build", "run", "test", "new", "add", "install", "check", "clippy", "fmt", "publish", "update",
            "bench", "doc",
        ],
        "swift": ["build", "test", "run", "package", "format"],
        "node": [],
        "bun": ["install", "run", "add", "remove", "x", "test", "build", "create", "init", "upgrade"],
        "kill": [],
        "defaults": ["read", "write", "delete", "domains", "find", "export", "import"],
        "tar": ["xf", "xzf", "xvf", "xvzf", "xjf", "cf", "czf", "cvf", "cvzf", "cjf", "tf", "tvf"],
        "ps": ["aux", "ax", "axu", "ef"],
        "cd": [],
        "rm": [],
        "brew": [
            "install", "uninstall", "update", "upgrade", "list", "info", "search", "services", "tap",
            "doctor", "cleanup",
        ],
        "yarn": ["add", "install", "build", "dev", "start", "test", "run", "remove", "upgrade"],
        "curl": [],
        "yum": ["install", "update", "remove"],
    ]

    static let commands: Set<String> = [
        "sudo", "git", "npm", "npx", "yarn", "pnpm", "brew", "docker", "kubectl", "curl",
        "wget", "ssh", "scp", "rsync", "chmod", "chown", "mkdir", "rmdir", "ln", "ls",
        "cd", "rm", "mv", "cp", "grep", "awk", "sed", "tar", "ps", "kill", "killall",
        "launchctl", "systemctl", "defaults", "codesign", "xcrun", "xcodebuild", "swift",
        "swiftc", "cargo", "rustc", "pip", "pip3", "python3", "node", "deno", "bun",
        "apt", "apt-get", "yum", "dnf", "pacman", "terraform", "aws", "gcloud", "psql",
    ]
}

/// The part of a clip the code-shape signals read: all of a small one, and the start, end and evenly spaced windows of a large one.
enum CodeSample {
    /// The most UTF-8 bytes of a clip the signals read.
    static let budget = 64_000

    /// The longest a sample can be: the budget, and a line break after each piece.
    static let longest = budget + windows + 2

    /// Bytes read from each end, where a clip's imports, headers and closing lines are.
    static let edge = 16_000

    /// How many windows are spread across the middle, and how long each is.
    static let windows = 16
    static let window = 2_000

    static func of(_ text: String) -> String {
        let count = text.utf8.count
        guard count > budget else { return text }
        return ClipBytes.read(text) { clip, bytes in
            let middle = count - 2 * edge - window
            var pieces = [piece(clip, bytes, from: 0, to: edge, alignStart: false, alignEnd: true)]
            for index in 0..<windows {
                let start = edge + middle * index / (windows - 1)
                pieces.append(
                    piece(clip, bytes, from: start, to: start + window, alignStart: true, alignEnd: true))
            }
            pieces.append(
                piece(clip, bytes, from: count - edge, to: count, alignStart: true, alignEnd: false))
            var sample = ""
            sample.reserveCapacity(budget + windows + 2)
            for piece in pieces {
                sample += piece
                if !(piece.last?.isNewline ?? true) { sample += "\n" }
            }
            return sample
        }
    }

    /// A piece of the clip trimmed to whole lines where it holds a line break, so no line is read half.
    private static func piece(
        _ clip: ClipBytes, _ bytes: UnsafeBufferPointer<UInt8>, from lower: Int, to upper: Int,
        alignStart: Bool, alignEnd: Bool
    ) -> Substring {
        var lower = lower
        var upper = upper
        let lineFeed = UInt8(ascii: "\n")
        if alignStart, let feed = (lower..<upper).first(where: { bytes[$0] == lineFeed }), feed + 1 < upper {
            lower = feed + 1
        }
        if alignEnd, let feed = (lower..<upper).last(where: { bytes[$0] == lineFeed }) {
            upper = feed + 1
        }
        let start = clip.character(atOrBefore: lower)
        let end = max(start, clip.character(atOrBefore: upper))
        return clip.text[start..<end]
    }
}
