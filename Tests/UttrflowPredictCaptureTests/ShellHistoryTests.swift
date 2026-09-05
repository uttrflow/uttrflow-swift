import Foundation
import Testing

@testable import UttrflowPredictCapture

@Suite("Reading a shell's history")
struct ShellHistoryTests {
    @Test("Both shells are looked for, zsh first, whether or not the home directory ends in a slash.")
    func pathsAreBothShells() {
        #expect(
            ShellHistory.paths(inHomeDirectory: "/Users/someone")
                == ["/Users/someone/.zsh_history", "/Users/someone/.bash_history"])
        #expect(
            ShellHistory.paths(inHomeDirectory: "/Users/someone/")
                == ["/Users/someone/.zsh_history", "/Users/someone/.bash_history"])
    }

    @Test("Plain bash history is one command per line.")
    func plainHistory() {
        #expect(ShellHistory.commands(in: "git status\nmake verify\n") == ["git status", "make verify"])
    }

    @Test("The timestamp zsh writes before a command is not part of the command.")
    func extendedHistoryIsStripped() {
        let contents = ": 1699999999:0;git status\n: 1700000000:12;make verify\n"
        #expect(ShellHistory.commands(in: contents) == ["git status", "make verify"])
    }

    @Test("A command written across several lines comes back as one command.")
    func continuationsAreJoined() {
        let contents = ": 1699999999:0;for file in *; do\\\necho $file\\\ndone\n: 1700000000:0;ls\n"
        #expect(ShellHistory.commands(in: contents) == ["for file in *; do\necho $file\ndone", "ls"])
    }

    @Test("A file whose last command is left hanging still yields it.")
    func unterminatedContinuationIsKept() {
        #expect(ShellHistory.commands(in: "echo one\\\necho two") == ["echo one\necho two"])
    }

    @Test("Blank lines and one-character commands are dropped.")
    func noiseIsDropped() {
        #expect(ShellHistory.commands(in: "\n  \nls\ny\n") == ["ls"])
    }

    @Test("A command carrying a credential is never imported.")
    func secretsAreRefused() {
        let contents = ": 1:0;export API_KEY=sk-ant-abcdefghijklmnop0123\n: 2:0;git status\n"
        #expect(ShellHistory.commands(in: contents) == ["git status"])
    }

    @Test("Repeats are kept, because how often a command is run is what ranks it.")
    func repeatsAreKept() {
        #expect(ShellHistory.commands(in: "ls\nls\nls\n").count == 3)
    }

    @Test("Only the most recent commands are taken, however long the file is.")
    func theFileIsCapped() {
        let contents = (0..<(ShellHistory.limit + 10)).map { "echo \($0)" }.joined(separator: "\n")
        let commands = ShellHistory.commands(in: contents)
        #expect(commands.count == ShellHistory.limit)
        #expect(commands.last == "echo \(ShellHistory.limit + 9)")
    }

    @Test("A file that is not there reads as no commands at all.")
    func missingFileIsEmpty() {
        #expect(ShellHistory.read(atPath: NSTemporaryDirectory() + "uttrflow-absent-history").isEmpty)
    }

    @Test("Bytes that are not text are replaced rather than refusing the whole file.")
    func invalidBytesAreTolerated() throws {
        let scratch = Scratch()
        try FileManager.default.createDirectory(
            atPath: scratch.directory, withIntermediateDirectories: true)
        var data = Data("git status\n".utf8)
        data.append(contentsOf: [0xFF, 0xFE])
        data.append(contentsOf: Array("\nmake verify\n".utf8))
        FileManager.default.createFile(atPath: scratch.path("history"), contents: data)
        let commands = ShellHistory.read(atPath: scratch.path("history"))
        #expect(commands.first == "git status")
        #expect(commands.last == "make verify")
    }
}
