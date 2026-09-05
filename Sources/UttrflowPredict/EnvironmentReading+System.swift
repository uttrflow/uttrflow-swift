import Foundation

/// Reads what actually exists on this Mac, which is the one thing a language model cannot know.
public struct SystemEnvironmentReader: EnvironmentReading {
    /// How long a read may take before its answer is thrown away, since a keystroke is waiting.
    static let timeoutInSeconds = 0.5

    /// How long a program may take to list its own verbs, which node-based ones take longer over.
    static let helpTimeoutInSeconds = 2.0

    /// How many values one read may return, so a huge repository or directory stays cheap.
    static let limit = 200

    /// How many verbs a program may list, since git alone lists over three hundred and a cut list would deny the rest.
    static let verbLimit = 400

    /// How many programs may be remembered, since `PATH` on a developer's Mac holds thousands.
    static let executableLimit = 2_000

    /// Where `git` is looked for, in the order a developer's Mac usually keeps it.
    static let gitPaths = [
        "/opt/homebrew/bin/git", "/usr/local/bin/git",
        "/Library/Developer/CommandLineTools/usr/bin/git",
        "/Applications/Xcode.app/Contents/Developer/usr/bin/git",
    ]

    /// Where programs are looked for beyond the `PATH` this process was launched with, which an app's is not the shell's.
    static let extraSearchPaths = ["/opt/homebrew/bin", "/usr/local/bin"]

    /// The shell configuration read for aliases, relative to the user's home directory.
    static let aliasFiles = [".zshrc", ".zshenv", ".bashrc", ".bash_profile", ".aliases"]

    /// The names a Makefile goes by, in the order make itself tries them.
    static let makefiles = ["GNUmakefile", "makefile", "Makefile"]

    /// The package managers whose `run` verb takes the project's scripts, and whose own verbs those scripts join.
    static let scriptRunners: Set<String> = ["npm", "yarn", "pnpm", "bun"]

    public init() {}

    public func values(of kind: EnvironmentKind, in directory: String) async -> [String]? {
        let path = (directory as NSString).expandingTildeInPath
        switch kind {
        case .branch: return await branches(in: path)
        case .entries(let under): return entries(under: under, from: path, directoriesOnly: false)
        case .directories(let under): return entries(under: under, from: path, directoriesOnly: true)
        case .executable: return executables()
        case .alias: return aliases()
        case .subcommand(let program): return await verbs(of: program, in: path)
        case .gitAlias: return await gitAliases(in: path)
        }
    }

    /// The repository's refs by their short names — branches, tags and remote branches — absent when the directory is not one or `git` is missing.
    private func branches(in directory: String) async -> [String]? {
        guard let git = Self.gitPaths.first(where: FileManager.default.isExecutableFile(atPath:)) else {
            return nil
        }
        let output = await run(
            git,
            arguments: [
                "-C", directory, "for-each-ref", "--count=\(Self.verbLimit)",
                "--format=%(refname:short)", "refs/heads", "refs/tags", "refs/remotes",
            ])
        return output?.split(separator: "\n").map(String.init)
    }

    /// What one directory holds, hidden entries included since a dotfile is named on purpose; nothing where the directory does not exist, and no answer where it cannot be read.
    private func entries(under: String, from directory: String, directoriesOnly: Bool) -> [String]? {
        let path = Self.resolve(under, from: directory)
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: path, isDirectory: &isDirectory), isDirectory.boolValue
        else {
            return []
        }
        guard let names = try? FileManager.default.contentsOfDirectory(atPath: path) else { return nil }
        let kept = directoriesOnly ? names.filter { Self.isDirectory("\(path)/\($0)") } : names
        return Array(kept.sorted().prefix(Self.limit))
    }

    /// A path as the shell would read it from the terminal's directory: from root or home as given, otherwise from there.
    static func resolve(_ under: String, from directory: String) -> String {
        let expanded = (under as NSString).expandingTildeInPath
        let joined = expanded.hasPrefix("/") ? expanded : "\(directory)/\(expanded)"
        return (joined as NSString).standardizingPath
    }

    private static func isDirectory(_ path: String) -> Bool {
        var isDirectory: ObjCBool = false
        return FileManager.default.fileExists(atPath: path, isDirectory: &isDirectory)
            && isDirectory.boolValue
    }

    /// Every program on the search path.
    private func executables() -> [String] {
        var found: [String] = []
        for directory in Self.searchPaths() {
            guard found.count < Self.executableLimit else { break }
            for name in visible(in: directory)
            where FileManager.default.isExecutableFile(atPath: "\(directory)/\(name)") {
                found.append(name)
            }
        }
        return found
    }

    /// The directories programs are looked for in: the launch `PATH`, then where Homebrew and installers put them.
    static func searchPaths() -> [String] {
        let launched = (ProcessInfo.processInfo.environment["PATH"] ?? "").split(separator: ":").map(
            String.init)
        var seen: Set<String> = []
        return (launched + extraSearchPaths).filter { seen.insert($0).inserted }
    }

    /// The visible entries of one directory, empty when it cannot be read.
    private func visible(in directory: String) -> [String] {
        let contents = (try? FileManager.default.contentsOfDirectory(atPath: directory)) ?? []
        return contents.filter { !$0.hasPrefix(".") }
    }

    /// The verbs one program takes here: git's from git, make's from the Makefile, a runner's from the project, the rest from the program's help.
    private func verbs(of program: String, in directory: String) async -> [String]? {
        switch program {
        case "git":
            return await gitSubcommands(in: directory)
        case "make", "just":
            return Self.makefiles.compactMap {
                try? String(contentsOfFile: "\(directory)/\($0)", encoding: .utf8)
            }
            .first.map(MakefileTargets.names(in:))
        case let runner where runner.hasSuffix(" run"):
            return scripts(in: directory)
        case let runner where Self.scriptRunners.contains(runner):
            guard let listed = await helpCommands(of: runner, in: directory) else { return nil }
            return listed + (scripts(in: directory) ?? [])
        default:
            return await helpCommands(of: program, in: directory)
        }
    }

    /// How a program is asked to list its verbs, which is `--help` for most and a listing command for the few that keep one.
    static func listingArguments(for program: String) -> [String] {
        switch program {
        case "cargo": ["--list"]
        case "brew": ["commands", "--quiet"]
        case "npm": ["help"]
        default: ["--help"]
        }
    }

    /// Fewer names than this is a help page without a command list, which is no answer rather than a short one.
    static let fewestListedVerbs = 3

    /// The scripts the project here declares, absent when it has no manifest or one that does not parse.
    private func scripts(in directory: String) -> [String]? {
        (try? String(contentsOfFile: "\(directory)/package.json", encoding: .utf8))
            .flatMap(PackageScripts.names(in:))
    }

    /// The commands a program lists when asked, absent when it is not on the search path, does not answer, or lists none.
    private func helpCommands(of program: String, in directory: String) async -> [String]? {
        guard
            let tool = Self.searchPaths().lazy.map({ "\($0)/\(program)" })
                .first(where: FileManager.default.isExecutableFile(atPath:))
        else { return nil }
        guard
            let output = await run(
                tool, arguments: Self.listingArguments(for: program), in: directory,
                within: Self.helpTimeoutInSeconds)
        else { return nil }
        let names = HelpCommands.names(in: output)
        return names.count >= Self.fewestListedVerbs ? Array(names.prefix(Self.verbLimit)) : nil
    }

    /// Every subcommand this machine's git accepts, asked of git rather than written down here.
    private func gitSubcommands(in directory: String) async -> [String]? {
        guard let git = Self.gitPaths.first(where: FileManager.default.isExecutableFile(atPath:)) else {
            return nil
        }
        let listed = await run(git, arguments: ["-C", directory, "--list-cmds=builtins,main,others,alias"])
        return listed.map { Array($0.split(separator: "\n").map(String.init).prefix(Self.verbLimit)) }
    }

    /// Every name the user's git configuration binds, which no typo model may be allowed to undo.
    private func gitAliases(in directory: String) async -> [String]? {
        guard let git = Self.gitPaths.first(where: FileManager.default.isExecutableFile(atPath:)) else {
            return nil
        }
        // A configuration with no aliases is an exit status of one and an answer of none, not a failure.
        let declared =
            await run(git, arguments: ["-C", directory, "config", "--get-regexp", "^alias\\."]) ?? ""
        return Array(GitAliases.names(in: declared).prefix(Self.limit))
    }

    /// Every alias the user's shell configuration declares, read as text rather than by running it.
    private func aliases() -> [String] {
        let home = FileManager.default.homeDirectoryForCurrentUser
        let text = Self.aliasFiles
            .compactMap { try? String(contentsOf: home.appending(path: $0), encoding: .utf8) }
            .joined(separator: "\n")
        return Array(ShellAliases.names(in: text).prefix(Self.limit))
    }

    /// One bounded run of a program, absent for a failure, a timeout or unreadable output; both streams are read, since help goes to either.
    private func run(
        _ tool: String, arguments: [String], in directory: String? = nil,
        within timeout: Double = SystemEnvironmentReader.timeoutInSeconds
    ) async -> String? {
        let process = Process()
        process.executableURL = URL(filePath: tool)
        process.arguments = arguments
        process.environment = [
            "PATH": Self.searchPaths().joined(separator: ":"), "GIT_TERMINAL_PROMPT": "0", "NO_COLOR": "1",
            "HOME": FileManager.default.homeDirectoryForCurrentUser.path,
        ]
        if let directory { process.currentDirectoryURL = URL(filePath: directory) }

        let output = Pipe()
        process.standardOutput = output
        process.standardError = output
        do {
            try process.run()
        } catch {
            return nil
        }

        // Read before waiting: output that fills the pipe buffer blocks the program writing it.
        let produced = try? output.fileHandleForReading.readToEnd()

        let deadline = Date().addingTimeInterval(timeout)
        while process.isRunning && Date() < deadline {
            try? await Task.sleep(for: .milliseconds(10))
        }
        guard !process.isRunning else {
            process.terminate()
            return nil
        }
        guard process.terminationStatus == 0, let produced else { return nil }
        return String(data: produced, encoding: .utf8)
    }
}
