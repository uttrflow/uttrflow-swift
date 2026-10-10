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

    @Test("Repeated commands keep only their newest occurrence.")
    func repeatedCommandsAreDeduplicated() {
        #expect(ShellHistory.commands(in: "git status\nls\ngit status\nls\n") == ["git status", "ls"])
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

    @Test("Metafied UTF-8 bytes in zsh history are restored before decoding.")
    func zshMetafiedTextIsDecoded() throws {
        let scratch = Scratch()
        try FileManager.default.createDirectory(
            atPath: scratch.directory, withIntermediateDirectories: true)
        var data = Data(": 1:0;echo caf".utf8)
        data.append(contentsOf: [0x83, 0xE3, 0x83, 0x89, 0x0A])
        FileManager.default.createFile(atPath: scratch.path(".zsh_history"), contents: data)
        #expect(ShellHistory.read(atPath: scratch.path(".zsh_history")) == ["echo café"])
    }

    @Test("Bash history keeps its plain UTF-8 encoding.")
    func bashTextIsNotUnmetafied() throws {
        let scratch = Scratch()
        try FileManager.default.createDirectory(
            atPath: scratch.directory, withIntermediateDirectories: true)
        FileManager.default.createFile(
            atPath: scratch.path(".bash_history"), contents: Data("echo café\n".utf8))
        #expect(ShellHistory.read(atPath: scratch.path(".bash_history")) == ["echo café"])
    }

    @Test("A large history reads its newest distinct commands across bounded chunks.")
    func largeHistoryReadsNewestCommands() throws {
        let scratch = Scratch()
        try FileManager.default.createDirectory(
            atPath: scratch.directory, withIntermediateDirectories: true)
        let firstKept = 1_000
        let contents = (0..<(ShellHistory.limit + firstKept))
            .map { "command-number-\($0)-with-padding" }
            .joined(separator: "\n")
        FileManager.default.createFile(
            atPath: scratch.path(".bash_history"), contents: Data(contents.utf8))

        let commands = ShellHistory.read(atPath: scratch.path(".bash_history"))
        #expect(commands.count == ShellHistory.limit)
        #expect(commands.first == "command-number-\(firstKept)-with-padding")
        #expect(commands.last == "command-number-\(ShellHistory.limit + firstKept - 1)-with-padding")
    }

    @Test("Bash epoch timestamp lines are not imported as commands.")
    func bashTimestampsAreSkipped() throws {
        let scratch = Scratch()
        try FileManager.default.createDirectory(
            atPath: scratch.directory, withIntermediateDirectories: true)
        let contents = "#1699999999\ngit status\n#1700000000\ngit status\n#1700000001\nmake verify\n"
        FileManager.default.createFile(
            atPath: scratch.path(".bash_history"), contents: Data(contents.utf8))

        #expect(ShellHistory.read(atPath: scratch.path(".bash_history")) == ["git status", "make verify"])
    }

    @Test("An unterminated continuation drops its trailing backslash at EOF.")
    func readDropsTrailingBackslashAtEOF() throws {
        let scratch = Scratch()
        try FileManager.default.createDirectory(
            atPath: scratch.directory, withIntermediateDirectories: true)
        FileManager.default.createFile(
            atPath: scratch.path(".bash_history"), contents: Data("echo one\\\necho two\\".utf8))

        #expect(ShellHistory.read(atPath: scratch.path(".bash_history")) == ["echo one\necho two"])
    }

    @Test("A command with a remaining replacement character is dropped.")
    func undecodableCommandIsDropped() throws {
        let scratch = Scratch()
        try FileManager.default.createDirectory(
            atPath: scratch.directory, withIntermediateDirectories: true)
        var data = Data("echo ".utf8)
        data.append(0xFF)
        data.append(contentsOf: Array("\nmake verify\n".utf8))
        FileManager.default.createFile(atPath: scratch.path(".bash_history"), contents: data)
        #expect(ShellHistory.read(atPath: scratch.path(".bash_history")) == ["make verify"])
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
