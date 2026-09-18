// Tests for which programs a command lookup runs, with what, and that a run which overstays is killed with all it started.

import Darwin
import Foundation
import Synchronization
import Testing

@testable import UttrflowPredict

/// A launcher that runs nothing and remembers every launch it was asked for.
private final class RecordingLauncher: ProgramLaunching {
    /// Every launch asked for, in order.
    private let seen = Mutex<[ProgramLaunch]>([])

    var launches: [ProgramLaunch] { seen.withLock { $0 } }

    /// Records the launch and answers with a help page listing three verbs.
    func output(of launch: ProgramLaunch) async -> String? {
        seen.withLock { $0.append(launch) }
        return "Commands:\n  build   Build it\n  test    Test it\n  run     Run it\n"
    }
}

/// A project folder holding its own copies of common tools, and a standard folder holding the installed ones.
private struct Workspace {
    let root: URL
    let project: String
    let installed: String

    /// Lays out both folders under a new temporary directory.
    init() throws {
        root = FileManager.default.temporaryDirectory.appending(path: "lookup-\(UUID().uuidString)")
        project = root.appending(path: "project").path
        installed = root.appending(path: "installed").path
        for folder in ["\(project)/node_modules/.bin", "\(project)/vendor/bin", installed] {
            try FileManager.default.createDirectory(atPath: folder, withIntermediateDirectories: true)
        }
        for tool in ["yarn", "go", "npm", "cargo", "docker"] { try Self.program(at: "\(installed)/\(tool)") }
        for tool in ["yarn", "localtool"] { try Self.program(at: "\(project)/node_modules/.bin/\(tool)") }
        try Self.program(at: "\(project)/vendor/bin/vendored")
        try Self.program(at: "\(project)/tool")
        try FileManager.default.createSymbolicLink(
            atPath: "\(installed)/linked", withDestinationPath: "\(project)/node_modules/.bin/yarn")
        try Data(#"{"scripts":{"dev":"x"}}"#.utf8).write(to: URL(filePath: "\(project)/package.json"))
    }

    /// An executable file that is never run.
    private static func program(at path: String) throws {
        try Data("#!/bin/sh\nexit 1\n".utf8).write(to: URL(filePath: path))
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: path)
    }

    /// The search directories a careless launcher would use: the standard one, and the project's own.
    var directories: [String] {
        [installed, "node_modules/.bin", "\(project)/node_modules/.bin", "\(project)/vendor/bin", project]
    }

    /// Whether `path`, with links resolved, lies in the project.
    func isInProject(_ path: String) -> Bool {
        let resolved = (path as NSString).resolvingSymlinksInPath
        let folder = (project as NSString).resolvingSymlinksInPath
        return resolved == folder || resolved.hasPrefix(folder + "/")
    }
}

@Suite("Looking up a command's verbs")
struct CommandLookupTests {
    /// The environment variables a lookup may carry, and nothing else.
    private static let allowedVariables: Set<String> = [
        "PATH", "HOME", "NO_COLOR", "GIT_TERMINAL_PROMPT", "GIT_OPTIONAL_LOCKS", "GOTOOLCHAIN",
        "COREPACK_ENABLE_NETWORK",
    ]

    @Test("never runs a program the project holds, and runs the installed ones with nothing of the project")
    func noProjectProgramRuns() async throws {
        let workspace = try Workspace()
        defer { try? FileManager.default.removeItem(at: workspace.root) }
        let launcher = RecordingLauncher()
        let reader = SystemEnvironmentReader(launcher: launcher, programDirectories: workspace.directories)

        let asked = [
            "yarn", "go", "npm", "cargo", "docker", "git", "localtool", "vendored", "linked", "tool",
            "./tool",
            "../project/tool", "node_modules/.bin/yarn", ".bin", "",
        ]
        for program in asked { _ = await reader.values(of: .subcommand(of: program), in: workspace.project) }
        _ = await reader.values(of: .gitAlias, in: workspace.project)

        let launches = launcher.launches
        let named = Set(launches.map { ($0.executable as NSString).lastPathComponent })
        #expect(named.isSuperset(of: ["yarn", "go", "npm", "cargo", "docker"]))
        #expect(named.isDisjoint(with: ["localtool", "vendored", "linked", "tool"]))
        for launch in launches {
            #expect(!workspace.isInProject(launch.executable), "ran \(launch.executable)")
            #expect(
                launch.executable.hasPrefix(workspace.installed + "/")
                    || SystemEnvironmentReader.gitPaths.contains(launch.executable))
            #expect(Set(launch.environment.keys).isSubset(of: Self.allowedVariables))
            let path = launch.environment["PATH", default: ""].split(separator: ":").map(String.init)
            #expect(path.allSatisfy { $0.hasPrefix("/") && !workspace.isInProject($0) })
            #expect(!path.contains { $0.contains("node_modules") })
        }
    }

    @Test("names the terminal's folder to git only as the repository to read, never to a program as its own")
    func theFolderIsNeverAWorkingDirectory() async throws {
        let workspace = try Workspace()
        defer { try? FileManager.default.removeItem(at: workspace.root) }
        let launcher = RecordingLauncher()
        let reader = SystemEnvironmentReader(launcher: launcher, programDirectories: workspace.directories)

        for program in ["yarn", "go", "npm", "cargo", "git"] {
            _ = await reader.values(of: .subcommand(of: program), in: workspace.project)
        }
        _ = await reader.values(of: .gitAlias, in: workspace.project)

        for launch in launcher.launches where !SystemEnvironmentReader.gitPaths.contains(launch.executable) {
            #expect(!launch.arguments.contains { $0.contains(workspace.project) })
        }
        for launch in launcher.launches where launch.arguments.contains(workspace.project) {
            #expect(
                launch.arguments.starts(with: ["-C", workspace.project, "config", "--get-regexp"])
                    || launch.arguments.contains("for-each-ref"))
        }
    }

    @Test("resolves only bare names, and never from a relative, module or project directory")
    func resolution() {
        let folder = "/work/app"
        let everywhere: (String) -> Bool = { _ in true }
        #expect(
            CommandLookup.program(named: "yarn", in: ["/usr/bin"], outside: folder, isExecutable: everywhere)
                == "/usr/bin/yarn")
        #expect(
            CommandLookup.program(
                named: "yarn", in: ["/usr/bin"], outside: folder, isExecutable: { _ in false }) == nil)
        for name in ["", "./yarn", "../yarn", ".yarn", "bin/yarn", "/usr/bin/yarn"] {
            #expect(
                CommandLookup.program(
                    named: name, in: ["/usr/bin"], outside: folder, isExecutable: everywhere) == nil)
        }
        let unsafe = ["bin", "./bin", "/x/node_modules/.bin", "/work/app", "/work/app/bin"]
        #expect(CommandLookup.runnableDirectories(unsafe + ["/usr/bin"], outside: folder) == ["/usr/bin"])
        #expect(CommandLookup.runnableDirectories(["/usr/bin"], outside: "/") == ["/usr/bin"])
    }

    @Test("the standard directories are system and package-manager ones only")
    func standardDirectories() {
        #expect(CommandLookup.programDirectories.allSatisfy { $0.hasPrefix("/") })
        #expect(!CommandLookup.programDirectories.contains { $0.hasPrefix(NSHomeDirectory()) })
        let environment = CommandLookup.environment(searchPath: ["/usr/bin"], home: "/home")
        #expect(Set(environment.keys) == Self.allowedVariables)
        #expect(environment["GOTOOLCHAIN"] == "local")
    }
}

/// Whether the process `pid` has exited, waiting on the kernel's exit notice rather than a clock.
private func hasExited(_ pid: pid_t) -> Bool {
    let queue = kqueue()
    defer { close(queue) }
    var change = kevent(
        ident: UInt(pid), filter: Int16(EVFILT_PROC), flags: UInt16(EV_ADD | EV_ONESHOT), fflags: NOTE_EXIT,
        data: 0, udata: nil)
    guard kevent(queue, &change, 1, nil, 0, nil) == 0 else { return errno == ESRCH }
    var event = kevent()
    // A bound so a broken kill fails the test rather than hanging it; an exit arrives long before.
    var bound = timespec(tv_sec: 30, tv_nsec: 0)
    return kevent(queue, nil, 0, &event, 1, &bound) == 1
}

/// A launch of `/bin/sh -c script` with the given extra arguments.
private func shell(_ script: String, _ arguments: [String] = [], timeout: Double = 30) -> ProgramLaunch {
    ProgramLaunch(
        executable: "/bin/sh", arguments: ["-c", script, "sh"] + arguments,
        environment: ["PATH": "/usr/bin:/bin"], timeout: timeout)
}

@Suite("Running a lookup's program", .timeLimit(.minutes(1)))
struct SpawnedProgramLauncherTests {
    @Test("runs in a fresh empty directory that is gone afterwards, never the caller's")
    func anEmptyDirectory() async throws {
        let output = try #require(await SpawnedProgramLauncher().output(of: shell("pwd; ls -A | wc -l")))
        let lines = output.split(separator: "\n").map { $0.trimmingCharacters(in: .whitespaces) }
        let directory = try #require(lines.first)
        #expect(directory.contains("uttrflow-help."))
        #expect(directory != FileManager.default.currentDirectoryPath)
        #expect(lines.last == "0")
        #expect(!FileManager.default.fileExists(atPath: directory))
    }

    @Test("gives the program exactly the environment it was handed")
    func exactlyTheEnvironment() async throws {
        let launch = ProgramLaunch(
            executable: "/usr/bin/env", arguments: [], environment: ["PATH": "/usr/bin", "ONLY": "this"],
            timeout: 30)
        let output = try #require(await SpawnedProgramLauncher().output(of: launch))
        #expect(Set(output.split(separator: "\n").map(String.init)) == ["PATH=/usr/bin", "ONLY=this"])
    }

    @Test("has no answer for a program that fails or cannot start")
    func failures() async {
        #expect(await SpawnedProgramLauncher().output(of: shell("echo partial; exit 3")) == nil)
        let missing = ProgramLaunch(
            executable: "/nonexistent/tool", arguments: [], environment: [:], timeout: 30)
        #expect(await SpawnedProgramLauncher().output(of: missing) == nil)
    }

    @Test("kills a program that overstays, and what it started, however the pipe is held")
    func aTimeoutKillsTheGroup() async throws {
        let marker = FileManager.default.temporaryDirectory.appending(path: "lookup-\(UUID().uuidString)")
            .path
        defer { try? FileManager.default.removeItem(atPath: marker) }
        // Time runs out only once the program has started a child that shares its pipe.
        let started = Date(timeIntervalSinceReferenceDate: 0)
        let launcher = SpawnedProgramLauncher(now: {
            FileManager.default.fileExists(atPath: marker) ? .distantFuture : started
        })

        let output = await launcher.output(
            of: shell(#"sleep 1000 & echo $! > "$1.tmp"; mv "$1.tmp" "$1"; wait"#, [marker]))

        #expect(output == nil)
        let child = try #require(
            pid_t(
                try String(contentsOfFile: marker, encoding: .utf8).trimmingCharacters(
                    in: .whitespacesAndNewlines)))
        #expect(hasExited(child))
    }

    @Test("keeps what a program wrote when it exits while a child still holds the pipe, and kills the child")
    func aLingeringChild() async throws {
        let output = try #require(await SpawnedProgramLauncher().output(of: shell("sleep 1000 & echo $!")))
        let child = try #require(pid_t(output.trimmingCharacters(in: .whitespacesAndNewlines)))
        #expect(hasExited(child))
    }

    @Test("has no answer for a program that writes more than the limit, and keeps one that writes less")
    func tooMuchOutput() async throws {
        let eightKilobytes = ProgramLaunch(
            executable: "/usr/bin/head", arguments: ["-c", "8192", "/dev/zero"], environment: [:], timeout: 30
        )
        #expect(await SpawnedProgramLauncher(outputLimit: 4_096).output(of: eightKilobytes) == nil)
        let kept = try #require(await SpawnedProgramLauncher(outputLimit: 16_384).output(of: eightKilobytes))
        #expect(kept.utf8.count == 8_192)
    }
}
