import Foundation

/// Reads a shell's history file, so a terminal is useful on the first day rather than the third week.
public enum ShellHistory {
    /// How many commands an import takes, counted from the most recent backwards.
    public static let limit = 5_000

    /// The zsh extended-history prefix, which is a timestamp and an elapsed time before the command.
    nonisolated(unsafe) private static let extendedPrefix = #/^:\s*\d+:\d+;/#

    /// Where the two shells keep their history, in the order they are looked for.
    public static func paths(inHomeDirectory home: String) -> [String] {
        [".zsh_history", ".bash_history"].map { home.hasSuffix("/") ? home + $0 : home + "/" + $0 }
    }

    /// The commands in a history file, oldest last kept, with timestamps stripped and secrets dropped.
    public static func commands(in contents: String) -> [String] {
        var commands: [String] = []
        var continued = ""
        for line in contents.split(separator: "\n", omittingEmptySubsequences: false) {
            let joined = continued + stripped(String(line), isContinuation: !continued.isEmpty)
            guard !joined.hasSuffix("\\") else {
                continued = String(joined.dropLast()) + "\n"
                continue
            }
            continued = ""
            if let command = command(in: joined) { commands.append(command) }
        }
        if let command = command(in: continued) { commands.append(command) }
        return Array(commands.suffix(limit))
    }

    /// Reads a history file off the disk, tolerating bytes that are not text rather than refusing.
    public static func read(atPath path: String) -> [String] {
        guard let data = FileManager.default.contents(atPath: path) else { return [] }
        return commands(in: String(decoding: data, as: UTF8.self))
    }

    /// Removes the timestamp zsh writes before a command, which only ever opens a first line.
    private static func stripped(_ line: String, isContinuation: Bool) -> String {
        guard !isContinuation, let match = line.firstMatch(of: extendedPrefix) else { return line }
        return String(line[match.range.upperBound...])
    }

    /// Whether a line is a command worth keeping, once it has been trimmed.
    private static func command(in line: String) -> String? {
        let command = line.trimmingCharacters(in: .whitespacesAndNewlines)
        guard command.count >= CaptureGate.minimumLength, !CaptureGate.looksLikeSecret(command)
        else { return nil }
        return command
    }
}
