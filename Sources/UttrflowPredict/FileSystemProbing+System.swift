public import Foundation

private import Synchronization

/// This Mac's filesystem, asked by `stat`, `access` and bounded reads alone, with a network volume given a deadline.
public struct SystemFileSystem: FileSystemProbing {
    /// How long a stat on a volume that may be remote is waited for before it is given up on.
    public static let remoteBudget = DispatchTimeInterval.milliseconds(20)

    /// How long a volume that missed its deadline is left alone, so a hung mount costs one wait rather than one per keystroke.
    public static let slowVolumeLifetimeInSeconds = 30.0

    /// Where a path may sit on a volume that answers over a network, and so may not answer at all.
    static let remoteRoots = ["/Volumes/", "/Network/", "/net/"]

    /// Where programs are commonly installed beyond what `PATH` and `/etc/paths` name, since an app does not inherit the shell's `PATH`.
    static let extraSearchPaths = [
        "/opt/homebrew/bin", "/opt/homebrew/sbin", "/usr/local/bin", "/usr/local/sbin", "/usr/local/go/bin",
        "~/.local/bin", "~/bin", "~/.cargo/bin", "~/go/bin", "~/.bun/bin", "~/.deno/bin",
    ]

    public let homeDirectory: String
    public let searchPaths: [String]
    /// How long a remote stat may take.
    private let budget: DispatchTimeInterval
    /// The stat itself, injected so a test can stand in for the disk.
    private let probe: @Sendable (String) -> PathKind
    /// How a remote stat is held to its budget, injected so a test can miss the deadline without blocking a thread.
    private let timeBox: @Sendable (DispatchTimeInterval, @escaping @Sendable () -> PathKind) -> PathKind?
    /// The clock a slow volume is remembered on.
    private let now: @Sendable () -> Date
    /// The volumes that missed a deadline, and until when they are skipped.
    private let slow = SlowVolumes()

    /// The filesystem of this Mac, its search path read from the launch environment and `/etc/paths`.
    public init(
        environment: [String: String] = ProcessInfo.processInfo.environment,
        homeDirectory: String = NSHomeDirectory(), budget: DispatchTimeInterval = Self.remoteBudget,
        probe: @escaping @Sendable (String) -> PathKind = Self.statKind,
        timeBox: @escaping @Sendable (DispatchTimeInterval, @escaping @Sendable () -> PathKind) -> PathKind? =
            { Self.timeBoxed(within: $0, $1) },
        now: @escaping @Sendable () -> Date = { Date() }
    ) {
        self.homeDirectory = homeDirectory
        let listed =
            ["/etc/paths"]
            + ((try? FileManager.default.contentsOfDirectory(atPath: "/etc/paths.d")) ?? [])
            .sorted().map { "/etc/paths.d/\($0)" }
        searchPaths = Self.searchPaths(
            launch: environment["PATH"] ?? "",
            pathFiles: listed.compactMap { try? String(contentsOfFile: $0, encoding: .utf8) },
            home: homeDirectory)
        self.budget = budget
        self.probe = probe
        self.timeBox = timeBox
        self.now = now
    }

    /// The launch `PATH`, then `/etc/paths` and its directory, then the usual install locations: absolute, `~` expanded, each once.
    static func searchPaths(launch: String, pathFiles: [String], home: String) -> [String] {
        let named =
            launch.split(separator: ":").map(String.init)
            + pathFiles.flatMap { $0.split(whereSeparator: \.isNewline).map(String.init) }
            + extraSearchPaths
        var seen: Set<String> = []
        return named.map { $0.trimmingCharacters(in: .whitespaces) }
            .map { $0 == "~" || $0.hasPrefix("~/") ? home + $0.dropFirst() : $0 }
            .filter { $0.hasPrefix("/") && seen.insert($0).inserted }
    }

    public func kind(atPath path: String) -> PathKind {
        guard let volume = Self.remoteVolume(of: path) else { return probe(path) }
        guard !slow.isSlow(volume, at: now()) else { return .unknown }
        let probe = self.probe
        guard let kind = timeBox(budget, { probe(path) }) else {
            slow.markSlow(volume, until: now().addingTimeInterval(Self.slowVolumeLifetimeInSeconds))
            return .unknown
        }
        return kind
    }

    public func contents(ofFile path: String, limit: Int) -> String? {
        guard Self.remoteVolume(of: path) == nil, case .file = probe(path),
            let handle = FileHandle(forReadingAtPath: path)
        else { return nil }
        defer { try? handle.close() }
        guard let data = try? handle.read(upToCount: limit + 1), data.count <= limit else { return nil }
        return String(data: data, encoding: .utf8)
    }

    public func names(inDirectory path: String, limit: Int) -> [String]? {
        guard Self.remoteVolume(of: path) == nil,
            let names = try? FileManager.default.contentsOfDirectory(atPath: path), names.count <= limit
        else { return nil }
        return names
    }

    /// What `stat` says one path names, following links; a path that cannot be asked about is unknown rather than missing.
    public static func statKind(_ path: String) -> PathKind {
        var info = stat()
        guard stat(path, &info) == 0 else {
            return errno == ENOENT || errno == ENOTDIR ? .missing : .unknown
        }
        guard info.st_mode & S_IFMT != S_IFDIR else { return .directory }
        return .file(executable: info.st_mode & S_IFMT == S_IFREG && access(path, X_OK) == 0)
    }

    /// The volume a path is on when that volume may be remote, as `/Volumes/Name`; absent for the startup disk.
    static func remoteVolume(of path: String) -> String? {
        guard let root = remoteRoots.first(where: path.hasPrefix) else { return nil }
        let name = path.dropFirst(root.count).prefix { $0 != "/" }
        return name.isEmpty ? nil : root + name
    }

    /// Runs work on a queue of its own and waits for it only as long as the budget, absent when it has not finished.
    public static func timeBoxed<Value: Sendable>(
        within budget: DispatchTimeInterval, _ work: @escaping @Sendable () -> Value
    ) -> Value? {
        let result = Outcome<Value>()
        let done = DispatchSemaphore(value: 0)
        // A queue of its own gets a thread at once, where a busy shared pool could leave the work unstarted past the budget.
        DispatchQueue(label: "com.uttrflow.predict.remote-stat", qos: .utility).async {
            result.set(work())
            done.signal()
        }
        guard done.wait(timeout: .now() + budget) == .success else { return nil }
        return result.value
    }
}

/// One answer handed from the thread that did the work to the one waiting on it.
private final class Outcome<Value: Sendable>: Sendable {
    private let held = Mutex<Value?>(nil)

    func set(_ value: Value) { held.withLock { $0 = value } }

    var value: Value? { held.withLock { $0 } }
}

/// The volumes that missed a deadline, each skipped until its time is up.
private final class SlowVolumes: Sendable {
    private let until = Mutex<[String: Date]>([:])

    func isSlow(_ volume: String, at moment: Date) -> Bool {
        until.withLock { ($0[volume] ?? .distantPast) > moment }
    }

    func markSlow(_ volume: String, until moment: Date) {
        until.withLock { $0[volume] = moment }
    }
}
