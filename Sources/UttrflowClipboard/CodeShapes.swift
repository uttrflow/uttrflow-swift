import Foundation

/// Recognises source code and shell commands, so the row can be set in a monospaced
/// face and read the way it was written.
///
/// Evidence rather than a single test, because no single test survives contact with
/// prose. A brace appears in "use the {name} placeholder"; a semicolon appears in a
/// sentence that has a list in it; the word "class" appears in a paragraph about
/// timetables. Any one of those alone would misfile ordinary English as code, which is
/// the failure that matters here — a paragraph in a monospaced face looks broken, while
/// a snippet in a proportional one merely looks plain.
///
/// So each signal is written in a *code-shaped* form — `class` followed by a name, not
/// the bare word — and two of them are needed before anything is called code. Two
/// exceptions get there alone, and both are unmistakable: a shebang, and a line that
/// opens with a command name.
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

    /// A line that ends in a semicolon or a brace — a statement, not a sentence.
    ///
    /// The semicolon has to be at the end. Mid-line it is punctuation people use, and
    /// counting it is how a well-punctuated paragraph became code.
    private static func hasStatementEnding(_ text: String) -> Bool {
        text.split(whereSeparator: \.isNewline).contains { line in
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            return trimmed.hasSuffix(";") || trimmed.hasSuffix("{") || trimmed.hasSuffix("}")
        }
    }

    /// A continuation line that begins indented.
    ///
    /// Only lines after the first, because the first line's own indentation was trimmed
    /// off before detection ever ran. Two spaces is enough — that is a whole indentation
    /// level in Ruby, YAML and JavaScript — and a wrapped paragraph does not indent its
    /// second line.
    private static func isIndented(_ text: String) -> Bool {
        text.split(whereSeparator: \.isNewline).dropFirst().contains { line in
            line.hasPrefix("\t") || line.hasPrefix("  ")
        }
    }

    /// Something being declared: a function with brackets after its name, a type with a
    /// name after its keyword, a binding with a value after it, an import with a module.
    nonisolated(unsafe) private static let declaration =
        #/
        \b(?: func | function | def | fn | sub )\s+\w+\s*\(
        | \b(?: class | struct | enum | interface | trait | protocol | actor )\s+\w+
        | \b(?: let | var | const | val )\s+\w+\s*[:=]
        | \b(?: public | private | internal | fileprivate | static | async | await )\s+\w
        | ^\s*(?: import | from | package | using | require | \#include | \#import )\s+\S
        /#
        .anchorsMatchLineEndings()

    /// Control flow, counted apart from declarations because the two are independent
    /// evidence: three lines that bind values and then return one carry a declaration
    /// and a `return`, and neither would reach the threshold if they were the same
    /// signal. Each is written so that it cannot match the English word — a bracket
    /// after the keyword, or the keyword opening a line of its own.
    nonisolated(unsafe) private static let controlFlow =
        #/
        \b(?: if | for | while | switch | catch | foreach )\s*\(
        | ^\s*(?: return | throw | break | continue | yield | else | elif | endif )\b
        /#
        .anchorsMatchLineEndings()

    /// Operators that only ever occur in code. Assignment and comparison are left out
    /// deliberately: `=` appears in prose about equations, and `==` is rare enough in
    /// English that the other members carry the signal without it.
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

    /// A clip that opens by importing something.
    ///
    /// `import Foundation` carries no punctuation at all, so a score can never reach two
    /// on it, and a file's first two lines are one of the most ordinary things anybody
    /// copies. The keyword must be the very first thing in the clip and the line must end
    /// straight after the module name, which is what keeps English out: "import duties on
    /// Foundation goods" has a sentence after the name and does not match.
    nonisolated(unsafe) private static let importHeader =
        #/
        ^(?: import | from | package | using | require | \#include | \#import )
        \s+ ["'<]? [\w.:/*-]+ [">']? ;?$
        /#
        .anchorsMatchLineEndings()

    private static func isImportHeader(_ text: String) -> Bool {
        String(text.prefix(while: { !$0.isNewline })).wholeMatch(of: importHeader) != nil
    }

    /// Whether a one-line clip is a command, or a pipeline of them.
    ///
    /// A one-line shell command is the case a score cannot reach: `brew install jq` has
    /// no braces, no semicolon, no brackets and no indentation, and it is unambiguously
    /// something to be set in a monospaced face. The command name is the only signal
    /// there is, so it is allowed to be sufficient on its own.
    ///
    /// Restricted to a single line, and matched case-sensitively, because the list is
    /// the risky part: an English sentence that opens with one of these words would
    /// otherwise be code. The names kept are the ones that are not ordinary English —
    /// `find`, `make`, `open`, `cat`, `echo`, `go` and `source` were all dropped for
    /// exactly that reason, and are picked up by the general signals or by a neighbour
    /// in a pipeline when they appear in real code.
    ///
    /// Every stage of a pipeline is looked at, not just the first, because a pipeline is
    /// a sequence of commands and recognising any one of them settles the whole line.
    /// That is what saves `cat log.txt | grep error`, whose first word had to be dropped
    /// from the list and whose second could safely stay on it.
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
