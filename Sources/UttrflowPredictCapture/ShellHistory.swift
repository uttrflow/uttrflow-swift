import Foundation

/// Reads a shell's history file, so a terminal is useful on the first day rather than the third week.
public enum ShellHistory {
    /// How many commands an import takes, counted from the most recent backwards.
    public static let limit = 5_000

    /// How many bytes a reverse read takes from the history file at once.
    private static let readChunkSize = 64 * 1024

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
        return mostRecentUnique(commands)
    }

    /// Reads the newest distinct commands in bounded chunks, tolerating bytes that are not text.
    public static func read(atPath path: String) -> [String] {
        guard let handle = FileHandle(forReadingAtPath: path) else { return [] }
        defer { try? handle.close() }
        do {
            let isZsh = URL(fileURLWithPath: path).lastPathComponent == ".zsh_history"
            var offset = try handle.seekToEnd()
            var carry: [UInt8] = []
            var pending: [[UInt8]] = []
            var newestFirst: [String] = []
            var seen: Set<String> = []

            while offset > 0, newestFirst.count < limit {
                let count = Int(min(UInt64(readChunkSize), offset))
                offset -= UInt64(count)
                try handle.seek(toOffset: offset)
                guard let data = try handle.read(upToCount: count), !data.isEmpty else { break }
                let bytes = Array(data) + carry
                var lineEnd = bytes.count
                for index in bytes.indices.reversed() where bytes[index] == 0x0A {
                    accept(
                        Array(bytes[(index + 1)..<lineEnd]), isZsh: isZsh,
                        pending: &pending, newestFirst: &newestFirst, seen: &seen)
                    lineEnd = index
                    if newestFirst.count == limit { break }
                }
                carry = Array(bytes[..<lineEnd])
            }

            if newestFirst.count < limit {
                accept(
                    carry, isZsh: isZsh, pending: &pending,
                    newestFirst: &newestFirst, seen: &seen)
            }
            if newestFirst.count < limit {
                finish(pending, isZsh: isZsh, newestFirst: &newestFirst, seen: &seen)
            }
            return Array(newestFirst.reversed())
        } catch {
            return []
        }
    }

    /// Removes the timestamp zsh writes before a command, which only ever opens a first line.
    private static func stripped(_ line: String, isContinuation: Bool) -> String {
        guard !isContinuation, let match = line.firstMatch(of: extendedPrefix) else { return line }
        return String(line[match.range.upperBound...])
    }

    /// Restores bytes escaped with zsh's Meta prefix before UTF-8 decoding.
    private static func unmetafied(_ data: Data) -> Data {
        var iterator = data.makeIterator()
        var decoded: [UInt8] = []
        decoded.reserveCapacity(data.count)
        while let byte = iterator.next() {
            guard byte == 0x83 else {
                decoded.append(byte)
                continue
            }
            guard let escapedByte = iterator.next() else {
                decoded.append(byte)
                break
            }
            decoded.append(escapedByte ^ 0x20)
        }
        return Data(decoded)
    }

    /// Whether a line is a command worth keeping, once it has been trimmed.
    private static func command(in line: String) -> String? {
        let command = line.trimmingCharacters(in: .whitespacesAndNewlines)
        guard command.count >= CaptureGate.minimumLength,
            !command.contains("\u{FFFD}"), !isBashTimestamp(command),
            !CaptureGate.looksLikeSecret(command)
        else { return nil }
        return command
    }

    /// Keeps the last occurrence of each command in its original chronological order.
    private static func mostRecentUnique(_ commands: [String]) -> [String] {
        var seen: Set<String> = []
        let newestFirst = commands.reversed().filter { seen.insert($0).inserted }
        return Array(newestFirst.prefix(limit).reversed())
    }

    /// Adds a physical line to the pending command, or completes the newer command first.
    private static func accept(
        _ line: [UInt8], isZsh: Bool, pending: inout [[UInt8]],
        newestFirst: inout [String], seen: inout Set<String>
    ) {
        guard !pending.isEmpty else {
            pending = [line]
            return
        }
        if line.last == 0x5C {
            pending.append(line)
        } else {
            finish(pending, isZsh: isZsh, newestFirst: &newestFirst, seen: &seen)
            pending = [line]
        }
    }

    /// Parses a completed logical command and records it once, newest first.
    private static func finish(
        _ linesNewestFirst: [[UInt8]], isZsh: Bool,
        newestFirst: inout [String], seen: inout Set<String>
    ) {
        let lines = linesNewestFirst.reversed().enumerated().map { index, bytes -> String in
            var line = String(decoding: isZsh ? unmetafied(Data(bytes)) : Data(bytes), as: UTF8.self)
            line = stripped(line, isContinuation: index > 0)
            if line.hasSuffix("\\") { line.removeLast() }
            return line
        }
        if let command = command(in: lines.joined(separator: "\n")), seen.insert(command).inserted {
            newestFirst.append(command)
        }
    }

    /// Bash writes epoch timestamps as standalone comment lines when history timestamps are on.
    private static func isBashTimestamp(_ command: String) -> Bool {
        guard command.first == "#", command.count > 1 else { return false }
        return command.dropFirst().unicodeScalars.allSatisfy { (48...57).contains($0.value) }
    }
}
