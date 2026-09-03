import Foundation

/// Reads what actually exists on this Mac, which is the one thing a language model cannot know.
public struct SystemEnvironmentReader: EnvironmentReading {
    /// How long a read may take before its answer is thrown away, since a keystroke is waiting.
    static let timeoutInSeconds = 0.5

    /// How many values one read may return, so a huge repository or directory stays cheap.
    static let limit = 200

    /// How many programs may be remembered, since `PATH` on a developer's Mac holds thousands.
    static let executableLimit = 2_000

    /// Where `git` is looked for, in the order a developer's Mac usually keeps it.
    static let gitPaths = [
        "/opt/homebrew/bin/git", "/usr/local/bin/git",
        "/Library/Developer/CommandLineTools/usr/bin/git",
        "/Applications/Xcode.app/Contents/Developer/usr/bin/git",
    ]

    /// The shell configuration read for aliases, relative to the user's home directory.
    static let aliasFiles = [".zshrc", ".zshenv", ".bashrc", ".bash_profile", ".aliases"]

    public init() {}

    public func values(of kind: EnvironmentKind, in directory: String) async -> [String] {
        let path = (directory as NSString).expandingTildeInPath
        switch kind {
        case .branch: return await branches(in: path)
        case .file: return names(in: path)
        case .executable: return executables()
        case .alias: return aliases()
        case .gitSubcommand: return await gitSubcommands(in: path)
        case .gitAlias: return await gitAliases(in: path)
        }
    }

    /// The repository's local branches, empty when the directory is not one or `git` is missing.
    private func branches(in directory: String) async -> [String] {
        guard let git = Self.gitPaths.first(where: FileManager.default.isExecutableFile(atPath:)) else {
            return []
        }
        let output = await run(
            git,
            arguments: [
                "-C", directory, "for-each-ref", "--count=\(Self.limit)",
                "--format=%(refname:short)", "refs/heads",
            ])
        return output.split(separator: "\n").map(String.init)
    }

    /// What the directory holds, without the hidden entries a user does not mean to name.
    private func names(in directory: String) -> [String] {
        Array(contents(of: directory).prefix(Self.limit))
    }

    /// Every program on the `PATH` this process was launched with.
    private func executables() -> [String] {
        var found: [String] = []
        for directory in (ProcessInfo.processInfo.environment["PATH"] ?? "").split(separator: ":") {
            guard found.count < Self.executableLimit else { break }
            for name in contents(of: String(directory))
            where FileManager.default.isExecutableFile(atPath: "\(directory)/\(name)") {
                found.append(name)
            }
        }
        return found
    }

    /// The visible entries of one directory, empty when it cannot be read.
    private func contents(of directory: String) -> [String] {
        let contents = (try? FileManager.default.contentsOfDirectory(atPath: directory)) ?? []
        return contents.filter { !$0.hasPrefix(".") }
    }

    /// Every subcommand this machine's git accepts, asked of git rather than written down here.
    private func gitSubcommands(in directory: String) async -> [String] {
        guard let git = Self.gitPaths.first(where: FileManager.default.isExecutableFile(atPath:)) else {
            return []
        }
        let listed = await run(
            git, arguments: ["-C", directory, "--list-cmds=builtins,main,others,alias"])
        return Array(listed.split(separator: "\n").map(String.init).prefix(Self.limit))
    }

    /// Every name the user's git configuration binds, which no typo model may be allowed to undo.
    private func gitAliases(in directory: String) async -> [String] {
        guard let git = Self.gitPaths.first(where: FileManager.default.isExecutableFile(atPath:)) else {
            return []
        }
        let declared = await run(
            git, arguments: ["-C", directory, "config", "--get-regexp", "^alias\\."])
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

    /// One bounded run of a program, answering empty for a failure, a timeout or unreadable output.
    private func run(_ tool: String, arguments: [String]) async -> String {
        let process = Process()
        process.executableURL = URL(filePath: tool)
        process.arguments = arguments
        process.environment = ["PATH": "/usr/bin:/bin", "GIT_TERMINAL_PROMPT": "0"]

        let output = Pipe()
        process.standardOutput = output
        process.standardError = Pipe()
        do {
            try process.run()
        } catch {
            return ""
        }

        // Read before waiting: output that fills the pipe buffer blocks the program writing it.
        let produced = try? output.fileHandleForReading.readToEnd()

        let deadline = Date().addingTimeInterval(Self.timeoutInSeconds)
        while process.isRunning && Date() < deadline {
            try? await Task.sleep(for: .milliseconds(10))
        }
        guard !process.isRunning else {
            process.terminate()
            return ""
        }
        guard process.terminationStatus == 0, let produced else { return "" }
        return String(data: produced, encoding: .utf8) ?? ""
    }
}
