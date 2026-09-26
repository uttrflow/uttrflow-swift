/// Recognises command lines that destroy data or the machine, so they are never learned or auto-offered.
public enum DestructiveCommand {
    /// Whether taking this line as a completion could do irreversible harm, judged conservatively.
    public static func matches(_ text: String, failClosedOnUnresolved: Bool = false) -> Bool {
        // A fork bomb carries no ordinary tokens, so it is matched on the whitespace-stripped text.
        if text.lowercased().filter({ !$0.isWhitespace }).contains(":(){:|:&};:") { return true }
        let lower = text.lowercased()
        if lower.contains("of=/dev/") || lower.contains("/dev/sd") || lower.contains("/dev/disk") {
            return true
        }
        guard let clauses = ShellWords.commands(in: text, home: "") else { return failClosedOnUnresolved }
        return clauses.contains { clause in
            if failClosedOnUnresolved,
                (clause.words + clause.inputs).contains(where: \.isUnresolved)
            {
                return true
            }
            return destroys(clause.words, failClosedOnUnresolved: failClosedOnUnresolved)
        }
    }

    /// Words that run the command after them, with the flags of theirs that take a value.
    private static let wrappers: [String: Set<String>] = [
        "sudo": ["-u", "-g", "-h", "-p", "-C", "-D", "-r", "-t", "-U", "-T"], "doas": ["-u", "-C"],
        "env": ["-u", "-S", "-P"], "nice": ["-n"], "nohup": [], "time": [], "command": [], "builtin": [],
        "exec": ["-a"], "noglob": [], "nocorrect": [],
        "xargs": ["-I", "-J", "-L", "-n", "-P", "-s", "-E", "-R", "-S", "-d"],
    ]

    /// Programs that destroy whatever they are pointed at.
    private static let destroyers: Set<String> = [
        "rm", "rmdir", "shred", "srm", "unlink", "dd", "mkfs", "fdisk", "parted", "shutdown", "reboot",
        "halt",
        "poweroff",
    ]

    private enum Command {
        case none
        case unresolved
        case named(String, [String])
    }

    /// The program a parsed clause runs, read past assignments and every wrapper.
    private static func command(in tokens: [ShellWord]) -> Command {
        var rest = tokens[...]
        while let first = rest.first {
            guard !first.isUnresolved else { return .unresolved }
            let name = programName(first.text)
            if TerminalLineCheck.isAssignment(first.text), rest.count > 1 {
                rest.removeFirst()
                continue
            }
            guard let flags = wrappers[name], rest.count > 1 else {
                return .named(name, Array(rest.dropFirst().map(\.text)))
            }
            rest.removeFirst()
            while let flag = rest.first, flag.text.count > 1, flag.text.hasPrefix("-") {
                guard !flag.isUnresolved else { return .unresolved }
                rest.removeFirst()
                if flags.contains(flag.text), !rest.isEmpty { rest.removeFirst() }
            }
        }
        return .none
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
        switch command {
        case "git":
            if matchesDestructiveGit(arguments) { return true }
        case "find":
            if lowered.contains("-delete") { return true }
            if let exec = lowered.firstIndex(where: { $0 == "-exec" || $0 == "-execdir" }),
                let program = lowered.dropFirst(exec + 1).first, destroyers.contains(programName(program))
            {
                return true
            }
        case "diskutil":
            let verbs = ["erase", "zerodisk", "randomdisk", "securerase", "partitiondisk", "reformat"]
            if lowered.contains(where: { word in verbs.contains(where: word.hasPrefix) }) { return true }
        case "docker", "podman":
            if lowered.contains("prune") || (lowered.first == "volume" && lowered.dropFirst().first == "rm") {
                return true
            }
        case "kubectl":
            if lowered.first == "delete" { return true }
        case "terraform", "tofu":
            if lowered.contains("destroy") || lowered.contains("-destroy") { return true }
        case "crontab":
            if lowered.contains("-r") { return true }
        case "mv", "cp":
            if lowered.last == "/dev/null" { return true }
        default:
            break
        }

        guard sqlVerbs.contains(command) || sqlClients.contains(command) else { return false }
        // SQL that drops or empties a table, wherever the verb sits in the statement.
        let words = Set(
            ([command] + lowered).flatMap {
                $0.split(whereSeparator: { !$0.isLetter && !$0.isNumber && $0 != "_" }).map(String.init)
            })
        if words.contains("drop"), words.contains(where: droppableObject) { return true }
        return words.contains("truncate")
    }

    /// SQL verbs that begin a statement typed straight into a database prompt.
    private static let sqlVerbs: Set<String> = ["drop", "truncate", "alter"]

    /// Programs that run the SQL they are given.
    private static let sqlClients: Set<String> = [
        "psql", "mysql", "mariadb", "sqlite3", "sqlite", "sqlcmd", "duckdb", "clickhouse", "clickhouse-client",
        "cockroach", "snowsql", "bq", "pgcli", "mycli", "litecli", "usql", "osql", "isql", "sqlplus", "db2",
        "trino", "presto", "spark-sql", "hive", "beeline", "cqlsh", "impala-shell", "vsql", "redshift",
    ]

    /// Whether a git clause throws work away for good: a forced or deleting push, a hard reset, a forced clean, a forced branch deletion, a dropped stash or discarded changes.
    private static func matchesDestructiveGit(_ arguments: [String]) -> Bool {
        // The flag has to stand after the subcommand it belongs to, so a word quoted elsewhere is not one.
        func flags(after subcommand: String) -> ArraySlice<String>? {
            arguments.firstIndex(of: subcommand).map { arguments[($0 + 1)...] }
        }
        if let flags = flags(after: "push"),
            flags.contains(where: {
                $0.hasPrefix("--force") || $0 == "-f" || $0 == "--delete" || $0 == "-d" || $0.hasPrefix("+")
                    || ($0.hasPrefix(":") && $0.count > 1)
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
        if let flags = flags(after: "checkout"), flags.contains("--") || flags.contains(".") { return true }
        if let flags = flags(after: "restore"), !flags.contains("--staged") || flags.contains("--worktree") {
            return true
        }
        return false
    }

    /// The kinds of thing a DROP destroys, which is what makes the statement irreversible.
    private static func droppableObject(_ word: String) -> Bool {
        word == "table" || word == "database" || word == "schema" || word == "index"
    }
}
