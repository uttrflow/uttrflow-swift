public import struct Foundation.Date

/// One kind of thing this machine knows about itself, each read a different way.
public enum EnvironmentKind: Sendable, Hashable {
    /// A branch in the repository the terminal is sitting in.
    case branch
    /// A name under a directory, given from the terminal's own: `.` for it, a path from it, from home or from root.
    case entries(under: String)
    /// A directory under one, given the same way.
    case directories(under: String)
    /// A program on `PATH`.
    case executable
    /// A name the user's shell configuration binds to a command.
    case alias
    /// A verb a program takes: git's subcommands, make's targets, the scripts a project declares under `npm run`.
    case subcommand(of: String)
    /// A name the user's git configuration binds to a subcommand.
    case gitAlias

    /// A name in the directory the terminal is sitting in.
    public static let file = EnvironmentKind.entries(under: ".")

    /// A directory in the directory the terminal is sitting in.
    public static let directory = EnvironmentKind.directories(under: ".")

    /// How long an answer is believed: a directory changes with every command, a program's verbs with the program.
    var lifetimeInSeconds: Double {
        switch self {
        case .subcommand, .executable, .alias, .gitAlias: EnvironmentIndex.programLifetimeInSeconds
        case .branch, .entries, .directories: EnvironmentIndex.lifetimeInSeconds
        }
    }
}

/// Reads one kind of fact off this machine, which only the system half can really do.
public protocol EnvironmentReading: Sendable {
    /// Every value of one kind for one directory: empty when there are none, absent when the read failed or was too slow.
    func values(of kind: EnvironmentKind, in directory: String) async -> [String]?
}

/// What this machine last said, held briefly so a keystroke never waits on a read.
public actor EnvironmentIndex {
    /// How long an answer about a directory is believed before the machine is asked again.
    public static let lifetimeInSeconds = 5.0

    /// How long an answer about programs and their verbs is believed, since those change when something is installed.
    public static let programLifetimeInSeconds = 60.0

    /// One directory's answer about one kind of thing.
    struct Key: Hashable {
        let kind: EnvironmentKind
        let directory: String
    }

    /// Values and the moment they stop being believed; a failed read is remembered too, so it is not repeated every keystroke.
    private struct Cached {
        let values: [String]?
        let expires: Date
    }

    private let reader: any EnvironmentReading
    private var cached: [Key: Cached] = [:]
    private var refreshing: [Key: Task<Void, Never>] = [:]

    public init(reader: any EnvironmentReading) {
        self.reader = reader
    }

    /// What is known right now, asking the machine in the background when that is nothing or stale; absent until it has answered.
    public func values(of kind: EnvironmentKind, in directory: String, now: Date) -> [String]? {
        let key = Key(kind: kind, directory: directory)
        let entry = cached[key]
        if entry.map({ $0.expires <= now }) ?? true { refresh(key, now: now) }
        return entry?.values
    }

    /// Waits for the reads in flight, which only a test has a reason to do.
    public func settle() async {
        while let task = refreshing.values.first {
            await task.value
        }
    }

    /// Asks the machine once per key, so a burst of keystrokes cannot start a burst of reads.
    private func refresh(_ key: Key, now: Date) {
        guard refreshing[key] == nil else { return }
        refreshing[key] = Task {
            let values = await reader.values(of: key.kind, in: key.directory)
            record(key, values: values, now: now)
        }
    }

    /// Believes an answer for the kind's lifetime after the keystroke that asked for it.
    private func record(_ key: Key, values: [String]?, now: Date) {
        cached[key] = Cached(values: values, expires: now.addingTimeInterval(key.kind.lifetimeInSeconds))
        refreshing[key] = nil
    }
}

/// The completions this machine can supply on its own, which no model can know.
public struct EnvironmentSource: Sendable {
    /// How many of one kind may be offered, so a large directory cannot flood the ranking.
    public static let maximumPerKind = 8

    private let index: EnvironmentIndex

    public init(index: EnvironmentIndex) {
        self.index = index
    }

    /// What exists here that finishes the line, empty for any field that is not a terminal.
    public func candidates(for surface: Surface, matching typed: String, now: Date) async -> [Candidate] {
        guard let directory = Self.workingDirectory(of: surface),
            let completing = CompletionToken(typed)
        else { return [] }

        var offered: [String] = []
        var seen: Set<String> = []
        for lookup in Verification.offerings(for: completing) {
            for kind in lookup.kinds {
                let values = await index.values(of: kind, in: directory, now: now) ?? []
                for value in Self.matches(values, completing: lookup.word).prefix(Self.maximumPerKind)
                where seen.insert(lookup.prefix + value).inserted {
                    offered.append(lookup.prefix + value)
                }
            }
        }
        return offered.map {
            let text = completing.leading + $0
            return Candidate(
                text: text, source: .environment, isIrreversible: DestructiveCommand.matches(text))
        }
    }

    /// The directory a terminal is sitting in, absent for a field whose scope is a web host.
    static func workingDirectory(of surface: Surface) -> String? {
        guard let scope = surface.scope, scope.hasPrefix("/") || scope.hasPrefix("~/") else { return nil }
        return scope
    }

    /// The values that finish the token, shortest first, since the nearest completion is the likeliest.
    static func matches(_ values: [String], completing token: String) -> [String] {
        let folded = token.lowercased()
        return
            values
            .filter { $0.count > token.count && $0.lowercased().hasPrefix(folded) }
            .sorted { ($0.count, $0) < ($1.count, $1) }
    }
}

/// Reads the names a shell binds to commands, which is the one environment fact that is text.
enum ShellAliases {
    /// Every alias name declared in a shell's configuration, in the order it declares them.
    static func names(in configuration: String) -> [String] {
        configuration.split(separator: "\n").compactMap(name(in:))
    }

    /// The name one line binds, absent for anything that is not a plain alias declaration.
    private static func name(in line: some StringProtocol) -> String? {
        let declaration = line.drop { $0 == " " || $0 == "\t" }
        guard declaration.hasPrefix("alias ") else { return nil }
        let binding = declaration.dropFirst(6).drop { $0 == " " }
        guard let equals = binding.firstIndex(of: "=") else { return nil }
        let name = binding[..<equals]
        guard !name.isEmpty, name.allSatisfy(isNameCharacter) else { return nil }
        return String(name)
    }

    /// What a name may be made of, which excludes the flags and quoting a shell also accepts.
    private static func isNameCharacter(_ character: Character) -> Bool {
        character.isLetter || character.isNumber || character == "_" || character == "-"
            || character == "."
    }
}

/// Reads the names git binds to subcommands, which is the half of "wrong" that is actually right.
enum GitAliases {
    /// Every alias name in the output of `git config --get-regexp`, in the order it lists them.
    static func names(in configuration: String) -> [String] {
        configuration.split(separator: "\n").compactMap(name(in:))
    }

    /// The name one line binds, absent for anything that is not an alias declaration.
    private static func name(in line: some StringProtocol) -> String? {
        guard line.hasPrefix("alias.") else { return nil }
        let name = line.dropFirst(6).prefix { $0 != " " }
        guard !name.isEmpty else { return nil }
        return String(name)
    }
}
