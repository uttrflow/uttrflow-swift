import Foundation

/// Runs a real formatter, if one is installed.
///
/// Excluded from the coverage gate: it spawns another program and pipes bytes through it,
/// and there is nothing to assert about those lines that is not simply "the operating
/// system did what we asked". Everything that decides *whether* to run one, and whether to
/// believe what comes back, is decided in ``CodeFormatting`` and ``FormatterGuard`` and
/// tested there.
///
/// Four rules, and each is load-bearing rather than tidiness:
///
/// - Only a ``KnownFormatter`` is ever executed, by name, from a fixed list of directories.
///   Never a search of `PATH`, because `PATH` is whatever the user's shell has picked up
///   and this feature hands it everything they are about to paste.
/// - The code goes in on standard input, never as an argument. It is the user's text and
///   may contain anything; on a command line that becomes a command.
/// - No shell. `Process` with an explicit executable, so nothing is expanded, globbed or
///   split on the way.
/// - A timeout, because this runs while somebody is waiting on a paste and a program that
///   has hung must not take the panel with it.
public struct SystemCodeFormatter: CodeFormatting {
    /// Where a formatter is looked for.
    ///
    /// The usual places a developer's tools land, in order. Not `PATH`: an entry prepended
    /// to it — by a project's `.envrc`, by a shell plugin, by anything — would be searched
    /// first and executed on the user's clipboard.
    static let directories = [
        "/opt/homebrew/bin", "/usr/local/bin", "/usr/bin", "/opt/homebrew/opt/go/libexec/bin",
    ]

    public init() {}

    public func isAvailable(for language: CodeLanguage) async -> Bool {
        KnownFormatter.forLanguage(language).flatMap { executable(for: $0) } != nil
    }

    public func format(_ text: String, as language: CodeLanguage) async -> String? {
        guard let formatter = KnownFormatter.forLanguage(language),
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

    /// One run, bounded, with the code on standard input.
    ///
    /// Answers `nil` on any refusal at all — a non-zero exit, a timeout, output that is not
    /// text. D7 says a failed format is quiet and the original is pasted untouched, so
    /// there is nothing here to distinguish between the ways it can fail.
    private func run(_ tool: URL, arguments: [String], input: String) async -> String? {
        let process = Process()
        process.executableURL = tool
        process.arguments = arguments
        // A bare environment. Formatters read configuration from their surroundings, and
        // the surroundings of a clipboard panel are not a project the user chose.
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

        // Read before waiting: a formatter whose output fills the pipe buffer blocks
        // writing it, and waiting first would deadlock against exactly that.
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
