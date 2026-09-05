// Recognises source code and shell commands.

import Foundation

/// Recognises code by two independent code-shaped signals, or by one unmistakable one.
enum CodeShapes {
    static func matches(_ text: String) -> Bool {
        if text.hasPrefix("#!") { return true }
        if isImportHeader(text) { return true }
        if isShellCommand(text) { return true }
        return signalCount(in: text) >= 2
    }

    // MARK: - The signals

    /// How many independent hints of code the text carries, counted up to the threshold.
    private static func signalCount(in text: String) -> Int {
        [
            text.contains("{") && text.contains("}"),
            hasStatementEnding(text),
            isIndented(text),
            text.firstMatch(of: declaration) != nil,
            text.firstMatch(of: controlFlow) != nil,
            text.firstMatch(of: codeOperator) != nil,
            text.firstMatch(of: invocation) != nil,
            text.firstMatch(of: commentLine) != nil,
            text.firstMatch(of: query) != nil,
            text.firstMatch(of: shellFragment) != nil,
        ]
        .count(where: { $0 })
    }

    /// A line that ends in a semicolon or a brace; mid-line, a semicolon is punctuation people use.
    private static func hasStatementEnding(_ text: String) -> Bool {
        text.split(whereSeparator: \.isNewline).contains { line in
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            return trimmed.hasSuffix(";") || trimmed.hasSuffix("{") || trimmed.hasSuffix("}")
        }
    }

    /// A continuation line that begins indented; a wrapped paragraph does not indent its second line.
    private static func isIndented(_ text: String) -> Bool {
        text.split(whereSeparator: \.isNewline).dropFirst().contains { line in
            line.hasPrefix("\t") || line.hasPrefix("  ")
        }
    }

    /// Something being declared: a function, a type, a binding with a value, an import with a module.
    nonisolated(unsafe) private static let declaration =
        #/
        \b(?: func | function | def | fn | sub )\s+\w+\s*\(
        | \b(?: class | struct | enum | interface | trait | protocol | actor )\s+\w+
        | \b(?: let | var | const | val )\s+\w+\s*[:=]
        | \b(?: public | private | internal | fileprivate | static | async | await )\s+\w
        | ^\s*(?: import | from | package | using | require | \#include | \#import )\s+\S
        /#
        .anchorsMatchLineEndings()

    /// Control flow, independent of declarations, written so it cannot match the English word.
    nonisolated(unsafe) private static let controlFlow =
        #/
        \b(?: if | for | while | switch | catch | foreach )\s*\(
        | ^\s*(?: return | throw | break | continue | yield | else | elif | endif )\b
        /#
        .anchorsMatchLineEndings()

    /// Operators that only occur in code; `=` and `==` are left out because prose about equations has them.
    nonisolated(unsafe) private static let codeOperator = #/=>|->|::|!==|===|&&|\|\||\+=|-=|\+\+|!=/#

    /// A name immediately followed by an opening bracket: a call, or a definition.
    nonisolated(unsafe) private static let invocation = #/\w+\((?:\)|[^\s)])/#

    /// A line that opens with a comment marker in one of the usual spellings.
    nonisolated(unsafe) private static let commentLine = #/^\s*(?://|/\*|\*\s|\#\s|--\s)/#
        .anchorsMatchLineEndings()

    /// SQL, which has none of the punctuation the other signals look for.
    nonisolated(unsafe) private static let query =
        #/(?i)^\s*(?:select|insert\s+into|update|delete\s+from|create\s+table|alter\s+table|drop\s+table)\s+/#
        .anchorsMatchLineEndings()

    /// Shell punctuation: a pipe, a chained command, a substitution, a redirect, a flag.
    nonisolated(unsafe) private static let shellFragment = #/\s\|\s|\&\&|\$\(|\s>>?\s|\s--?[a-zA-Z]/#

    // MARK: - The two that stand alone

    /// A clip that opens by importing something, which carries no punctuation for a score to reach.
    nonisolated(unsafe) private static let importHeader =
        #/
        ^(?: import | from | package | using | require | \#include | \#import )
        \s+ ["'<]? [\w.:/*-]+ [">']? ;?$
        /#
        .anchorsMatchLineEndings()

    private static func isImportHeader(_ text: String) -> Bool {
        String(text.prefix(while: { !$0.isNewline })).wholeMatch(of: importHeader) != nil
    }

    /// Whether a one-line clip is a command or a pipeline; the command name is the only signal there is.
    private static func isShellCommand(_ text: String) -> Bool {
        guard !text.contains(where: \.isNewline) else { return false }
        if text.hasPrefix("$ ") || text.hasPrefix("./") { return true }
        return text.split(whereSeparator: { "|&;".contains($0) })
            .compactMap { $0.split(whereSeparator: \.isWhitespace).first }
            .contains { commands.contains(String($0)) }
    }

    private static let commands: Set<String> = [
        "sudo", "git", "npm", "npx", "yarn", "pnpm", "brew", "docker", "kubectl", "curl",
        "wget", "ssh", "scp", "rsync", "chmod", "chown", "mkdir", "rmdir", "ln", "ls",
        "cd", "rm", "mv", "cp", "grep", "awk", "sed", "tar", "ps", "kill", "killall",
        "launchctl", "systemctl", "defaults", "codesign", "xcrun", "xcodebuild", "swift",
        "swiftc", "cargo", "rustc", "pip", "pip3", "python3", "node", "deno", "bun",
        "apt", "apt-get", "yum", "dnf", "pacman", "terraform", "aws", "gcloud", "psql",
    ]
}
