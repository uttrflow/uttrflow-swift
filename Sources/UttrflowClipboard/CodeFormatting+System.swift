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

        return await run(tool, arguments: formatter.arguments, input: text)
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
        let process = Process()
        process.executableURL = tool
        process.arguments = arguments
        // A bare environment: a clipboard panel's surroundings are not a project the user chose.
        process.environment = ["PATH": Self.directories.joined(separator: ":")]

        let stdin = Pipe()
        let stdout = Pipe()
        let stderr = Pipe()
        process.standardInput = stdin
        process.standardOutput = stdout
        process.standardError = stderr

        do {
            try process.run()
        } catch {
            return nil
        }

        stdin.fileHandleForWriting.write(Data(input.utf8))
        try? stdin.fileHandleForWriting.close()

        // Read before waiting, or a formatter that fills the pipe buffer deadlocks.
        let produced = try? stdout.fileHandleForReading.readToEnd()
        _ = try? stderr.fileHandleForReading.readToEnd()

        let deadline = Date().addingTimeInterval(KnownFormatter.timeout)
        while process.isRunning && Date() < deadline {
            try? await Task.sleep(for: .milliseconds(20))
        }
        guard !process.isRunning else {
            process.terminate()
            return nil
        }
        guard process.terminationStatus == 0, let produced, !produced.isEmpty else { return nil }
        return String(data: produced, encoding: .utf8)
    }
}
