import Foundation

/// Which program a suggestion may run to list a command's verbs, and the environment it runs in. See `Docs/command-lookups.md`.
enum CommandLookup {
    /// The directories a verb lookup may run a program from, in the order a Mac's default search path has them.
    static let programDirectories = [
        "/usr/bin", "/bin", "/usr/sbin", "/sbin", "/opt/homebrew/bin", "/usr/local/bin",
    ]

    /// Whether `name` is a bare program name, never a path that could reach into a project.
    static func isBareName(_ name: String) -> Bool {
        !name.isEmpty && !name.contains("/") && !name.hasPrefix(".") && !name.contains("\0")
    }

    /// Whether `path` lies inside `directory`, both with symbolic links resolved; the root holds no project.
    static func isInside(_ path: String, _ directory: String) -> Bool {
        let root = (directory as NSString).resolvingSymlinksInPath
        guard root != "/" else { return false }
        let resolved = (path as NSString).resolvingSymlinksInPath
        return resolved == root || resolved.hasPrefix(root + "/")
    }

    /// The directories of `candidates` a program may be run from while a terminal sits in `directory`.
    static func runnableDirectories(_ candidates: [String], outside directory: String) -> [String] {
        candidates.filter { candidate in
            candidate.hasPrefix("/")
                && !candidate.split(separator: "/").contains("node_modules")
                && !isInside(candidate, directory)
        }
    }

    /// The program `name` resolves to from `candidates`, or `nil` when it is not a bare name or would run from the project.
    static func program(
        named name: String, in candidates: [String], outside directory: String,
        isExecutable: (String) -> Bool = FileManager.default.isExecutableFile(atPath:)
    ) -> String? {
        guard isBareName(name) else { return nil }
        return runnableDirectories(candidates, outside: directory).lazy
            .map { "\($0)/\(name)" }
            .first { isExecutable($0) && !isInside($0, directory) }
    }

    /// The whole environment a lookup runs with: the fixed search path, home, and switches that keep tools local and quiet.
    static func environment(searchPath: [String], home: String) -> [String: String] {
        [
            "PATH": searchPath.joined(separator: ":"), "HOME": home, "NO_COLOR": "1",
            "GIT_TERMINAL_PROMPT": "0", "GIT_OPTIONAL_LOCKS": "0",
            "GOTOOLCHAIN": "local", "COREPACK_ENABLE_NETWORK": "0",
        ]
    }
}
