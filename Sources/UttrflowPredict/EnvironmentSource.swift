public import struct Foundation.Date

/// One kind of thing this machine knows about itself, each read a different way.
public enum EnvironmentKind: Sendable, Hashable {
    /// A branch in the repository the terminal is sitting in.
    case branch
    /// A name in the directory the terminal is sitting in.
    case file
    /// A program on `PATH`.
    case executable
    /// A name the user's shell configuration binds to a command.
    case alias
    /// A subcommand the git on this machine accepts.
    case gitSubcommand
    /// A name the user's git configuration binds to a subcommand.
    case gitAlias
}

/// Reads one kind of fact off this machine, which only the system half can really do.
public protocol EnvironmentReading: Sendable {
    /// Every value of one kind for one directory, empty when the read fails or is too slow.
    func values(of kind: EnvironmentKind, in directory: String) async -> [String]
}

/// What this machine last said, held briefly so a keystroke never waits on a read.
public actor EnvironmentIndex {
    /// How long an answer is believed before the machine is asked again.
    public static let lifetimeInSeconds = 5.0

    /// One directory's answer about one kind of thing.
    struct Key: Hashable {
        let kind: EnvironmentKind
        let directory: String
    }

    /// Values and the moment they stop being believed.
    private struct Cached {
        let values: [String]
        let expires: Date
    }

    private let reader: any EnvironmentReading
    private var cached: [Key: Cached] = [:]
    private var refreshing: [Key: Task<Void, Never>] = [:]

    public init(reader: any EnvironmentReading) {
        self.reader = reader
    }

    /// What is known right now, asking the machine in the background when that is nothing or stale.
    public func values(of kind: EnvironmentKind, in directory: String, now: Date) -> [String] {
        let key = Key(kind: kind, directory: directory)
        let entry = cached[key]
        if entry.map({ $0.expires <= now }) ?? true { refresh(key, now: now) }
        return entry?.values ?? []
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

    /// Believes an answer until `lifetimeInSeconds` after the keystroke that asked for it.
    private func record(_ key: Key, values: [String], now: Date) {
        cached[key] = Cached(values: values, expires: now.addingTimeInterval(Self.lifetimeInSeconds))
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
        for kind in Self.kinds(completingFirstWord: completing.isFirstWord) {
            let values = await index.values(of: kind, in: directory, now: now)
            for value in Self.matches(values, completing: completing.token).prefix(Self.maximumPerKind)
            where seen.insert(value).inserted {
                offered.append(value)
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

    /// What is worth completing here: a program at the start of a line, its arguments after it.
    static func kinds(completingFirstWord: Bool) -> [EnvironmentKind] {
        completingFirstWord ? [.executable, .alias] : [.branch, .file]
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

/// The word at the end of a command line, and the line it has to be put back into.
struct CompletionToken: Equatable {
    /// Everything before the word, kept because a candidate carries the whole line.
    let leading: String
    /// The word being completed, never empty.
    let token: String

    /// How many whole words come before this one, which tells a command from its arguments.
    var precedingWords: Int { leading.split(separator: " ").count }

    /// Whether the word is the command rather than one of its arguments.
    var isFirstWord: Bool { precedingWords == 0 }

    /// The command this word belongs to, absent when it is the command itself.
    var command: String? { leading.split(separator: " ").first.map(String.init) }

    /// A word anywhere in a line, for the words a completion adds behind the one being typed.
    init(leading: String, token: String) {
        self.leading = leading
        self.token = token
    }

    /// The word a line ends on, absent when it ends on a space and there is nothing to finish.
    init?(_ typed: String) {
        guard let last = typed.split(separator: " ", omittingEmptySubsequences: false).last,
            !last.isEmpty
        else { return nil }
        leading = String(typed.dropLast(last.count))
        token = String(last)
    }
}

/// Reads the names a shell binds to commands, which is the one environment fact that is text.
public enum ShellAliases {
    /// Every alias name declared in a shell's configuration, in the order it declares them.
    public static func names(in configuration: String) -> [String] {
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
public enum GitAliases {
    /// Every alias name in the output of `git config --get-regexp`, in the order it lists them.
    public static func names(in configuration: String) -> [String] {
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
