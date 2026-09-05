/// What a word in a command line may be, decided by the command it belongs to and where it stands. See `Docs/predict-agent.md`, A1.
public enum ArgumentKind: Equatable, Sendable {
    /// The command itself: a program on the path or an alias.
    case program
    /// One of the verbs a program takes, as git's subcommands, make's targets and a project's scripts are.
    case subcommand(of: String)
    /// A directory here or under a path from here.
    case directory
    /// A file or a directory here or under a path from here.
    case file
    /// A branch of the repository here.
    case branch
    /// Anything: a flag, a pattern, a message, a host, a word the command reads as text.
    case free
}

/// The command line as its shell reads it: the simple command the last word belongs to and what that word may be.
public struct LineShape: Equatable, Sendable {
    /// The program the word is an argument of, absent when the word is the program.
    public let command: String?
    /// What the word may be.
    public let kind: ArgumentKind

    /// The shape of the word a line ends on, from the words before it.
    static func of(_ token: CompletionToken) -> LineShape {
        var words = CommandGrammar.simpleCommand(before: token.leading)
        while let first = words.first, CommandGrammar.wrappers.contains(first) {
            words.removeFirst()
            // A wrapper's own flags belong to it, not to the command it runs.
            while let flag = words.first, flag.hasPrefix("-") { words.removeFirst() }
        }
        guard let command = words.first else { return LineShape(command: nil, kind: .program) }
        let arguments = words.dropFirst().filter { !$0.hasPrefix("-") }
        return LineShape(command: command, kind: CommandGrammar.kind(of: command, after: Array(arguments)))
    }
}

/// What the common commands take, of the kind a shell's completion keeps: data in one place, read by position.
enum CommandGrammar {
    /// Programs that run another command, whose own name says nothing about the arguments.
    static let wrappers: Set<String> = ["sudo", "time", "nohup", "env", "exec", "command", "builtin", "nice"]

    /// The operators after which a new simple command begins.
    static let separators: Set<String> = ["&&", "||", "|", ";"]

    /// Commands whose arguments are directories.
    static let directoryCommands: Set<String> = ["cd", "pushd", "rmdir"]

    /// Commands whose arguments are files or directories.
    static let fileCommands: Set<String> = [
        "ls", "cat", "less", "more", "head", "tail", "vim", "vi", "nvim", "nano", "code", "open", "source",
        ".", "rm", "cp", "mv", "chmod", "chown", "diff", "wc", "tar", "unzip", "zip", "python", "python3",
        "node", "ruby", "sh", "bash", "zsh", "stat", "file", "du", "tree", "bat", "subl", "rsync", "scp",
    ]

    /// Commands that take a pattern first and files after it.
    static let patternCommands: Set<String> = ["grep", "rg", "ag", "egrep", "fgrep"]

    /// Programs whose first argument is one of their own verbs.
    static let subcommandPrograms: Set<String> = [
        "git", "docker", "kubectl", "npm", "yarn", "pnpm", "bun", "brew", "cargo", "gh", "swift", "pip",
        "pip3", "poetry", "terraform", "aws", "gcloud", "helm", "go", "deno", "systemctl", "make", "just",
    ]

    /// Programs whose every argument is a target they declare.
    static let targetPrograms: Set<String> = ["make", "just"]

    /// Package managers whose `run` verb takes a script the project declares.
    static let scriptRunners: Set<String> = ["npm", "yarn", "pnpm", "bun"]

    /// git's verbs that take a branch, or a path where the branch would go.
    static let gitBranchVerbs: Set<String> = [
        "checkout", "switch", "merge", "rebase", "branch", "cherry-pick", "log", "diff", "reset",
    ]

    /// git's verbs that take paths.
    static let gitFileVerbs: Set<String> = ["add", "rm", "mv", "restore"]

    /// The words of the last simple command in the text, which is the one the next word belongs to.
    static func simpleCommand(before leading: String) -> [String] {
        let words = leading.split(separator: " ").map(String.init)
        // An operator stands alone or hangs off the word before it, as `cd x;` does.
        guard
            let separator = words.lastIndex(where: {
                separators.contains($0) || $0.hasSuffix(";") || $0.hasSuffix("|")
            })
        else { return words }
        return Array(words[(separator + 1)...])
    }

    /// What the next word of a command is, after the positional arguments already given.
    static func kind(of command: String, after arguments: [String]) -> ArgumentKind {
        if directoryCommands.contains(command) { return .directory }
        if fileCommands.contains(command) { return .file }
        if patternCommands.contains(command) { return arguments.isEmpty ? .free : .file }
        if command == "find" { return arguments.isEmpty ? .directory : .free }
        if targetPrograms.contains(command) { return .subcommand(of: command) }
        guard subcommandPrograms.contains(command) else { return .free }
        guard let verb = arguments.first else { return .subcommand(of: command) }
        if command == "git" {
            if gitBranchVerbs.contains(verb) { return .branch }
            return gitFileVerbs.contains(verb) ? .file : .free
        }
        // A package manager's `run` takes the project's own scripts, which the project file names.
        if scriptRunners.contains(command), verb == "run", arguments.count == 1 {
            return .subcommand(of: "\(command) run")
        }
        return .free
    }
}
