/// Whether a terminal line names only what exists from where the terminal sits, decided by stats and small reads and never by running anything. See `Docs/predict-terminal-paths.md`.
public struct TerminalLineCheck: Sendable {
    /// The disk the line is checked against.
    let files: any FileSystemProbing

    /// A check against one filesystem.
    public init(files: any FileSystemProbing) {
        self.files = files
    }

    /// Where a command leaves the shell: where it was, in a directory, or somewhere this check cannot follow.
    enum Landing: Equatable {
        case stays
        case moves(to: String)
        case lost
    }

    /// What an argument has to be for its command to take it.
    enum Requirement {
        case directory
        case file
        case anything
        case executable
    }

    /// Whether every command, path and branch the line names exists here, `scope` being the terminal's directory; a line that cannot be read without running something does not pass.
    public func allows(_ line: String, in scope: String?, aliases: Set<String> = []) -> Bool {
        guard let commands = ShellWords.commands(in: line, home: files.homeDirectory) else { return false }
        var directory = workingDirectory(scope)
        var conditional = false
        for command in commands {
            guard let landing = judge(command, from: directory, aliases: aliases) else { return false }
            switch landing {
            case .stays:
                break
            case .moves(let target):
                // Only a `cd` the next command surely follows moves it; after `||`, `|` or `&` where it runs is unknown.
                let followed = !conditional && [.and, .sequence, .end].contains(command.separator)
                directory = followed ? target : nil
            case .lost:
                directory = nil
            }
            switch command.separator {
            case .or: conditional = true
            case .sequence, .background: conditional = false
            case .and, .pipe, .end: break
            }
        }
        return true
    }

    /// The terminal's directory when it names one that exists, since a title or a stale document is no directory to resolve from.
    func workingDirectory(_ scope: String?) -> String? {
        guard var path = scope?.trimmingCharacters(in: .whitespacesAndNewlines), !path.isEmpty else {
            return nil
        }
        if path == "~" || path.hasPrefix("~/") { path = files.homeDirectory + path.dropFirst() }
        guard path.hasPrefix("/") else { return nil }
        let normalized = TerminalPath.normalized(path)
        return files.kind(atPath: normalized) == .directory ? normalized : nil
    }

    /// Where one simple command leaves the shell, absent when anything it names is not here.
    func judge(_ command: SimpleCommand, from directory: String?, aliases: Set<String>) -> Landing? {
        guard command.inputs.allSatisfy({ exists($0, as: .file, from: directory) }) else { return nil }
        var words = command.words[...]
        while let first = words.first, Self.isAssignment(first.text) { words.removeFirst() }
        words = Self.unwrapped(words)
        guard let head = words.first else { return .stays }
        guard isCommand(head, from: directory, aliases: aliases) else { return nil }
        return landing(of: TerminalPath.lastName(of: head.text), Array(words.dropFirst()), from: directory)
    }

    /// Whether a word names something the shell can run: a builtin, an alias, a program found on the search path, or an executable file by its path.
    func isCommand(_ head: ShellWord, from directory: String?, aliases: Set<String>) -> Bool {
        guard !head.isUnresolved, !head.text.isEmpty else { return false }
        if head.text.contains("/") { return exists(head, as: .executable, from: directory) }
        if Self.builtins.contains(head.text) || aliases.contains(head.text) { return true }
        return files.searchPaths.contains {
            files.kind(atPath: TerminalPath.joined($0, head.text)) == .file(executable: true)
        }
    }

    /// Whether a word names a path of the required kind, relative words only where the directory is known.
    func exists(_ word: ShellWord, as requirement: Requirement, from directory: String?) -> Bool {
        guard !word.isUnresolved, !word.text.isEmpty, word.text.hasPrefix("/") || directory != nil else {
            return false
        }
        let kind = files.kind(atPath: TerminalPath.resolved(word.text, from: directory ?? "/"))
        // A trailing slash asks for a directory whatever the command would otherwise take.
        switch (word.text.hasSuffix("/") ? .directory : requirement, kind) {
        case (.directory, .directory), (.anything, .directory), (.anything, .file), (.file, .file),
            (.executable, .file(executable: true)):
            return true
        default:
            return false
        }
    }

    /// Whether every word names a path of the required kind, `-` standing for the standard input.
    func allExist(
        _ words: some Collection<ShellWord>, as requirement: Requirement, from directory: String?
    ) -> Bool {
        words.allSatisfy { $0.text == "-" || exists($0, as: requirement, from: directory) }
    }

    /// Where a command of this name leaves the shell once its arguments are checked, absent when one is not here.
    func landing(of name: String, _ arguments: [ShellWord], from directory: String?) -> Landing? {
        let flags = Self.valueFlags[name] ?? []
        let operands = Self.operands(
            of: arguments, valueFlags: flags, plusIsFlag: Self.editors.contains(name))
        switch name {
        case "cd", "pushd":
            return changeDirectory(arguments, from: directory)
        case "popd":
            return .lost
        case _ where Self.fileReaders.contains(name):
            return allExist(operands, as: .file, from: directory) ? .stays : nil
        case _ where Self.pathTakers.contains(name):
            // `open` also takes an address, which is no path on this disk.
            let paths = operands.filter { !(name == "open" && $0.text.contains("://")) }
            return allExist(paths, as: .anything, from: directory) ? .stays : nil
        case "cp", "mv":
            return allExist(
                operands.count > 1 ? operands.dropLast() : operands[...], as: .anything, from: directory)
                ? .stays : nil
        case "chmod", "chown", "chgrp":
            return allExist(operands.dropFirst(), as: .anything, from: directory) ? .stays : nil
        case _ where Self.interpreters.contains(name):
            guard let script = arguments.first, !script.text.hasPrefix("-") else { return .stays }
            return exists(script, as: .file, from: directory) ? .stays : nil
        case _ where Self.searchers.contains(name):
            return searched(arguments, from: directory)
        case "git":
            return git(arguments, from: directory)
        default:
            return .stays
        }
    }

    /// Where `cd` or `pushd` leaves the shell: home with no argument, a directory that exists, or nowhere to follow for the directory stack.
    func changeDirectory(_ arguments: [ShellWord], from directory: String?) -> Landing? {
        let stackEntry = { (text: String) in
            text.count > 1 && (text.hasPrefix("-") || text.hasPrefix("+"))
                && text.dropFirst().allSatisfy(\.isNumber)
        }
        if arguments.contains(where: { stackEntry($0.text) }) {
            return .lost
        }
        let operands = Self.operands(of: arguments, valueFlags: [], plusIsFlag: false)
        guard operands.count <= 1 else { return nil }
        guard let target = operands.first else {
            return .moves(to: TerminalPath.normalized(files.homeDirectory))
        }
        if target.text == "-" { return .lost }
        guard exists(target, as: .directory, from: directory) else { return nil }
        return .moves(to: TerminalPath.resolved(target.text, from: directory ?? "/"))
    }

    /// A search's files, which follow the pattern unless a flag gave the pattern.
    func searched(_ arguments: [ShellWord], from directory: String?) -> Landing? {
        let patternFlags: Set = ["-e", "-f", "--regexp", "--file"]
        let patternGiven = arguments.contains {
            patternFlags.contains($0.text) || $0.text.hasPrefix("--regexp=") || $0.text.hasPrefix("--file=")
        }
        let operands = Self.operands(of: arguments, valueFlags: Self.searchValueFlags, plusIsFlag: false)
        return allExist(patternGiven ? operands[...] : operands.dropFirst(), as: .anything, from: directory)
            ? .stays : nil
    }

    /// git's verbs that name branches and paths, checked against the repository's refs and the disk; any other verb stands.
    func git(_ arguments: [ShellWord], from directory: String?) -> Landing? {
        var rest = arguments[...]
        var elsewhere = false
        while let first = rest.first, first.text.hasPrefix("-") {
            rest.removeFirst()
            if first.text.hasPrefix("--git-dir") || first.text.hasPrefix("--work-tree") { elsewhere = true }
            if first.text == "-C" { elsewhere = true }
            if first.text == "-C" || first.text == "-c" { _ = rest.popFirst() }
        }
        guard let verb = rest.first, Self.gitVerbs.contains(verb.text) else { return .stays }
        let tail = Array(rest.dropFirst())
        guard !elsewhere, let directory, let repository = GitRepository.holding(directory, files: files)
        else {
            return nil
        }
        switch verb.text {
        case "checkout":
            return checkout(tail, in: repository, from: directory) ? .stays : nil
        case "switch":
            return switched(tail, in: repository) ? .stays : nil
        default:
            let operands = Self.operands(of: tail, valueFlags: Self.gitPathValueFlags, plusIsFlag: false)
            let paths = verb.text == "mv" && operands.count > 1 ? operands.dropLast() : operands[...]
            return allExist(paths, as: .anything, from: directory) ? .stays : nil
        }
    }

    /// Whether `git checkout` names a commit that exists or paths that do, and a new branch's start point where it gives one.
    func checkout(_ arguments: [ShellWord], in repository: GitRepository, from directory: String) -> Bool {
        var names: [ShellWord] = []
        var paths: [ShellWord] = []
        var creates = false
        var afterDashes = false
        var skipNext = false
        for word in arguments {
            if skipNext {
                skipNext = false
            } else if afterDashes {
                paths.append(word)
            } else if word.text == "--" {
                afterDashes = true
            } else if ["-b", "-B", "--orphan"].contains(word.text) {
                creates = true
                skipNext = true
            } else if word.text == "-" || !word.text.hasPrefix("-") {
                names.append(word)
            }
        }
        guard allExist(paths, as: .anything, from: directory) else { return false }
        guard let first = names.first else { return true }
        guard !first.isUnresolved else { return false }
        if !creates, first.text == "-" { return names.count == 1 }
        if repository.hasCommit(named: first.text)
            || (!creates && repository.hasRemoteBranch(named: first.text))
        {
            return allExist(names.dropFirst(), as: .anything, from: directory)
        }
        // With no commit named, every name is a file to restore from the index.
        return !creates && paths.isEmpty && allExist(names, as: .anything, from: directory)
    }

    /// Whether `git switch` names a branch that exists, or a start point that does for one it creates.
    func switched(_ arguments: [ShellWord], in repository: GitRepository) -> Bool {
        var names: [ShellWord] = []
        var creates = false
        var detaches = false
        var skipNext = false
        for word in arguments {
            if skipNext {
                skipNext = false
            } else if ["-c", "-C", "--create", "--force-create", "--orphan"].contains(word.text) {
                creates = true
                skipNext = true
            } else if word.text == "-d" || word.text == "--detach" {
                detaches = true
            } else if word.text == "-" || !word.text.hasPrefix("-") {
                names.append(word)
            }
        }
        guard let first = names.first else { return true }
        guard names.count == 1, !first.isUnresolved else { return false }
        if first.text == "-" { return !creates }
        if creates || detaches {
            return repository.hasCommit(named: first.text) || repository.hasRemoteBranch(named: first.text)
        }
        return repository.hasBranch(first.text) || repository.hasRemoteBranch(named: first.text)
    }

    /// The words that are not flags or a flag's value, everything after `--` included.
    static func operands(of arguments: [ShellWord], valueFlags: Set<String>, plusIsFlag: Bool) -> [ShellWord]
    {
        var operands: [ShellWord] = []
        var afterDashes = false
        var skipNext = false
        for word in arguments {
            if skipNext {
                skipNext = false
            } else if afterDashes {
                operands.append(word)
            } else if word.text == "--" {
                afterDashes = true
            } else if word.text.count > 1, word.text.hasPrefix("-") {
                skipNext = valueFlags.contains(word.text)
            } else if !(plusIsFlag && word.text.hasPrefix("+")) {
                operands.append(word)
            }
        }
        return operands
    }

    /// Whether a word sets a variable for the command after it.
    static func isAssignment(_ text: String) -> Bool {
        guard let equals = text.firstIndex(of: "="), let first = text.first, first.isLetter || first == "_"
        else {
            return false
        }
        return text[..<equals].allSatisfy { $0.isLetter || $0.isNumber || $0 == "_" }
    }

    /// The words with every leading wrapper, its flags and their values removed, so the command it runs is what is read.
    static func unwrapped(_ words: ArraySlice<ShellWord>) -> ArraySlice<ShellWord> {
        var words = words
        while let first = words.first, !first.isUnresolved, let flags = wrappers[first.text], words.count > 1
        {
            words.removeFirst()
            while let flag = words.first, flag.text.count > 1, flag.text.hasPrefix("-") {
                words.removeFirst()
                if flags.contains(flag.text), !words.isEmpty { words.removeFirst() }
            }
            while first.text == "env", let assignment = words.first, isAssignment(assignment.text) {
                words.removeFirst()
            }
        }
        return words
    }

    /// Words that run the command after them, with the flags of theirs that take a value.
    static let wrappers: [String: Set<String>] = [
        "sudo": ["-u", "-g", "-h", "-p", "-C", "-D", "-r", "-t", "-U", "-T"], "doas": ["-u", "-C"],
        "env": ["-u", "-S", "-P"], "nice": ["-n"], "nohup": [], "time": [], "command": [], "builtin": [],
        "exec": ["-a"], "noglob": [], "nocorrect": [],
    ]

    /// Commands the shell itself answers, which no search path holds; `eval` is left out, since what it runs is text.
    static let builtins: Set<String> = [
        "cd", "pushd", "popd", "dirs", "source", ".", "echo", "printf", "print", "export", "unset", "alias",
        "unalias", "exit", "logout", "history", "fc", "type", "which", "where", "whence", "hash", "rehash",
        "read", "set", "setopt", "unsetopt", "bindkey", "jobs", "fg", "bg", "wait", "kill", "disown", "true",
        "false", "test", "[", "[[", "pwd", "ulimit", "umask", "trap", "shift", "local", "typeset", "declare",
        "let", "return", "break", "continue", "times", "autoload", "zmodload", "functions", "emulate",
        "noglob",
        "getopts", "readonly", "integer", "float", "zle", "zstyle", "exec", "command", "builtin", "time",
        "nocorrect", "compdef", "shopt", "help",
    ]

    /// Commands whose every operand is a file they read.
    static let fileReaders: Set<String> = ["cat", "less", "more", "head", "tail", "bat", "wc", "source", "."]

    /// Commands whose every operand is a file or a directory that has to exist.
    static let pathTakers: Set<String> = [
        "ls", "du", "tree", "stat", "file", "diff", "open", "rm", "rmdir", "code", "subl", "vim", "vi",
        "nvim",
        "nano", "emacs",
    ]

    /// Editors, which read a `+` word as a line to open at.
    static let editors: Set<String> = ["vim", "vi", "nvim", "nano", "emacs"]

    /// Interpreters, whose first operand is the script they run unless a flag came first.
    static let interpreters: Set<String> = [
        "python", "python3", "node", "ruby", "perl", "php", "sh", "bash", "zsh",
    ]

    /// Searches, whose first operand is the pattern and the rest files.
    static let searchers: Set<String> = ["grep", "egrep", "fgrep", "rg", "ag"]

    /// git's verbs whose operands this check reads.
    static let gitVerbs: Set<String> = ["checkout", "switch", "add", "restore", "rm", "mv"]

    /// The flags of git's path verbs that take a value.
    static let gitPathValueFlags: Set<String> = ["-s", "--source", "--pathspec-from-file", "--chmod"]

    /// The flags of a search that take a value, the pattern's among them.
    static let searchValueFlags: Set<String> = [
        "-e", "-f", "-A", "-B", "-C", "-m", "-d", "-D", "--regexp", "--file", "--context", "--after-context",
        "--before-context", "--max-count", "-g", "--glob", "-t", "--type", "-T", "--type-not", "-j",
        "--threads",
        "-M", "--max-columns",
    ]

    /// Each command's flags that take a value, so the value is not read as a path.
    static let valueFlags: [String: Set<String>] = [
        "head": ["-n", "-c"], "tail": ["-n", "-c", "-b"], "less": ["-p", "-x", "-y", "-o", "-O"],
        "bat": [
            "-l", "--language", "-H", "--highlight-line", "-r", "--line-range", "--style", "--theme", "-m",
        ],
        "du": ["-d", "-B", "-t", "-I"], "tree": ["-L", "-I", "-P", "-o", "--filelimit"],
        "stat": ["-f", "-t"],
        "open": ["-a", "-b", "-u", "--env", "--stdin", "--stdout", "--stderr"],
        "code": [
            "-g", "--goto", "-d", "--diff", "-a", "--add", "-m", "--merge", "--profile", "--user-data-dir",
        ],
        "subl": ["--command", "--project"], "diff": ["-C", "-U", "-L", "--label", "-I", "-x", "-X"],
        "vim": ["-c", "-S", "-t", "-q", "-u", "-i", "-T", "-w", "-W", "-s", "--cmd"],
        "vi": ["-c", "-S", "-t", "-q", "-u", "-i", "-T", "-w", "-W", "-s", "--cmd"],
        "nvim": ["-c", "-S", "-t", "-q", "-u", "-i", "-w", "-W", "-s", "--cmd", "--listen"],
        "nano": ["-T", "-Y", "-o", "--rcfile"], "emacs": ["-l", "--load", "-f", "--funcall", "--eval"],
    ]
}
