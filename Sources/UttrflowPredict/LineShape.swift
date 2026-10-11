/// What a word in a command line may be, decided by the command it belongs to and where it stands. See `Docs/predict-agent.md`.
enum ArgumentKind: Equatable, Sendable {
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
    /// A branch of the repository here, or a file here, as git's history and diff verbs take either.
    case branchOrFile
    /// Anything: a flag, a pattern, a message, a host, a word the command reads as text.
    case free
}

/// The command line as its shell reads it: the simple command the last word belongs to and what that word may be.
struct LineShape: Equatable, Sendable {
    /// The program the word is an argument of, absent when the word is the program.
    let command: String?
    /// What the word may be.
    let kind: ArgumentKind
    var isUncertain = false
    var isAliasDependent = false

    /// The shape of the word a line ends on, from the words before it.
    static func of(_ token: CompletionToken) -> LineShape { of(token, aliases: [:]) }

    /// The shape of the word a line ends on, reading a command word the shell would expand as the words it stands for.
    static func of(_ token: CompletionToken, aliases: [String: [String]]) -> LineShape {
        var words = CommandGrammar.simpleCommand(before: token.leading)
        while let first = words.first, CommandGrammar.wrappers.contains(first) {
            CommandGrammar.removeWrapper(from: &words)
        }
        words = expanded(words, aliases: aliases)
        return classified(words)
    }

    static func of(_ token: CompletionToken, metadata: AliasExpansionSnapshot) -> LineShape {
        let words = CommandGrammar.simpleCommand(before: token.leading)
        guard !words.isEmpty else { return LineShape(command: nil, kind: .program) }
        guard let aliases = metadata.words,
            let resolved = resolved(words, aliases: aliases, metadata: metadata)
        else { return LineShape(command: words.first, kind: .free, isUncertain: true) }
        var shape = classified(resolved.words)
        shape.isAliasDependent = resolved.isAliasDependent
        return shape
    }

    private static func classified(_ words: [String]) -> LineShape {
        guard let command = words.first else { return LineShape(command: nil, kind: .program) }
        let rest = words.dropFirst()
        // A bare `--` ends the options, so every word after it is an operand whatever it begins with.
        let end = rest.firstIndex(of: "--")
        let options = rest[..<(end ?? rest.endIndex)]
        let operands = end.map { rest[($0 + 1)...] } ?? []
        let arguments = options.filter { !$0.hasPrefix("-") } + operands
        return LineShape(
            command: command,
            kind: CommandGrammar.kind(
                of: command, after: arguments, flags: options.filter { $0.hasPrefix("-") },
                previous: rest.last,
                endOfOptions: end != nil))
    }
}

extension LineShape {

    private static func resolved(
        _ original: [String], aliases: [String: [String]], metadata: AliasExpansionSnapshot
    ) -> (words: [String], isAliasDependent: Bool)? {
        var words = original
        var seen: Set<String> = []
        var isAliasDependent = false
        let names = aliases.keys.sorted()
        while let first = words.first {
            if let position = names.firstIndex(of: first), metadata.uncertainAliases.contains(position) {
                return nil
            }
            if let body = aliases[first], !seen.contains(first) {
                isAliasDependent = true
                seen.insert(first)
                words = body + words.dropFirst()
                if body.first != first { continue }
            } else if aliases[first] != nil {
                return nil
            }
            guard let command = words.first else { break }
            if let position = CommandGrammar.shadowableCommands.firstIndex(of: command),
                metadata.blockedCommands.contains(position)
            {
                return nil
            }
            guard CommandGrammar.wrappers.contains(command) else { break }
            CommandGrammar.removeWrapper(from: &words)
        }
        return (words, isAliasDependent)
    }

    /// The words with a leading alias replaced by what it stands for, once for each name, as a shell does.
    private static func expanded(_ words: [String], aliases: [String: [String]]) -> [String] {
        var words = words
        var seen: Set<String> = []
        while let first = words.first, let body = aliases[first], seen.insert(first).inserted {
            words = body + words.dropFirst()
        }
        return words
    }
}

/// What the common commands take, of the kind a shell's completion keeps: data in one place, read by position.
enum CommandGrammar {
    static func removeWrapper(from words: inout [String]) {
        guard let first = words.first else { return }
        words.removeFirst()
        while let flag = words.first, flag.hasPrefix("-") {
            words.removeFirst()
            if CommandGrammar.wrapperValueFlags[first]?.contains(flag) == true, !words.isEmpty {
                words.removeFirst()
            }
        }
        while first == "env", let assignment = words.first, CommandGrammar.isAssignment(assignment) {
            words.removeFirst()
        }
    }

    /// Programs that run another command, whose own name says nothing about the arguments.
    static let wrapperValueFlags: [String: Set<String>] = [
        "sudo": ["-u", "-g", "-h", "-p", "-C", "-D", "-r", "-t", "-U", "-T"],
        "doas": ["-u", "-C"], "env": ["-u", "-S", "-P", "-C"], "nice": ["-n"], "exec": ["-a"],
    ]

    /// Programs that run another command, whose flags and option values precede that command.
    static let wrappers: Set<String> = [
        "sudo", "doas", "time", "nohup", "env", "exec", "command", "builtin", "nice", "noglob", "nocorrect",
    ]

    /// Whether a word assigns a value to a shell variable.
    static func isAssignment(_ word: String) -> Bool {
        guard let equals = word.firstIndex(of: "="), let first = word.first, first.isLetter || first == "_"
        else { return false }
        return word[..<equals].allSatisfy { $0.isLetter || $0.isNumber || $0 == "_" }
    }

    /// The operators after which a new simple command begins.
    static let separators: Set<String> = ["&&", "||", "|", ";"]

    /// Commands whose arguments are directories.
    static let directoryCommands: Set<String> = ["cd", "pushd", "rmdir"]

    /// Commands whose arguments are files or directories.
    static let fileCommands: Set<String> = [
        "ls", "cat", "less", "more", "head", "tail", "vim", "vi", "nvim", "nano", "code", "open", "source",
        ".", "rm", "cp", "mv", "chmod", "chown", "diff", "wc", "tar", "unzip", "zip", "stat", "file", "du",
        "tree", "bat", "subl", "rsync", "scp",
    ]

    /// Interpreters, whose first word is a script and whose later words are the script's own; a flag such as `-m` or `-e` names what to run instead.
    static let interpreters: Set<String> = ["python", "python3", "node", "ruby", "sh", "bash", "zsh"]

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

    static let shadowableCommands = Array(
        directoryCommands.union(fileCommands).union(interpreters).union(patternCommands)
            .union(subcommandPrograms).union(targetPrograms).union(wrappers).union(["find"])
    ).sorted()

    static func shadowed(_ names: some Sequence<String>) -> Set<Int> {
        Set(names.compactMap { shadowableCommands.firstIndex(of: $0) })
    }

    /// Whether a program's verbs are read from the project here, so its answer belongs to this directory alone.
    static func readsTheProject(_ program: String) -> Bool {
        targetPrograms.contains(program) || scriptRunners.contains(program) || program.hasSuffix(" run")
    }

    /// git's verbs that take a branch, or a path where the branch would go.
    static let gitBranchVerbs: Set<String> = [
        "checkout", "switch", "merge", "rebase", "branch", "cherry-pick",
    ]

    /// The flags of each git verb whose value is the name of a branch it creates.
    static let gitBranchCreatingFlags: [String: Set<String>] = [
        "checkout": ["-b", "-B", "--orphan"],
        "switch": ["-c", "-C", "--create", "--force-create", "--orphan"],
        "worktree": ["-b", "-B"],
    ]

    /// `git branch` flags whose value is an existing commit.
    static let gitBranchCommitFlags: Set<String> = [
        "--contains", "--no-contains", "--merged", "--no-merged", "--points-at", "-u", "--set-upstream-to",
    ]

    /// What `git branch` takes next: an existing branch to delete, rename, copy or start from, or a new name.
    static func gitBranchArgument(flags: [String], previous: String?, given: Int) -> ArgumentKind {
        if let previous, gitBranchCommitFlags.contains(previous) { return .branch }
        let deletes: Set = ["-d", "-D", "--delete", "--edit-description", "--unset-upstream"]
        if flags.contains(where: deletes.contains) { return .branch }
        // `-m old new`: the first name may be the branch renamed, the second is always new.
        let renames: Set = ["-m", "-M", "-c", "-C", "--move", "--copy"]
        if flags.contains(where: renames.contains) { return given == 0 ? .branch : .free }
        let lists: Set = ["-l", "--list", "-a", "--all", "-r", "--remotes"]
        if flags.contains(where: lists.contains) { return .free }
        // A bare `git branch name` creates it; a word after the name is where it starts.
        return given == 0 ? .free : .branch
    }

    /// git's verbs that take a branch or a bare file with equal right.
    static let gitBranchOrFileVerbs: Set<String> = ["log", "diff", "reset"]

    /// git's verbs that take paths.
    static let gitFileVerbs: Set<String> = ["add", "rm", "mv", "restore"]

    /// The words of the last simple command in the text, which is the one the next word belongs to.
    static func simpleCommand(before leading: String) -> [String] {
        // The shell grammar, not a space split, decides where a quoted or adjacent operator falls.
        guard let commands = ShellWords.commands(in: leading, home: "") else {
            return legacySimpleCommand(before: leading)
        }
        guard let last = commands.last, last.separator == .end else { return [] }
        return last.words.map(\.text)
    }

    /// The naive split used where the shell grammar refuses the text, as an unclosed quote mid-word does.
    private static func legacySimpleCommand(before leading: String) -> [String] {
        let words = leading.split(separator: " ").map(String.init)
        // An operator stands alone or hangs off the word before it, as `cd x;` does.
        guard
            let separator = words.lastIndex(where: {
                separators.contains($0) || $0.hasSuffix(";") || $0.hasSuffix("|")
            })
        else { return words }
        return Array(words[(separator + 1)...])
    }

    /// What the next word of a command is, from the positional arguments and flags before it, the word just before it, and whether a bare `--` came first.
    static func kind(
        of command: String, after arguments: [String], flags: [String] = [], previous: String? = nil,
        endOfOptions: Bool = false
    ) -> ArgumentKind {
        let flagged = !flags.isEmpty || endOfOptions
        if directoryCommands.contains(command) { return .directory }
        if interpreters.contains(command) { return arguments.isEmpty && !flagged ? .file : .free }
        if fileCommands.contains(command) { return .file }
        if patternCommands.contains(command) { return arguments.isEmpty ? .free : .file }
        if command == "find" { return arguments.isEmpty ? .directory : .free }
        if targetPrograms.contains(command) { return .subcommand(of: command) }
        guard subcommandPrograms.contains(command) else { return .free }
        guard let verb = arguments.first else { return .subcommand(of: command) }
        if command == "git" {
            // After `--` git reads only paths.
            if endOfOptions { return .file }
            // A flag that creates a branch takes a new name, which no existing branch may complete.
            if let previous, gitBranchCreatingFlags[verb]?.contains(previous) == true { return .free }
            if verb == "branch" {
                return gitBranchArgument(flags: flags, previous: previous, given: arguments.count - 1)
            }
            if gitBranchVerbs.contains(verb) { return .branch }
            if gitBranchOrFileVerbs.contains(verb) { return .branchOrFile }
            return gitFileVerbs.contains(verb) ? .file : .free
        }
        // A package manager's `run` takes the project's own scripts, which the project file names.
        if scriptRunners.contains(command), verb == "run", arguments.count == 1 {
            return .subcommand(of: "\(command) run")
        }
        return .free
    }
}
