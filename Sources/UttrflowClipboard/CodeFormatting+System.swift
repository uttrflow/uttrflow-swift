// Runs an installed formatter over a clip.

import Foundation

/// Runs a real formatter from a fixed list of directories, on stdin, with no shell and a timeout.
public struct SystemCodeFormatter: CodeFormatting {
    /// Where a formatter is looked for; never `PATH`, which anything can prepend to.
    static let directories = [
        "/opt/homebrew/bin", "/usr/local/bin", "/usr/bin", "/opt/homebrew/opt/go/libexec/bin",
    ]

    public init() {}

    public func isAvailable(for language: CodeLanguage) async -> Bool {
        KnownFormatter(for: language).flatMap { executable(for: $0) } != nil
    }

    public func format(_ text: String, as language: CodeLanguage) async -> String? {
        guard let formatter = KnownFormatter(for: language),
            let tool = executable(for: formatter)
        else { return nil }

        return await run(tool, arguments: formatter.arguments(for: language), input: text)
    }

    /// The formatter's own file, or `nil` when it is not installed.
    private func executable(for formatter: KnownFormatter) -> URL? {
        for directory in Self.directories {
            let candidate = URL(filePath: directory).appending(path: formatter.rawValue)
            if FileManager.default.isExecutableFile(atPath: candidate.path) { return candidate }
        }
        return nil
    }

    /// One bounded run with the code on standard input; `nil` on any refusal at all.
    private func run(_ tool: URL, arguments: [String], input: String) async -> String? {
        await Self.run(
            tool, arguments: arguments, input: input,
            environment: ["PATH": Self.directories.joined(separator: ":")], timeout: KnownFormatter.timeout)
    }

    /// Runs `tool` over `input`, feeding and draining its pipes at once, and gives up `timeout` after it starts.
    static func run(
        _ tool: URL, arguments: [String], input: String, environment: [String: String],
        timeout: TimeInterval
    ) async -> String? {
        let process = Process()
        process.executableURL = tool
        process.arguments = arguments
        // A bare environment: a clipboard panel's surroundings are not a project the user chose.
        process.environment = environment

        let stdin = Pipe()
        let stdout = Pipe()
        let stderr = Pipe()
        process.standardInput = stdin
        process.standardOutput = stdout
        process.standardError = stderr
        // A tool that stops reading makes the write fail rather than raise SIGPIPE in this process.
        _ = fcntl(stdin.fileHandleForWriting.fileDescriptor, F_SETNOSIGPIPE, 1)

        let finished = DispatchGroup()
        finished.enter()
        process.terminationHandler = { _ in finished.leave() }
        do {
            try process.run()
        } catch {
            return nil
        }

        return await withCheckedContinuation { continuation in
            let answer = FirstAnswer(continuation)
            let produced = ProducedOutput()
            let queue = DispatchQueue.global(qos: .userInitiated)
            queue.async(group: finished) {
                try? stdin.fileHandleForWriting.write(contentsOf: Data(input.utf8))
                try? stdin.fileHandleForWriting.close()
            }
            queue.async(group: finished) { produced.data = try? stdout.fileHandleForReading.readToEnd() }
            queue.async(group: finished) { _ = try? stderr.fileHandleForReading.readToEnd() }
            finished.notify(queue: queue) {
                guard process.terminationStatus == 0, let data = produced.data, !data.isEmpty else {
                    answer.give(nil)
                    return
                }
                answer.give(String(data: data, encoding: .utf8))
            }
            queue.asyncAfter(deadline: .now() + timeout) {
                // A hung program must not take the panel, whatever its pipes are doing.
                if answer.give(nil) { process.terminate() }
            }
        }
    }
}

/// Resumes a run's continuation once, with whichever of the finished run and the deadline answers first.
private final class FirstAnswer: @unchecked Sendable {
    private let lock = NSLock()
    private var continuation: CheckedContinuation<String?, Never>?

    init(_ continuation: CheckedContinuation<String?, Never>) { self.continuation = continuation }

    /// Answers the run, returning whether this was the first answer.
    @discardableResult
    func give(_ value: String?) -> Bool {
        lock.lock()
        let waiting = continuation
        continuation = nil
        lock.unlock()
        waiting?.resume(returning: value)
        return waiting != nil
    }
}

/// The tool's standard output, written by its reader before the run's group is notified.
private final class ProducedOutput: @unchecked Sendable {
    var data: Data?
}
