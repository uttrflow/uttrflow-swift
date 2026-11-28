// One row of `Docs/probe-log.md`: where, when and on which build a probe's number was measured.
public import Foundation
import UttrflowCore

/// A class of host a budget is stated against, spelled the same in every row and in the hosts note.
public enum HostClass: String, Sendable, CaseIterable {
    case minimumSpec = "minimum-spec"
    case baseChip = "base chip"
    case quiet = "quiet"

    /// The memory of the smallest Mac the budgets are written for.
    public static let minimumSpecBytes: Int64 = HardwareFloor.minimumMemoryBytes

    /// The chip-name words that mark a tier above the base chip of a generation.
    public static let chipTiers: Set<String> = ["Pro", "Max", "Ultra"]

    /// The classes this host and its load at the moment of measuring belong to, in declaration order.
    public static func classes(of machine: MachineDescription, load: HostLoad) -> [HostClass] {
        allCases.filter { $0.admits(machine, load) }
    }

    private func admits(_ machine: MachineDescription, _ load: HostLoad) -> Bool {
        switch self {
        case .minimumSpec:
            return machine.memoryBytes <= Self.minimumSpecBytes
        case .baseChip:
            let words = machine.chip.split(separator: " ").map(String.init)
            return words.first == "Apple" && words.count == 2 && !Self.chipTiers.contains(words[1])
        case .quiet:
            return load.isQuiet
        }
    }
}

/// How busy the host was when it measured, which is what separates a quiet run from a loaded one.
public struct HostLoad: Sendable, Equatable {
    /// The one-minute load average, or `nil` when the kernel did not answer.
    public let oneMinute: Double?
    /// Processor cores the system has active.
    public let cores: Int

    public init(oneMinute: Double?, cores: Int) {
        self.oneMinute = oneMinute
        self.cores = cores
    }

    /// Quiet means the run queue was shorter than the cores that serve it, so nothing waited for a core.
    public var isQuiet: Bool { oneMinute.map { $0 < Double(cores) } ?? false }

    public static func current() -> HostLoad {
        var averages = [Double](repeating: 0, count: 3)
        let read = getloadavg(&averages, 3)
        return HostLoad(
            oneMinute: read > 0 ? averages[0] : nil,
            cores: ProcessInfo.processInfo.activeProcessorCount)
    }
}

/// One measured result in the format every row of `Docs/probe-log.md` takes.
public struct ProbeLogRow: Sendable, Equatable {
    /// The table header every probe-log table opens with, matching ``markdown(in:)`` column for column.
    public static let header = """
        | Issue | Date | Host class | Chip | Memory | OS | Build | Command | Result |
        |---|---|---|---|--:|---|---|---|---|
        """

    public let issue: Int?
    public let date: Date
    public let machine: MachineDescription
    public let load: HostLoad
    public let build: String
    public let command: String
    public let result: String

    public init(
        issue: Int?, date: Date, machine: MachineDescription, load: HostLoad, build: String,
        command: String, result: String
    ) {
        self.issue = issue
        self.date = date
        self.machine = machine
        self.load = load
        self.build = build
        self.command = command
        self.result = result
    }

    /// The command as typed, with the binary named rather than located, so rows from two checkouts compare.
    public static func command(from arguments: [String]) -> String {
        guard let binary = arguments.first else { return "" }
        let name = URL(fileURLWithPath: binary).lastPathComponent
        return ([name] + arguments.dropFirst()).joined(separator: " ")
    }

    public var hostClasses: [HostClass] { HostClass.classes(of: machine, load: load) }

    /// The row, ready to paste under ``header``.
    public func markdown(in timeZone: TimeZone = .current) -> String {
        let day = date.formatted(Date.ISO8601FormatStyle(timeZone: timeZone).year().month().day())
        let classes = hostClasses.map(\.rawValue).joined(separator: ", ")
        let measuredLoad =
            load.oneMinute.map { String(format: "load %.1f on %d cores", $0, load.cores) } ?? "load unread"
        let cells = [
            issue.map { "#\($0)" } ?? "—",
            day,
            (classes.isEmpty ? "" : classes + "; ") + measuredLoad,
            machine.chip,
            "\(machine.memoryBytes / 1_073_741_824) GB",
            machine.operatingSystem,
            build,
            "`\(command)`",
            result,
        ]
        return "| " + cells.map(Self.escape).joined(separator: " | ") + " |"
    }

    /// Keeps a cell containing a pipe or a line break from breaking the table.
    private static func escape(_ text: String) -> String {
        text.split(omittingEmptySubsequences: false, whereSeparator: \.isNewline)
            .joined(separator: " ")
            .replacingOccurrences(of: "|", with: "\\|")
    }
}

/// The build a probe ran from: its configuration and the commit of the checkout it ran in.
public enum BuildIdentity {
    /// The configuration this module was compiled in.
    public static var configuration: String {
        #if DEBUG
            return "debug"
        #else
            return "release"
        #endif
    }

    /// "release a1b2c3d", "debug a1b2c3d+dirty", or "debug, commit unknown" outside a checkout.
    public static func current(in directory: String = FileManager.default.currentDirectoryPath) -> String {
        guard let commit = git(["rev-parse", "--short", "HEAD"], in: directory), !commit.isEmpty else {
            return "\(configuration), commit unknown"
        }
        let dirty = git(["status", "--porcelain", "--untracked-files=no"], in: directory).map { !$0.isEmpty }
        return "\(configuration) \(commit)\(dirty == true ? "+dirty" : "")"
    }

    /// Runs one git command and returns its trimmed output, or `nil` when it fails.
    private static func git(_ arguments: [String], in directory: String) -> String? {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/git")
        process.arguments = ["-C", directory] + arguments
        let output = Pipe()
        process.standardOutput = output
        process.standardError = FileHandle.nullDevice
        do {
            try process.run()
        } catch {
            return nil
        }
        let data = output.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else { return nil }
        return String(decoding: data, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
