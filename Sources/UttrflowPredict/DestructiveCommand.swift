/// Recognises command lines that destroy data or the machine, so they are never learned or auto-offered.
public enum DestructiveCommand {
    /// Whether taking this line as a completion could do irreversible harm, judged conservatively.
    public static func matches(_ text: String, failClosedOnUnresolved: Bool = false) -> Bool {
        matches(text, failClosedOnUnresolved: failClosedOnUnresolved, files: defaultFileSystem)
    }

    /// The disk the no-filesystem callers fall back on, so `git checkout <path>` can be told from `git checkout <branch>`.
    private static let defaultFileSystem: any FileSystemProbing = CachedFileSystem(SystemFileSystem())

    /// Whether taking this line as a completion could do irreversible harm, asked of a disk so `git checkout <path>` can be told from `git checkout <branch>`.
    public static func matches(
        _ text: String, failClosedOnUnresolved: Bool = false, files: (any FileSystemProbing)?
    ) -> Bool {
        // A fork bomb carries no ordinary tokens, so it is matched on the whitespace-stripped text.
        if text.lowercased().filter({ !$0.isWhitespace }).contains(":(){:|:&};:") { return true }
        let lower = text.lowercased()
        if lower.contains("of=/dev/") || lower.contains("/dev/sd") || lower.contains("/dev/disk")
            || lower.contains("/dev/rdisk")
        {
            return true
        }
        // Which shell will run the line is unknown, so a `#` is read both as bash's comment and as zsh's word.
        let readings = text.contains("#") ? [true, false] : [true]
        return readings.contains { hashComments in
            // A line only the word reading cannot settle, as `ls # it's` is, is one zsh would not run.
            guard let clauses = ShellWords.commands(in: text, home: "", hashComments: hashComments) else {
                return hashComments && failClosedOnUnresolved
            }
            return destroys(clauses, failClosedOnUnresolved: failClosedOnUnresolved, files: files)
        }
    }

    /// Whether any of one reading's simple commands destroys data.
    private static func destroys(
        _ clauses: [SimpleCommand], failClosedOnUnresolved: Bool, files: (any FileSystemProbing)?
    ) -> Bool {
        clauses.contains { clause in
            if failClosedOnUnresolved,
                (clause.words + clause.inputs).contains(where: \.isUnresolved)
            {
                return true
            }
            if clause.overwrites.contains(where: { !harmlessOutputs.contains($0.text) }) { return true }
            return destroys(clause.words, failClosedOnUnresolved: failClosedOnUnresolved, files: files)
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

    /// The source operands of `cp`, after options and their values are removed.
    private static func cpSources(_ arguments: [String]) -> [String] {
        var operands: [String] = []
        var rest = arguments[...]
        var targetDirectory = false
        while let argument = rest.popFirst() {
            if argument == "--" {
                operands += rest
                break
            }
            if argument == "-S" || argument == "--suffix" {
                if !rest.isEmpty { rest.removeFirst() }
                continue
            }
            if argument.hasPrefix("-S") && argument.count > 2 || argument.hasPrefix("--suffix=") {
                continue
            }
            if argument == "-t" || argument == "--target-directory" {
                targetDirectory = true
                if !rest.isEmpty { rest.removeFirst() }
                continue
            }
            if argument.hasPrefix("-t") && argument.count > 2 || argument.hasPrefix("--target-directory=") {
                targetDirectory = true
                continue
            }
            if argument.count > 1 && argument.hasPrefix("-") {
                continue
            }
            operands.append(argument)
        }
        return targetDirectory ? operands : Array(operands.dropLast())
    }

    /// A word that runs the command after it: its flags that take a value, and how many plain words of its own precede the command.
    private struct Wrapper {
        let valued: Set<String>
        var operands = 0
        /// Flags whose appearance anywhere in the wrapper's body means the rest of the line is the carried command.
        var carryFlags: Set<String>? = nil
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
        "setsid": Wrapper(valued: []),
        "parallel": Wrapper(valued: [
            "-j", "--jobs", "--max-procs",
            "-N", "--max-args",
            "-n", "--number-of-args",
            "-a", "--arg-file",
            "-S", "--sshlogin",
            "--colsep",
            "--header",
            "--tagstring",
            "--joblog",
            "--retries",
            "--timeout",
            "--files",
            "--results",
            "--tmpdir",
            "--workdir",
            "--basefile",
            "--bar",
            "--load",
            "--noswap",
            "--memfree",
            "--memsuspend",
            "--block",
            "--link",
            "--linkinputsource",
            "--filter",
            "--rpl",
            "--shellquote",
            "--trc",
            "--cleanup",
            "--env",
            "--eta",
        ]),
        "ssh": Wrapper(
            valued: [
                "-i", "-p", "-l", "-o", "-E", "-F", "-L", "-R", "-D", "-W", "-J", "-c", "-m", "-S",
                "-O", "-Q", "-b", "-B", "-I",
            ],
            operands: 1,
        ),
        "mosh": Wrapper(
            valued: [
                "--client", "--server", "--predict", "--port", "-p", "--ssh", "--family",
            ],
            operands: 1,
        ),
        "fd": Wrapper(
            valued: [
                "-e", "--extension", "-t", "--type", "-l", "--max-depth", "-d", "--min-depth",
                "-E", "--exclude", "-S", "--size", "--changed-within", "--changed-before",
                "-o", "--owner", "-c", "--color", "-j", "--threads", "--search-path",
                "--max-results", "--ignore-file", "--base-directory",
            ],
            operands: 0,
            carryFlags: ["-x", "-X", "--exec", "--exec-batch", "--run"],
        ),
    ]

    /// Shell reserved words that stand in front of the command a clause runs, as a loop's `do` and an `if`'s `then` do.
    private static let reservedWords: Set<String> = [
        "do", "then", "else", "elif", "if", "while", "until", "!",
    ]

    /// Commands with their own argument semantics, which the carrier failsafe must not reinterpret.
    private static let judgedCommands: Set<String> = [
        "chmod", "chown", "chgrp", "git", "hg", "svn", "find", "diskutil",
        "terraform", "tofu", "redis-cli", "valkey-cli", "keydb-cli", "mongo", "mongosh",
        "crontab", "sh", "bash", "zsh", "dash", "ksh", "fish", "su", "runuser",
        "eval", "mv", "cp", "killall", "pkill", "kill", "rsync", "tee",
        "echo", "man", "which", "tldr", "type", "help", "info", "whatis", "apropos",
        "printf", "command",
    ]

    /// Programs that destroy whatever they are pointed at.
    private static let destroyers: Set<String> = [
        "rm", "rmdir", "shred", "srm", "unlink", "dd", "mkfs", "fdisk", "parted", "shutdown", "reboot",
        "halt",
        "poweroff", "dropdb", "dropuser", "userdel",
    ]

    /// `find` action flags whose clauses run an inner command terminated by `;` or `+`.
    private static let findActionFlags: Set<String> = ["-exec", "-execdir", "-ok", "-okdir"]

    private enum Command {
        case none
        case unresolved
        case named(String, [String])
        /// A quoted word in the program's place, which ssh, parallel and similar runners hand to a shell as a line.
        case line(String)
    }

    /// The program a parsed clause runs, read past assignments, reserved words and every wrapper.
    private static func command(in tokens: [ShellWord]) -> Command {
        var rest = tokens[...]
        while let first = rest.first {
            // An assignment's value is never run, so its quoting or expansion says nothing about the command.
            if TerminalLineCheck.isAssignment(first.text) || reservedWords.contains(programName(first.text)), rest.count > 1 {
                rest.removeFirst()
                continue
            }
            guard !first.isUnresolved else { return .unresolved }
            if first.text.contains(where: \.isWhitespace) {
                return .line(rest.map(\.text).joined(separator: " "))
            }
            let name = programName(first.text)
            // `command -v` and `command -V` inspect a name; they do not run the name as a command.
            let commandOptions = rest.dropFirst().prefix(while: { $0.text.hasPrefix("-") })
            if name == "command", commandOptions.contains(where: { $0.text == "-v" || $0.text == "-V" }) {
                return .named(name, Array(rest.dropFirst().map(\.text)))
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

    /// Whether the line begins with a carrier whose trigger appears anywhere in its body, and the carried command destroys.
    private static func carriesDestructive(_ tokens: [ShellWord]) -> Bool? {
        guard let first = tokens.first, tokens.count > 1 else { return nil }
        let name = programName(first.text)
        guard let wrapper = wrappers[name], let carryFlags = wrapper.carryFlags else { return nil }
        for (index, candidate) in tokens.enumerated().dropFirst() {
            guard candidate.text.count > 1, candidate.text.hasPrefix("-"), !candidate.isUnresolved else {
                continue
            }
            if carryFlags.contains(candidate.text) {
                let carried = Array(tokens.dropFirst(index + 1))
                let text = shellQuoted(carried.map(\.text))
                guard let clauses = ShellWords.commands(in: text, home: "") else { return false }
                return clauses.contains { destroys($0.words, failClosedOnUnresolved: false) }
            }
        }
        return nil
    }

    /// A tool whose verbs follow its option flags: the flags that take a value, and which verbs delete for good.
    private struct VerbTool: Sendable {
        let valued: Set<String>
        /// Whether the tool's positional words, then all its arguments, both lowercased, name an irreversible deletion.
        let destroys: @Sendable (_ positionals: [String], _ arguments: [String]) -> Bool
    }

    /// The programs judged by their verbs, so a test can hold a sample line for each.
    static var verbToolNames: Set<String> { Set(verbTools.keys) }

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
                return awsDestructiveOperations.contains(operation)
                    || operation.hasPrefix("delete-") || operation.hasPrefix("batch-delete-")
                    || operation.hasPrefix("terminate-") || operation.hasPrefix("deregister-")
                    || operation.hasPrefix("purge-") || operation.hasPrefix("remove-")
            }),
        "gcloud": VerbTool(
            valued: [
                "--project", "--account", "--configuration", "--format", "--verbosity", "--zone", "--region",
                "--impersonate-service-account", "--billing-project", "--filter", "--flatten",
            ],
            destroys: { positionals, _ in
                positionals.contains("delete") || positionals.contains("rm") || positionals.contains("purge")
            }),
        "az": VerbTool(
            valued: [
                "--subscription", "-g", "--resource-group", "-n", "--name", "-o", "--output", "--query", "-l",
                "--location",
            ],
            destroys: { positionals, _ in
                positionals.contains("delete") || positionals.contains("rm") || positionals.contains("purge")
                    || positionals.contains("delete-batch")
            }),
        "gsutil": VerbTool(
            valued: ["-o", "-h", "-u"],
            destroys: { positionals, arguments in
                positionals.first == "rm" || positionals.first == "rb"
                    || (positionals.first == "rsync"
                        && arguments.contains(where: { shortFlags($0, include: "d", valuesAfter: []) }))
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
        "npm": VerbTool(
            valued: [
                "--registry", "--userconfig", "--globalconfig", "--prefix", "--cache", "--workspace", "-w",
                "--scope", "--loglevel", "--otp",
            ],
            destroys: { positionals, _ in positionals.first == "unpublish" }),
        "pnpm": VerbTool(
            valued: [
                "--filter", "-F", "--dir", "--registry", "--store-dir", "--virtual-store-dir", "--prefix",
                "--config-dir", "--reporter",
            ],
            destroys: { positionals, _ in positionals.first == "unpublish" }),
        "yarn": VerbTool(
            valued: [
                "--cwd", "--use-yarnrc", "--mutex", "--network-concurrency", "--network-timeout",
                "--cache-folder", "--modules-folder", "--registry", "--scope",
            ],
            destroys: { positionals, _ in positionals.first == "unpublish" }),
        "cargo": VerbTool(
            valued: ["--config", "-Z"],
            destroys: { positionals, _ in positionals.first == "yank" }),
        "pip": pipTool,
        "pip3": pipTool,
        "oc": VerbTool(
            valued: [
                "-n", "--namespace", "--context", "--kubeconfig", "--cluster", "--user", "-s", "--server",
                "--token", "--as", "--request-timeout", "--loglevel",
            ],
            destroys: { positionals, _ in positionals.first == "delete" }),
        "defaults": VerbTool(
            valued: ["-host"],
            destroys: { positionals, _ in positionals.first == "delete" }),
        "mysqladmin": VerbTool(
            valued: ["-u", "--user", "-h", "--host", "--port", "-s", "--socket"],
            destroys: { positionals, _ in positionals.first == "drop" }),
        "pulumi": VerbTool(
            valued: ["-s", "--stack", "-c", "--cwd"],
            destroys: { positionals, _ in
                let verb = positionals.dropFirst().first
                return positionals.first == "destroy"
                    || (positionals.first == "stack" && (verb == "rm" || verb == "remove"))
            }),
        "heroku": VerbTool(
            valued: ["-a", "--app", "-c", "--confirm", "-r", "--remote"],
            destroys: { positionals, _ in
                ["apps:destroy", "destroy", "addons:destroy", "pg:reset"].contains(positionals.first)
            }),
        "vercel": VerbTool(
            valued: ["--scope", "-s", "--token", "-t", "--cwd"],
            destroys: { positionals, _ in ["rm", "remove"].contains(positionals.first) }),
        "firebase": VerbTool(
            valued: ["--project", "-p", "--token"],
            destroys: { positionals, _ in
                guard let verb = positionals.first else { return false }
                return verb.hasSuffix(":delete") || verb.hasSuffix(":remove") || verb == "hosting:disable"
            }),
        "sysadminctl": VerbTool(
            valued: [],
            destroys: { _, arguments in arguments.contains("-deleteuser") }),
        "brew": VerbTool(
            valued: brewValued,
            destroys: { positionals, arguments in
                ["uninstall", "remove"].contains(positionals.first)
                    && hasOption("--zap", in: arguments, valued: brewValued)
            }),
    ]

    /// Package-manager options that take a value before their subcommand.
    private static let pipValued: Set<String> = [
        "--python", "--proxy", "--retries", "--timeout", "--index-url", "--extra-index-url",
        "--find-links", "--trusted-host", "--cert", "--client-cert", "--cache-dir", "--log",
        "--log-file", "--exists-action", "--no-binary", "--only-binary",
    ]

    /// AWS operations, exact-spelled, that are irreversible in fact but do not begin with `delete-` or `terminate-`; `deregister-`, `purge-` and `remove-` are handled as prefixes in the AWS verb tool.
    private static let awsDestructiveOperations: Set<String> = [
        "schedule-key-deletion",
        "disable-key",
    ]

    /// Pip's quiet unattended uninstallation, recognized only when it is the actual pip subcommand.
    private static let pipTool = VerbTool(
        valued: pipValued,
        destroys: pipUninstall
    )

    private static func pipUninstall(_ positionals: [String], _ arguments: [String]) -> Bool {
        positionals.first == "uninstall"
            && (hasOption("-y", in: arguments, valued: pipValued)
                || hasOption("--yes", in: arguments, valued: pipValued))
    }

    private static let brewValued: Set<String> = ["--repository"]

    private static func hasOption(_ option: String, in arguments: [String], valued: Set<String>) -> Bool {
        var remaining = arguments[...]
        while let argument = remaining.popFirst() {
            if argument == "--" { return false }
            if argument == option { return true }
            if valued.contains(argument), !remaining.isEmpty { remaining.removeFirst() }
        }
        return false
    }

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

    /// A parsed command word as the program it names, lowercased; zsh expands a leading `=` to the command's path.
    private static func programName(_ word: String) -> String {
        let path = word.count > 1 && word.hasPrefix("=") ? String(word.dropFirst()) : word
        return (path.split(separator: "/").last.map(String.init) ?? path).lowercased()
    }

    /// The flags a `docker exec` / `docker run` line takes within its subcommand, whose values the parser must skip.
    /// Single-letter flags are matched as written, since `-p` takes a port and `-P` takes nothing.
    private static let containerSubcommandValued: Set<String> = [
        "-u", "--user", "-w", "--workdir", "-e", "--env", "--env-file",
        "-v", "-m", "-l", "-h", "-a", "-p", "-c", "--attach", "--cpu-shares", "--index",
        "--cap-add", "--cap-drop", "--cgroup-parent", "--device", "--device-cgroup-rule",
        "--dns", "--dns-opt", "--dns-search", "--domainname", "--entrypoint",
        "--expose", "--group-add", "--health-cmd", "--health-interval", "--health-retries",
        "--health-start-period", "--health-timeout", "--hostname", "--init-path", "--ip", "--ip6",
        "--label", "--label-file", "--link", "--link-local-addr", "--log-driver", "--log-opt",
        "--mac-address", "--memory", "--memory-reservation", "--memory-swap", "--memory-swappiness",
        "--mount", "--name", "--network", "--network-alias", "--pid", "--pids-limit",
        "--platform", "--publish", "--restart", "--runtime", "--shm-size", "--stop-signal",
        "--stop-timeout", "--storage-opt", "--sysctl", "--tmpfs", "--ulimit", "--userns",
        "--volume", "--volume-driver", "--volumes-from", "--add-host", "--security-opt",
    ]

    /// The flags `kubectl exec` takes within its subcommand, whose values the parser must skip.
    private static let kubectlExecValued: Set<String> = [
        "-c", "--container", "-p", "--pod", "--filename",
    ]

    /// Whether a flag as written is in a valued set: a single-letter flag by its exact case, a long one by its lowercase.
    private static func takesValue(_ flag: String, in valued: Set<String>) -> Bool {
        flag.hasPrefix("--") ? valued.contains(flag.lowercased()) : valued.contains(flag)
    }

    /// The text of the command `docker exec [opts] container [cmd]`, `docker run [opts] image [cmd]`, their
    /// `container` and `compose` forms, or `kubectl exec [opts] pod -- cmd` runs, or nil.
    private static func verbToolSubcommandCarrier(command: String, arguments: [String]) -> String? {
        let valued: Set<String>
        let globalValued: Set<String>
        let terminator: String?
        var isCompose = command == "docker-compose" || command == "podman-compose"
        switch command {
        case "docker", "podman", "docker-compose", "podman-compose":
            valued = containerSubcommandValued
            globalValued = isCompose ? composeValued : containerGlobalFlags
            terminator = nil
        case "kubectl":
            valued = kubectlExecValued
            globalValued = kubectlGlobalFlags
            terminator = "--"
        default:
            return nil
        }
        var rest = arguments[...]
        // Skip the tool's global flags that can appear in front of the subcommand.
        func skipFlags(_ flags: Set<String>, caseExact: Bool) {
            while let head = rest.first, head.hasPrefix("-"), head.count > 1, head != "--" {
                rest.removeFirst()
                let takes = caseExact ? takesValue(head, in: flags) : flags.contains(head.lowercased())
                if takes, !rest.isEmpty { rest.removeFirst() }
            }
        }
        skipFlags(globalValued, caseExact: false)
        if terminator == nil, !isCompose, let group = rest.first?.lowercased(),
            group == "container" || group == "compose"
        {
            rest.removeFirst()
            isCompose = group == "compose"
            if isCompose { skipFlags(composeValued, caseExact: false) }
        }
        let subcommands: Set<String> = terminator == nil ? ["exec", "run"] : ["exec"]
        guard rest.count >= 2, let verb = rest.first?.lowercased(), subcommands.contains(verb) else {
            return nil
        }
        rest.removeFirst()
        // Skip the subcommand's valued flags and their values.
        skipFlags(valued, caseExact: true)
        // Skip the required operand (container, service, image, or pod).
        guard !rest.isEmpty else { return nil }
        rest.removeFirst()
        if let term = terminator {
            // The carried command begins after the `--` terminator.
            guard let termIndex = rest.firstIndex(of: term) else { return nil }
            rest = rest[(termIndex + 1)...]
        }
        return rest.isEmpty ? nil : shellQuoted(rest.map { $0.lowercased() })
    }

    /// Parsed words joined back into a line the parser reads as the same words, so a quoted script stays one argument.
    private static func shellQuoted(_ words: [String]) -> String {
        words.map { "'" + $0.replacingOccurrences(of: "'", with: "'\\''") + "'" }.joined(separator: " ")
    }

    /// The global flags docker and podman take before any subcommand, with their values, lowercased.
    private static let containerGlobalFlags: Set<String> = [
        "-h", "--host", "-c", "--context", "--config", "-l", "--log-level",
        "--tlscacert", "--tlscert", "--tlskey", "--url", "--connection",
        "--root", "--runroot", "--storage-driver", "--identity",
    ]

    /// The global flags kubectl takes before its subcommand, with their values, lowercased.
    private static let kubectlGlobalFlags: Set<String> = [
        "-n", "--namespace", "--context", "--kubeconfig", "--cluster", "--user",
        "-s", "--server", "--token", "--as", "--as-group", "--as-uid",
        "--request-timeout", "-v", "--cache-dir", "--certificate-authority",
        "--client-certificate", "--client-key", "--tls-server-name",
        "--password", "--username", "--profile", "--profile-output",
        "--log-file", "--vmodule",
    ]

    /// Whether one clause destroys data or the machine.
    private static func destroys(
        _ tokens: [ShellWord], failClosedOnUnresolved: Bool, files: (any FileSystemProbing)? = nil
    ) -> Bool {
        if let carrier = carriesDestructive(tokens) { return carrier }
        let parsed = command(in: tokens)
        if case .unresolved = parsed { return failClosedOnUnresolved }
        if case .line(let line) = parsed {
            return matches(line, failClosedOnUnresolved: failClosedOnUnresolved, files: files)
        }
        guard case .named(let command, let arguments) = parsed else { return false }
        let lowered = arguments.map { $0.lowercased() }
        if destroyers.contains(command) || command.hasPrefix("mkfs.") { return true }
        if command == "python" || command == "python3" || command.hasPrefix("python3."),
            let module = lowered.firstIndex(of: "-m"),
            lowered.indices.contains(module + 1), lowered[module + 1] == "pip"
        {
            let pipArguments = Array(lowered.dropFirst(module + 2))
            if pipUninstall(positionals(pipArguments, valued: pipValued), pipArguments) { return true }
        }
        if let carrier = verbToolSubcommandCarrier(command: command, arguments: arguments) {
            if matches(carrier, failClosedOnUnresolved: failClosedOnUnresolved) { return true }
        }
        if let tool = verbTools[command], tool.destroys(positionals(lowered, valued: tool.valued), lowered) {
            return true
        }
        switch command {
        case "chmod", "chown", "chgrp":
            if hasRecursiveOption(arguments) { return true }
        case "git":
            if matchesDestructiveGit(arguments, files: files) { return true }
        case "hg":
            if matchesDestructiveMercurial(arguments) { return true }
        case "svn":
            if matchesDestructiveSubversion(arguments) { return true }
        case "find":
            if lowered.contains("-delete") { return true }
            // Every -exec, -execdir, -ok and -okdir clause is judged up to its terminating `;` or `+`, so a destroyer in a later clause is still found.
            var i = 0
            while i < tokens.count {
                guard findActionFlags.contains(tokens[i].text.lowercased()) else { i += 1; continue }
                let start = i + 1
                var end = tokens.count
                var j = start
                while j < tokens.count {
                    let text = tokens[j].text
                    if text == ";" || text == "+" {
                        end = j
                        break
                    }
                    j += 1
                }
                if destroys(
                    Array(tokens[start..<end]), failClosedOnUnresolved: failClosedOnUnresolved, files: files
                ) {
                    return true
                }
                i = end + 1
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
        case "su", "runuser":
            if let script = shellScript(arguments),
                matches(script, failClosedOnUnresolved: failClosedOnUnresolved)
            {
                return true
            }
        case "eval":
            // The arguments are joined into the line the shell re-parses, so a destroyer in any of them is judged as one.
            let script = arguments.joined(separator: " ")
            if !script.isEmpty,
                matches(script, failClosedOnUnresolved: failClosedOnUnresolved)
            {
                return true
            }
        case "mv":
            if lowered.last == "/dev/null" { return true }
        case "cp":
            if cpSources(arguments).contains(where: {
                $0.lowercased() == "/dev/null" || $0.lowercased() == "/dev/zero"
            }) {
                return true
            }
        case "killall":
            if processKillIsDestructive(lowered) { return true }
        case "pkill", "kill":
            if processKillIsDestructive(lowered) { return true }
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

        guard sqlVerbs.contains(command) || sqlClients.contains(command) else {
            // An unrecognised carrier word followed by a plain destroyer fails closed, after every known command has judged its own arguments.
            if judgedCommands.contains(command) || destroyers.contains(command) || verbTools[command] != nil {
                return false
            }
            // Only the first non-flag argument names the command the carrier runs, so `echo "rm -rf /"` is not destructive.
            for argument in lowered {
                guard !argument.hasPrefix("-") else { continue }
                return destroyers.contains(argument)
            }
            return false
        }
        return SQLDestructiveCommand.matches(command: command, arguments: lowered)
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
    private static func matchesDestructiveGit(
        _ arguments: [String], files: (any FileSystemProbing)? = nil
    ) -> Bool {
        let head = subcommandIndex(arguments)
        if let head, historyDestroyers.contains(arguments[head]) { return true }
        // The flags of the clause's own subcommand, so the same word as a message or path is not one.
        func flags(after subcommand: String) -> ArraySlice<String>? {
            guard let head, arguments[head] == subcommand else { return nil }
            return arguments[(head + 1)...]
        }
        if let flags = flags(after: "push"),
            flags.contains(where: {
                $0.hasPrefix("--force") || shortFlags($0, include: "f", valuesAfter: pushValueTaking)
                    || $0 == "--delete" || shortFlags($0, include: "d", valuesAfter: pushValueTaking)
                    || $0.hasPrefix("+") || ($0.hasPrefix(":") && $0.count > 1)
                    || $0 == "--mirror" || $0 == "--prune"
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
        if let flags = flags(after: "branch") {
            let forceDeletes = flags.contains(where: { shortFlags($0, include: "D", valuesAfter: []) })
            let deletes =
                flags.contains("--delete")
                || flags.contains(where: { shortFlags($0, include: "d", valuesAfter: []) })
            let forces =
                flags.contains("--force")
                || flags.contains(where: { shortFlags($0, include: "f", valuesAfter: []) })
            if forceDeletes || (deletes && forces) { return true }
        }
        if let flags = flags(after: "stash"), flags.first == "drop" || flags.first == "clear" { return true }
        if let flags = flags(after: "checkout"),
            flags.contains("--") || flags.contains(".") || flags.contains("--force")
                || flags.contains(where: { shortFlags($0, include: "f", valuesAfter: ["b", "B"]) })
        {
            return true
        }
        if checkoutRestoresExistingPath(flags(after: "checkout"), files: files) { return true }
        if matchesDestructiveGitCleanup(arguments) { return true }
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

    /// `git worktree remove`, `git rm` and a forced `git submodule deinit` each destroy work without further flags.
    private static func matchesDestructiveGitCleanup(_ arguments: [String]) -> Bool {
        let head = subcommandIndex(arguments)
        func flags(after subcommand: String) -> ArraySlice<String>? {
            guard let head, arguments[head] == subcommand else { return nil }
            return arguments[(head + 1)...]
        }
        if let flags = flags(after: "worktree"), flags.first == "remove" { return true }
        if let flags = flags(after: "rm"), !flags.contains("--cached") { return true }
        if let flags = flags(after: "submodule"), let deinitIndex = flags.firstIndex(of: "deinit") {
            let rest = flags[(deinitIndex + 1)...]
            return rest.contains("--force")
                || rest.contains(where: { shortFlags($0, include: "f", valuesAfter: []) })
        }
        return false
    }

    /// Whether the only positional left of `git checkout` names a file that exists on disk, so the line restores that file from the index.
    private static func checkoutRestoresExistingPath(
        _ flags: ArraySlice<String>?, files: (any FileSystemProbing)?
    ) -> Bool {
        guard let flags, let files, let path = singleCheckoutPositional(flags) else { return false }
        if case .file = files.kind(atPath: path) { return true }
        return false
    }

    /// The one word `git checkout` is left with once its flags and their values are read past, or nil when it is followed by more than one.
    private static func singleCheckoutPositional(_ flags: ArraySlice<String>) -> String? {
        var names: [String] = []
        var afterDashes = false
        var skipNext = false
        var index = flags.startIndex
        while index < flags.endIndex {
            let word = flags[index]
            if skipNext {
                skipNext = false
            } else if afterDashes {
                names.append(word)
            } else if word == "--" {
                afterDashes = true
            } else if word == "-b" || word == "-B" || word == "--orphan" {
                skipNext = true
            } else if !word.hasPrefix("-") {
                names.append(word)
            }
            index += 1
        }
        guard names.count == 1 else { return nil }
        let path = names[0]
        return looksLikePath(path) ? path : nil
    }

    /// Whether a single token has the shape of a filesystem path rather than a git commit, branch or revision.
    private static func looksLikePath(_ token: String) -> Bool {
        guard !token.isEmpty, !token.hasPrefix("-") else { return false }
        for character in token {
            switch character {
            case "~", "^", ":", "*", "?", "[", "]", "\\": return false
            default: continue
            }
        }
        return true
    }

    /// Whether a process signal or target can terminate more than one ordinary process.
    private static func processKillIsDestructive(_ arguments: [String]) -> Bool {
        for (index, argument) in arguments.enumerated() {
            if argument == "--" { break }
            if argument.hasPrefix("--signal=") {
                if isForceKillSignal(String(argument.dropFirst("--signal=".count))) { return true }
                continue
            }
            if argument == "-s" || argument == "--signal" {
                if arguments.indices.contains(index + 1), isForceKillSignal(arguments[index + 1]) {
                    return true
                }
                continue
            }
            guard argument.hasPrefix("-"), !argument.hasPrefix("--") else { continue }
            let signal = argument.dropFirst()
            if isForceKillSignal(String(signal)) { return true }
            if signal.lowercased().hasPrefix("s"), isForceKillSignal(String(signal.dropFirst())) {
                return true
            }
        }
        let positionals = positionals(arguments, valued: ["-s", "--signal", "-p", "--pid"])
        return positionals.contains("-1")
    }

    /// Whether a signal spelling names SIGKILL, with or without its prefix.
    private static func isForceKillSignal(_ spelling: String) -> Bool {
        let name =
            spelling.lowercased().hasPrefix("sig")
            ? String(spelling.dropFirst(3)).lowercased() : spelling.lowercased()
        return name == "kill" || Int(name) == 9
    }

    /// Git subcommands that rewrite every commit or drop unreachable objects whatever their flags.
    private static let historyDestroyers: Set<String> = ["filter-branch", "filter-repo", "prune"]

    /// Short flags in `git push` that take a value when they appear in a cluster, so anything after them is not another flag.
    private static let pushValueTaking: Set<Character> = ["o", "F"]

    /// Whether a Mercurial command removes history or discards working-copy changes.
    private static func matchesDestructiveMercurial(_ arguments: [String]) -> Bool {
        guard let index = operationIndex(arguments, valued: mercurialGlobalOptions) else { return false }
        let operation = arguments[index].lowercased()
        if ["strip", "prune", "purge"].contains(operation) { return true }
        guard operation == "update" else { return false }
        let flags = arguments.dropFirst(index + 1)
        return hasOption("--clean", in: flags) || hasShortOption("C", in: flags)
    }

    /// Whether a Subversion command deletes a repository path or discards local changes.
    private static func matchesDestructiveSubversion(_ arguments: [String]) -> Bool {
        guard let index = operationIndex(arguments, valued: subversionGlobalOptions) else { return false }
        return ["delete", "del", "remove", "rm", "revert"].contains(arguments[index].lowercased())
    }

    /// Global options that consume a value before Mercurial's command.
    private static let mercurialGlobalOptions: Set<String> = [
        "-R", "--repository", "--cwd", "--config", "--configfile", "--encoding", "--encodingmode",
        "--pager", "--color",
    ]

    /// Global options that consume a value before Subversion's subcommand.
    private static let subversionGlobalOptions: Set<String> = [
        "--username", "--password", "--config-dir", "--config-option", "--changelist",
    ]

    /// The first operation after a command's leading global options.
    private static func operationIndex(_ arguments: [String], valued: Set<String>) -> Int? {
        var index = arguments.startIndex
        while index < arguments.endIndex {
            let word = arguments[index]
            if word == "--" {
                return arguments.index(after: index) < arguments.endIndex
                    ? arguments.index(after: index) : nil
            }
            guard word.hasPrefix("-") else { return index }
            index = arguments.index(after: index)
            if valued.contains(word), index < arguments.endIndex { index = arguments.index(after: index) }
        }
        return nil
    }

    /// Whether the option occurs before an option terminator.
    private static func hasOption(_ option: String, in arguments: ArraySlice<String>) -> Bool {
        for argument in arguments {
            if argument == "--" { return false }
            if argument == option { return true }
        }
        return false
    }

    /// Whether a clustered short option occurs before an option terminator.
    private static func hasShortOption(_ option: Character, in arguments: ArraySlice<String>) -> Bool {
        for argument in arguments {
            if argument == "--" { return false }
            if shortFlags(argument, include: option, valuesAfter: []) { return true }
        }
        return false
    }

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

}
