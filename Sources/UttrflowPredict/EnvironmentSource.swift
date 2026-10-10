private import UttrflowCore

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

    /// Whether the answer is the same wherever the terminal is sitting, so one read serves every directory.
    var isMachineWide: Bool {
        switch self {
        case .executable, .alias: true
        case .subcommand(let program): !CommandGrammar.readsTheProject(program)
        case .branch, .entries, .directories, .gitAlias: false
        }
    }

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
    /// Every value of one kind for one directory, narrowed to what has been typed so far where the kind lists names: empty when there are none, absent when the read failed or was too slow.
    func values(of kind: EnvironmentKind, in directory: String, matching prefix: String) async -> [String]?
}

extension EnvironmentReading {
    /// Every value of one kind for one directory, unnarrowed — what a caller with no typed word yet, or no use for one, asks for.
    public func values(of kind: EnvironmentKind, in directory: String) async -> [String]? {
        await values(of: kind, in: directory, matching: "")
    }
}

/// What this machine last said, held briefly so a keystroke never waits on a read.
public actor EnvironmentIndex {
    /// How long an answer about a directory is believed before the machine is asked again.
    public static let lifetimeInSeconds = 5.0

    /// How long an answer about programs and their verbs is believed, since those change when something is installed.
    public static let programLifetimeInSeconds = 60.0

    /// One directory's answer about one kind of thing, cached separately for each prefix it is asked with.
    struct Key: Hashable {
        let kind: EnvironmentKind
        let directory: String
        let prefix: String
    }

    /// How long past its lifetime an answer is still served, which covers the read that replaces it and no more.
    public static let staleGraceInSeconds = 2.0

    /// The longest a listing that keeps failing is left alone, so a program that never answers is asked rarely.
    public static let longestBackoffInSeconds = 600.0

    /// The most answers held at once, so a day of visiting directories and typing paths cannot grow the index without bound.
    public static let capacity = 256

    /// How many of its own lifetimes an expired answer is kept for a refresh before it is dropped.
    static let lifetimesKeptExpired = 4.0

    /// The last answer, when it stops being believed, and when the machine is next asked; a failed read is remembered too, so it is not repeated every keystroke.
    private struct Cached {
        let values: [String]?
        let expires: ContinuousClock.Instant
        /// When the machine is next asked, which a failed read puts off without touching the answer before it.
        let retry: ContinuousClock.Instant
        /// How many reads in a row came back with nothing, which is what the backoff doubles on.
        let failures: Int
        /// When the answer was last asked for, which decides what goes first once the index is full.
        var asked: ContinuousClock.Instant
    }

    /// The half that actually asks the machine.
    private let reader: any EnvironmentReading
    /// What each key last answered, until it stops being believed.
    private var cached: [Key: Cached] = [:]
    /// The reads in flight, one per key, so a burst cannot start a burst of them.
    private var refreshing: [Key: Task<Void, Never>] = [:]
    /// Monotonic seconds, read around each read so an answer's lifetime starts when it lands.
    private let seconds: @Sendable () -> Double

    /// An index over one reader, holding nothing until that reader answers.
    public init(reader: any EnvironmentReading) {
        self.init(reader: reader, seconds: EnvironmentIndex.monotonicSeconds)
    }

    /// An index whose sense of how long a read took is given, which only a test has a reason to do.
    init(reader: any EnvironmentReading, seconds: @escaping @Sendable () -> Double) {
        self.reader = reader
        self.seconds = seconds
    }

    /// The fixed point ``monotonicSeconds()`` counts from.
    private static let origin = ContinuousClock.now

    /// Seconds on the continuous clock since ``origin``.
    static func monotonicSeconds() -> Double {
        let since = origin.duration(to: .now).components
        return Double(since.seconds) + Double(since.attoseconds) / 1e18
    }

    /// What is known right now, asking the machine in the background when that is nothing or stale; absent until it has answered or once long stale.
    public func values(
        of kind: EnvironmentKind, in directory: String, matching prefix: String = "",
        now: ContinuousClock.Instant
    ) -> [String]? {
        // A machine-wide answer is kept under one key, or every directory pays for its own PATH scan.
        let key = Key(kind: kind, directory: kind.isMachineWide ? "" : directory, prefix: prefix)
        let entry = cached[key]
        cached[key]?.asked = now
        if entry.map({ $0.retry <= now }) ?? true { refresh(key, now: now) }
        // An answer long past its lifetime is no fact about the machine now, so it is not served while the new one is read.
        guard let entry,
            now < entry.expires.advanced(by: .seconds(Self.staleGraceInSeconds))
        else { return nil }
        return entry.values
    }

    /// Waits for the reads in flight, which only a test has a reason to do.
    public func settle() async {
        while let task = refreshing.values.first {
            await task.value
        }
    }

    /// Asks the machine once per key, so a burst of keystrokes cannot start a burst of reads.
    private func refresh(_ key: Key, now: ContinuousClock.Instant) {
        guard refreshing[key] == nil else { return }
        refreshing[key] = Task {
            let started = seconds()
            let values = await reader.values(
                of: key.kind, in: key.directory, matching: key.prefix)
            let elapsed = max(0, seconds() - started)
            record(key, values: values, now: now.advanced(by: .seconds(elapsed)))
        }
    }

    /// Believes an answer for the kind's lifetime; a failed read keeps the answer before it and is retried later each time.
    private func record(_ key: Key, values: [String]?, now: ContinuousClock.Instant) {
        let previous = cached[key]
        let asked = max(previous?.asked ?? now, now)
        if let values {
            let expires = now.advanced(by: .seconds(key.kind.lifetimeInSeconds))
            cached[key] = Cached(
                values: values, expires: expires, retry: expires, failures: 0, asked: asked)
        } else {
            let failures = (previous?.failures ?? 0) + 1
            cached[key] = Cached(
                values: previous?.values, expires: previous?.expires ?? now,
                retry: now.advanced(by: .seconds(Self.lifetime(of: key.kind, failures: failures))),
                failures: failures, asked: asked)
        }
        refreshing[key] = nil
        prune(keeping: key, now: now)
    }

    /// How many answers the index holds, which only a test has a reason to ask.
    var count: Int { cached.count }

    /// Drops answers long past their lifetime, then the expired and the least recently asked while over ``capacity``.
    private func prune(keeping kept: Key, now: ContinuousClock.Instant) {
        cached = cached.filter { key, entry in
            key == kept
                || entry.expires.duration(to: now)
                    < .seconds(Self.lifetimesKeptExpired * key.kind.lifetimeInSeconds)
        }
        guard cached.count > Self.capacity else { return }
        let victims = cached.filter { $0.key != kept }
            .sorted {
                ($0.value.expires > now ? 1 : 0, $0.value.asked) < (
                    $1.value.expires > now ? 1 : 0, $1.value.asked
                )
            }
            .prefix(cached.count - Self.capacity)
        for victim in victims { cached[victim.key] = nil }
    }

    /// The kind's own lifetime, doubled per failure in a row up to ``longestBackoffInSeconds``.
    static func lifetime(of kind: EnvironmentKind, failures: Int) -> Double {
        let base = kind.lifetimeInSeconds
        guard failures > 0 else { return base }
        // Doubling by multiplication, so this file needs no maths import.
        var lifetime = base
        for _ in 0..<min(failures, 32) where lifetime < longestBackoffInSeconds { lifetime *= 2 }
        return min(lifetime, longestBackoffInSeconds)
    }
}

/// The completions this machine can supply on its own, which no model can know.
public struct EnvironmentSource: Sendable {
    /// How many of one kind may be offered, so a large directory cannot flood the ranking.
    public static let maximumPerKind = 8

    /// What this machine last said about itself.
    private let index: EnvironmentIndex

    /// A source over one index, which is the only thing it reads from.
    public init(index: EnvironmentIndex) {
        self.index = index
    }

    /// What exists here that finishes the line, empty for any field that is not a terminal.
    public func candidates(
        for surface: Surface, matching typed: String, now: ContinuousClock.Instant
    ) async -> [Candidate] {
        guard TerminalApplications.contains(surface.bundleIdentifier) else { return [] }
        guard let directory = Self.workingDirectory(of: surface),
            let completing = CompletionToken(typed)
        else { return [] }

        var offered: [String] = []
        var seen: Set<String> = []
        for lookup in Verification.offerings(for: completing) {
            for kind in lookup.kinds {
                // Only a name listing is narrowed here: branches and verbs cost the same to read whole, so narrowing them would only fragment their cache.
                let narrowing: String
                switch kind {
                case .entries, .directories: narrowing = lookup.word
                case .branch, .executable, .alias, .subcommand, .gitAlias: narrowing = ""
                }
                let values = await index.values(of: kind, in: directory, matching: narrowing, now: now) ?? []
                for value in Self.matches(values, completing: lookup.word).prefix(Self.maximumPerKind)
                where seen.insert(lookup.prefix + value).inserted {
                    offered.append(lookup.prefix + value)
                }
            }
        }
        return offered.map {
            let text = completing.leading + $0
            return Candidate(
                text: text, source: .environment,
                isIrreversible: DestructiveCommand.matches(text, failClosedOnUnresolved: true))
        }
    }

    /// The directory a terminal is sitting in, absent for a field whose scope is a web host.
    static func workingDirectory(of surface: Surface) -> String? {
        guard let scope = surface.scope, scope.hasPrefix("/") || scope.hasPrefix("~/") else { return nil }
        return scope
    }

    /// Whether a name could go on to finish what has been typed of it, case folded since the filesystem is not case sensitive here.
    static func hasPrefix(_ name: String, _ token: String) -> Bool {
        TextMatching.caseFoldedKey(name).hasPrefix(TextMatching.caseFoldedKey(token))
    }

    /// The values that finish the token, shortest first, since the nearest completion is the likeliest.
    static func matches(_ values: [String], completing token: String) -> [String] {
        values
            .filter { $0.count > token.count && Self.hasPrefix($0, token) }
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
