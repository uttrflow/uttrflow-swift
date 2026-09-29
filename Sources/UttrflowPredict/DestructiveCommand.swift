/// Recognises command lines that destroy data or the machine, so they are never learned or auto-offered.
public enum DestructiveCommand {
    /// Whether taking this line as a completion could do irreversible harm, judged conservatively.
    public static func matches(_ text: String, failClosedOnUnresolved: Bool = false) -> Bool {
        // A fork bomb carries no ordinary tokens, so it is matched on the whitespace-stripped text.
        if text.lowercased().filter({ !$0.isWhitespace }).contains(":(){:|:&};:") { return true }
        let lower = text.lowercased()
        if lower.contains("of=/dev/") || lower.contains("/dev/sd") || lower.contains("/dev/disk")
            || lower.contains("/dev/rdisk")
        {
            return true
        }
        guard let clauses = ShellWords.commands(in: text, home: "") else { return failClosedOnUnresolved }
        return clauses.contains { clause in
            if failClosedOnUnresolved,
                (clause.words + clause.inputs).contains(where: \.isUnresolved)
            {
                return true
            }
            if clause.overwrites.contains(where: { !harmlessOutputs.contains($0.text) }) { return true }
            return destroys(clause.words, failClosedOnUnresolved: failClosedOnUnresolved)
        }
    }

    /// Devices a `>` writes to without emptying any file.
    private static let harmlessOutputs: Set<String> = [
        "/dev/null", "/dev/stdout", "/dev/stderr", "/dev/tty", "/dev/fd/1", "/dev/fd/2",
    ]

    /// Flags that make rsync delete files, in the destination or at the source.
    private static func rsyncDeletes(_ flag: String) -> Bool {
        flag == "--del" || flag.hasPrefix("--delete") || flag == "--remove-source-files"
            || flag == "--remove-sent-files"
    }

    /// A word that runs the command after it: its flags that take a value, and how many plain words of its own precede the command.
    private struct Wrapper {
        let valued: Set<String>
        var operands = 0
    }

    /// Words that run the command after them, each read past before the command is judged.
    private static let wrappers: [String: Wrapper] = [
        "sudo": Wrapper(valued: ["-u", "-g", "-h", "-p", "-C", "-D", "-r", "-t", "-U", "-T"]),
        "doas": Wrapper(valued: ["-u", "-C"]), "env": Wrapper(valued: ["-u", "-S", "-P"]),
        "nice": Wrapper(valued: ["-n"]), "nohup": Wrapper(valued: []), "time": Wrapper(valued: []),
        "command": Wrapper(valued: []), "builtin": Wrapper(valued: []), "exec": Wrapper(valued: ["-a"]),
        "noglob": Wrapper(valued: []), "nocorrect": Wrapper(valued: []),
        "xargs": Wrapper(valued: ["-I", "-J", "-L", "-n", "-P", "-s", "-E", "-R", "-S", "-d"]),
        "timeout": Wrapper(valued: ["-s", "--signal", "-k", "--kill-after"], operands: 1),
        "gtimeout": Wrapper(valued: ["-s", "--signal", "-k", "--kill-after"], operands: 1),
        "caffeinate": Wrapper(valued: ["-t", "-w"]), "watch": Wrapper(valued: ["-n", "--interval"]),
        "ionice": Wrapper(valued: ["-c", "-n", "-p", "-P", "-u"]), "chronic": Wrapper(valued: []),
        "unbuffer": Wrapper(valued: []), "stdbuf": Wrapper(valued: ["-i", "-o", "-e"]),
        "taskpolicy": Wrapper(valued: ["-c", "-d", "-g", "-t", "-l"]), "arch": Wrapper(valued: ["-arch"]),
        "flock": Wrapper(valued: ["-w", "--timeout", "-E", "--conflict-exit-code"], operands: 1),
        "chroot": Wrapper(valued: ["-u", "-g", "-G"], operands: 1), "pkexec": Wrapper(valued: ["--user"]),
    ]

    /// Shell reserved words that stand in front of the command a clause runs, as a loop's `do` and an `if`'s `then` do.
    private static let reservedWords: Set<String> = [
        "do", "then", "else", "elif", "if", "while", "until", "!",
    ]

    /// Programs that destroy whatever they are pointed at.
    private static let destroyers: Set<String> = [
        "rm", "rmdir", "shred", "srm", "unlink", "dd", "mkfs", "fdisk", "parted", "shutdown", "reboot",
        "halt",
        "poweroff", "dropdb", "dropuser",
    ]

    private enum Command {
        case none
        case unresolved
        case named(String, [String])
    }

    /// The program a parsed clause runs, read past assignments, reserved words and every wrapper.
    private static func command(in tokens: [ShellWord]) -> Command {
        var rest = tokens[...]
        while let first = rest.first {
            guard !first.isUnresolved else { return .unresolved }
            let name = programName(first.text)
            if TerminalLineCheck.isAssignment(first.text) || reservedWords.contains(name), rest.count > 1 {
                rest.removeFirst()
                continue
            }
            guard let wrapper = wrappers[name], rest.count > 1 else {
                return .named(name, Array(rest.dropFirst().map(\.text)))
            }
            rest.removeFirst()
            while let flag = rest.first, flag.text.count > 1, flag.text.hasPrefix("-") {
                guard !flag.isUnresolved else { return .unresolved }
                rest.removeFirst()
                if wrapper.valued.contains(flag.text), !rest.isEmpty { rest.removeFirst() }
            }
            rest = rest.dropFirst(wrapper.operands)
        }
        return .none
    }

    /// A tool whose verbs follow its option flags: the flags that take a value, and which verbs delete for good.
    private struct VerbTool: Sendable {
        let valued: Set<String>
        /// Whether the tool's positional words, then all its arguments, both lowercased, name an irreversible deletion.
        let destroys: @Sendable (_ positionals: [String], _ arguments: [String]) -> Bool
    }

    /// Cluster, cloud, hosting, container and system tools, each judged by the verbs its option flags leave.
    private static let verbTools: [String: VerbTool] = [
        "kubectl": VerbTool(
            valued: [
                "-n", "--namespace", "--context", "--kubeconfig", "--cluster", "--user", "-s", "--server",
                "--token", "--as", "--as-group", "--as-uid", "--request-timeout", "-v", "--v", "--cache-dir",
                "--certificate-authority", "--client-certificate", "--client-key", "--tls-server-name",
                "--password", "--username", "--profile", "--profile-output", "--log-file", "--vmodule",
            ],
            destroys: { positionals, _ in positionals.first == "delete" }),
        "gh": VerbTool(
            valued: [
                "-r", "--repo", "--hostname", "-x", "--method", "-f", "--field", "--raw-field", "-h",
                "--header",
                "-q", "--jq", "-t", "--template", "--input", "-p", "--preview", "--cache",
            ],
            destroys: { positionals, arguments in
                positionals.dropFirst().first?.hasPrefix("delete") == true
                    || (positionals.first == "api" && requestsDelete(arguments))
            }),
        "aws": VerbTool(
            valued: [
                "--profile", "--region", "--output", "--endpoint-url", "--query", "--cli-read-timeout",
                "--cli-connect-timeout", "--ca-bundle", "--color", "--cli-binary-format", "--exclude",
                "--include",
            ],
            destroys: { positionals, arguments in
                guard let service = positionals.first, let operation = positionals.dropFirst().first else {
                    return false
                }
                if service == "s3" {
                    return operation == "rm" || operation == "rb"
                        || (operation == "sync" && arguments.contains("--delete"))
                }
                return operation.hasPrefix("delete-") || operation.hasPrefix("terminate-")
            }),
        "gcloud": VerbTool(
            valued: [
                "--project", "--account", "--configuration", "--format", "--verbosity", "--zone", "--region",
                "--impersonate-service-account", "--billing-project", "--filter", "--flatten",
            ],
            destroys: { positionals, _ in positionals.contains("delete") }),
        "az": VerbTool(
            valued: [
                "--subscription", "-g", "--resource-group", "-n", "--name", "-o", "--output", "--query", "-l",
                "--location",
            ],
            destroys: { positionals, _ in positionals.contains("delete") }),
        "gsutil": VerbTool(
            valued: ["-o", "-h", "-u"],
            destroys: { positionals, arguments in
                positionals.first == "rm" || positionals.first == "rb"
                    || (positionals.first == "rsync" && arguments.contains("-d"))
            }),
        "docker": containerTool, "podman": containerTool,
        "docker-compose": VerbTool(valued: composeValued, destroys: composeDownDeletesVolumes),
        "podman-compose": VerbTool(valued: composeValued, destroys: composeDownDeletesVolumes),
        "helm": VerbTool(
            valued: [
                "-n", "--namespace", "--kube-context", "--kubeconfig", "--kube-apiserver", "--kube-as-user",
                "--kube-as-group", "--kube-token", "--kube-ca-file", "--kube-tls-server-name",
                "--registry-config", "--repository-cache", "--repository-config", "--burst-limit", "--qps",
            ],
            destroys: { positionals, _ in ["uninstall", "delete", "del", "un"].contains(positionals.first) }),
        "tmutil": VerbTool(
            valued: [],
            destroys: { positionals, _ in
                ["delete", "deletelocalsnapshots", "thinlocalsnapshots", "deleteinprogress"].contains(
                    positionals.first)
            }),
        "launchctl": VerbTool(
            valued: [],
            destroys: { positionals, _ in ["remove", "bootout", "unload"].contains(positionals.first) }),
    ]

    /// Docker and Podman, which destroy by pruning, by removing a volume, or by forcing a container or an image out.
    private static let containerTool = VerbTool(
        valued: [
            "-H", "--host", "-c", "--context", "--config", "-l", "--log-level", "--tlscacert", "--tlscert",
            "--tlskey", "--url", "--connection", "--root", "--runroot", "--storage-driver", "--identity",
        ].reduce(into: Set<String>()) { $0.insert($1.lowercased()) },
        destroys: { positionals, arguments in
            if arguments.contains("prune") { return true }
            let object = positionals.dropFirst().first
            switch positionals.first {
            case "volume": return object == "rm" || object == "remove"
            case "rm", "rmi": return forces(arguments)
            case "container", "image": return (object == "rm" || object == "remove") && forces(arguments)
            case "compose":
                guard let compose = arguments.firstIndex(of: "compose") else { return false }
                let rest = Array(arguments[(compose + 1)...])
                return composeDownDeletesVolumes(
                    DestructiveCommand.positionals(rest, valued: composeValued), rest)
            default: return false
            }
        })

    /// Compose's own flags that take a value, read past before its verb.
    private static let composeValued: Set<String> = [
        "-f", "--file", "-p", "--project-name", "--env-file", "--profile", "--project-directory", "--ansi",
        "--parallel", "--progress",
    ]

    /// Whether a compose command takes its services down and deletes their named volumes with them.
    private static func composeDownDeletesVolumes(
        _ positionals: [String], _ arguments: [String]
    ) -> Bool {
        positionals.first == "down"
            && arguments.contains { $0 == "--volumes" || shortFlags($0, include: "v", valuesAfter: ["t"]) }
    }

    /// Whether lowercased arguments force the removal, alone or in a cluster of short flags.
    private static func forces(_ arguments: [String]) -> Bool {
        arguments.contains { $0 == "--force" || shortFlags($0, include: "f", valuesAfter: []) }
    }

    /// The words a tool's option flags leave, each flag's value skipped and everything after `--` kept.
    private static func positionals(_ lowered: [String], valued: Set<String>) -> [String] {
        var found: [String] = []
        var rest = lowered[...]
        while let word = rest.popFirst() {
            if word == "--" {
                found += rest
                break
            }
            guard word.count > 1, word.hasPrefix("-") else {
                found.append(word)
                continue
            }
            if valued.contains(word), !rest.isEmpty { rest.removeFirst() }
        }
        return found
    }

    /// Whether an HTTP request's lowercased flags ask for the DELETE method.
    private static func requestsDelete(_ arguments: [String]) -> Bool {
        zip(arguments, arguments.dropFirst()).contains { flag, value in
            (flag == "-x" || flag == "--method") && value == "delete"
        } || arguments.contains { $0 == "-xdelete" || $0 == "--method=delete" }
    }

    /// A parsed command word as the program it names, lowercased.
    private static func programName(_ word: String) -> String {
        (word.split(separator: "/").last.map(String.init) ?? word).lowercased()
    }

    /// Whether one clause destroys data or the machine.
    private static func destroys(_ tokens: [ShellWord], failClosedOnUnresolved: Bool) -> Bool {
        let parsed = command(in: tokens)
        if case .unresolved = parsed { return failClosedOnUnresolved }
        guard case .named(let command, let arguments) = parsed else { return false }
        let lowered = arguments.map { $0.lowercased() }
        if destroyers.contains(command) || command.hasPrefix("mkfs.") { return true }
        if let tool = verbTools[command], tool.destroys(positionals(lowered, valued: tool.valued), lowered) {
            return true
        }
        switch command {
        case "chmod", "chown", "chgrp":
            if hasRecursiveOption(arguments) { return true }
        case "git":
            if matchesDestructiveGit(arguments) { return true }
        case "find":
            if lowered.contains("-delete") { return true }
            // The command `-exec` runs is judged as its own clause, so a wrapper in front of it is read past.
            if let exec = tokens.firstIndex(where: { ["-exec", "-execdir"].contains($0.text.lowercased()) }),
                destroys(Array(tokens[(exec + 1)...]), failClosedOnUnresolved: failClosedOnUnresolved)
            {
                return true
            }
        case "diskutil":
            let verbs = [
                "erase", "zerodisk", "randomdisk", "securerase", "partitiondisk", "reformat", "deletevolume",
                "deletecontainer",
            ]
            if lowered.contains(where: { word in verbs.contains(where: word.hasPrefix) }) { return true }
        case "terraform", "tofu":
            if lowered.contains("destroy") || lowered.contains("-destroy") { return true }
        case "redis-cli", "valkey-cli", "keydb-cli":
            if lowered.contains(where: { $0 == "flushall" || $0 == "flushdb" }) { return true }
        case "mongo", "mongosh":
            let script = lowered.joined(separator: " ")
            if mongoDeletions.contains(where: script.contains) { return true }
        case "crontab":
            if lowered.contains("-r") { return true }
        case "sh", "bash", "zsh", "dash", "ksh", "fish":
            if let script = shellScript(arguments),
                matches(script, failClosedOnUnresolved: failClosedOnUnresolved)
            {
                return true
            }
        case "mv", "cp":
            if lowered.last == "/dev/null" { return true }
        case "rsync":
            if lowered.contains(where: rsyncDeletes) { return true }
        case "tee":
            // Without `-a` tee empties every file it names, as `>` does.
            let appends =
                lowered.contains("--append")
                || lowered.contains { shortFlags($0, include: "a", valuesAfter: []) }
            if !appends, lowered.contains(where: { !$0.hasPrefix("-") && !harmlessOutputs.contains($0) }) {
                return true
            }
        default:
            break
        }

        guard sqlVerbs.contains(command) || sqlClients.contains(command) else { return false }
        // SQL that drops or empties a table, wherever the verb sits in the statement.
        let sequence = ([command] + lowered).flatMap {
            $0.split(whereSeparator: { !$0.isLetter && !$0.isNumber && $0 != "_" }).map(String.init)
        }
        let words = Set(sequence)
        if words.contains("drop"), words.contains(where: droppableObject) { return true }
        // A DELETE empties rows wherever its FROM follows, with or without a WHERE.
        if let delete = sequence.firstIndex(of: "delete"), sequence[delete...].contains("from") {
            return true
        }
        return words.contains("truncate")
    }

    /// Calls in a MongoDB shell script that drop a database or a collection, or delete its documents.
    private static let mongoDeletions = ["dropdatabase(", ".drop(", ".deletemany(", ".remove("]

    /// The command string a shell is given with `-c`, which it runs as a line of its own.
    private static func shellScript(_ arguments: [String]) -> String? {
        guard
            let flag = arguments.firstIndex(where: {
                $0.hasPrefix("-") && !$0.hasPrefix("--") && $0.dropFirst().contains("c")
            })
        else { return nil }
        return arguments.dropFirst(flag + 1).first { !$0.hasPrefix("-") }
    }

    /// SQL verbs that begin a statement typed straight into a database prompt.
    private static let sqlVerbs: Set<String> = ["drop", "truncate", "alter", "delete"]

    /// Programs that run the SQL they are given.
    private static let sqlClients: Set<String> = [
        "psql", "mysql", "mariadb", "sqlite3", "sqlite", "sqlcmd", "duckdb", "clickhouse",
        "clickhouse-client", "cockroach", "snowsql", "bq", "pgcli", "mycli", "litecli", "usql", "osql",
        "isql", "sqlplus", "db2",
        "trino", "presto", "spark-sql", "hive", "beeline", "cqlsh", "impala-shell", "vsql", "redshift",
    ]

    /// Whether a git clause throws work away for good: a forced, deleting, mirroring or pruning push, a hard reset, a forced clean, a forced branch deletion, a dropped stash, changes discarded by a checkout, switch or restore, or history rewritten or pruned.
    private static func matchesDestructiveGit(_ arguments: [String]) -> Bool {
        let head = subcommandIndex(arguments)
        if let head, historyDestroyers.contains(arguments[head]) { return true }
        // The flags of the clause's own subcommand, so the same word as a message or path is not one.
        func flags(after subcommand: String) -> ArraySlice<String>? {
            guard let head, arguments[head] == subcommand else { return nil }
            return arguments[(head + 1)...]
        }
        if let flags = flags(after: "push"),
            flags.contains(where: {
                $0.hasPrefix("--force") || $0 == "-f" || $0 == "--delete" || $0 == "-d" || $0.hasPrefix("+")
                    || ($0.hasPrefix(":") && $0.count > 1) || $0 == "--mirror" || $0 == "--prune"
            })
        {
            return true
        }
        if let flags = flags(after: "reset"), flags.contains("--hard") { return true }
        if let flags = flags(after: "clean"),
            flags.contains(where: {
                $0.hasPrefix("-") && !$0.hasPrefix("--") && $0.lowercased().contains("f")
            })
                || flags.contains("--force")
        {
            return true
        }
        if let flags = flags(after: "branch"),
            flags.contains(where: {
                $0 == "-D" || ($0.hasPrefix("-") && !$0.hasPrefix("--") && $0.contains("D"))
            })
                || (flags.contains("--delete") && flags.contains("--force"))
        {
            return true
        }
        if let flags = flags(after: "stash"), flags.first == "drop" || flags.first == "clear" { return true }
        if let flags = flags(after: "checkout"),
            flags.contains("--") || flags.contains(".") || flags.contains("--force")
                || flags.contains(where: { shortFlags($0, include: "f", valuesAfter: ["b", "B"]) })
        {
            return true
        }
        if let flags = flags(after: "switch"),
            flags.contains("--force") || flags.contains("--discard-changes")
                || flags.contains(where: { shortFlags($0, include: "f", valuesAfter: ["c", "C"]) })
        {
            return true
        }
        if let flags = flags(after: "restore"), !flags.contains("--staged") || flags.contains("--worktree") {
            return true
        }
        if let flags = flags(after: "update-ref"), flags.contains("-d") || flags.contains("--delete") {
            return true
        }
        if let flags = flags(after: "reflog"), flags.first == "expire" || flags.first == "delete" {
            return true
        }
        if let flags = flags(after: "gc"),
            flags.contains(where: { ["--prune=now", "--prune=all"].contains($0) })
        {
            return true
        }
        return false
    }

    /// Git subcommands that rewrite every commit or drop unreachable objects whatever their flags.
    private static let historyDestroyers: Set<String> = ["filter-branch", "filter-repo", "prune"]

    /// Whether a cluster of short flags holds this one, read only up to the first flag whose value runs on in the same word.
    private static func shortFlags(
        _ word: String, include flag: Character, valuesAfter valued: Set<Character>
    ) -> Bool {
        guard word.hasPrefix("-"), !word.hasPrefix("--") else { return false }
        for letter in word.dropFirst() {
            if letter == flag { return true }
            if valued.contains(letter) { return false }
        }
        return false
    }

    /// Whether a permission or ownership command requests a recursive change before its option terminator.
    private static func hasRecursiveOption(_ arguments: [String]) -> Bool {
        for argument in arguments {
            if argument == "--" { return false }
            if argument == "--recursive" || shortFlags(argument, include: "R", valuesAfter: []) {
                return true
            }
        }
        return false
    }

    /// Where the subcommand stands once git's own leading options are skipped, or nil when there is none.
    private static func subcommandIndex(_ arguments: [String]) -> Int? {
        var index = arguments.startIndex
        while index < arguments.endIndex {
            let word = arguments[index]
            guard word.hasPrefix("-") else { return index }
            index += gitOptionsTakingValue.contains(word) ? 2 : 1
        }
        return nil
    }

    /// Git's leading options whose value is the next word.
    private static let gitOptionsTakingValue: Set<String> = [
        "-C", "-c", "--git-dir", "--work-tree", "--namespace", "--super-prefix", "--config-env",
    ]

    /// The kinds of thing a DROP destroys, which is what makes the statement irreversible.
    private static func droppableObject(_ word: String) -> Bool {
        word == "table" || word == "database" || word == "schema" || word == "index"
    }
}
