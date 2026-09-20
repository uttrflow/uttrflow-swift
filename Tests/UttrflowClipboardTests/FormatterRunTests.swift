// Tests that a formatter run is bounded by its deadline and cannot deadlock on its pipes.
import Foundation
import Testing

@testable import UttrflowClipboard

/// Drives the formatter's run against stand-in scripts, since the real formatters may not be installed.
@Suite("A formatter run is bounded and never deadlocks", .timeLimit(.minutes(2)))
struct FormatterRunTests {
    /// A stand-in tool: this shell script, written executable into its own temporary folder.
    private static func tool(_ script: String) throws -> URL {
        let folder = FileManager.default.temporaryDirectory.appending(path: "formatter-run-\(UUID())")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let file = folder.appending(path: "tool")
        try Data(("#!/bin/sh\n" + script + "\n").utf8).write(to: file)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: file.path)
        return file
    }

    private static func run(_ tool: URL, _ input: String, timeout: TimeInterval = 60) async -> String? {
        await SystemCodeFormatter.run(
            tool, arguments: [], input: input, environment: ["PATH": "/usr/bin:/bin"], timeout: timeout)
    }

    @Test("a tool that is still running at the deadline is given up on, even if it would answer later")
    func deadlineCoversTheWholeRun() async throws {
        let slow = try Self.tool("cat >/dev/null\nsleep 30\necho formatted")
        #expect(await Self.run(slow, "let x = 1", timeout: 0.2) == nil)
    }

    @Test("a megabyte round-trips through a tool that writes as it reads")
    func streamingToolDoesNotDeadlock() async throws {
        let echo = try Self.tool("exec /bin/cat")
        let input = String(repeating: "let value = 42\n", count: 70_000)
        #expect(await Self.run(echo, input) == input)
    }

    @Test("a tool that writes more warnings than a pipe holds still answers")
    func chattyToolDoesNotDeadlock() async throws {
        let chatty = try Self.tool("head -c 300000 /dev/zero >&2\nexec /bin/cat")
        #expect(await Self.run(chatty, "let x = 1\n") == "let x = 1\n")
    }

    @Test("a tool that fails, or answers with nothing, is refused")
    func refusals() async throws {
        #expect(await Self.run(try Self.tool("cat\nexit 1"), "let x = 1\n") == nil)
        #expect(await Self.run(try Self.tool("cat >/dev/null"), "let x = 1\n") == nil)
    }

    @Test("a tool that cannot be started is refused")
    func missingTool() async {
        let nowhere = URL(filePath: "/nonexistent/formatter-\(UUID())")
        #expect(await Self.run(nowhere, "let x = 1\n") == nil)
    }

    @Test("a tool that never reads its input does not stop the run")
    func toolThatIgnoresInput() async throws {
        let deaf = try Self.tool("echo formatted")
        let input = String(repeating: "x", count: 1_000_000)
        #expect(await Self.run(deaf, input) == "formatted\n")
    }
}
