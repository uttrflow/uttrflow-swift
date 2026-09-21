import Foundation
import Testing

@testable import UttrflowPredict

/// A folder on the real disk that a test lays out and removes, so the gate is judged against paths that exist.
private final class Folder {
    let path: String

    init() throws {
        let url = FileManager.default.temporaryDirectory.appending(path: "terminal-gate-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        path = url.path(percentEncoded: false).replacing(/\/$/, with: "")
    }

    /// Makes a directory under the folder, parents included.
    func directory(_ name: String) throws {
        try FileManager.default.createDirectory(atPath: "\(path)/\(name)", withIntermediateDirectories: true)
    }

    /// Makes a file under the folder, parents included.
    func file(_ name: String, contents: String = "") throws {
        try directory((name as NSString).deletingLastPathComponent)
        try Data(contents.utf8).write(to: URL(filePath: "\(path)/\(name)"))
    }

    deinit {
        try? FileManager.default.removeItem(atPath: path)
    }
}

/// A terminal sitting in a directory, which is where the whole-line gate applies.
private func shell(in directory: String?) -> Surface {
    Surface(bundleIdentifier: "com.apple.Terminal", role: "AXTextArea", scope: directory)
}

/// The lines the verifier lets through from a remembered set, on a machine index that has not answered.
private func kept(
    _ lines: [String], in surface: Surface, reader: StubEnvironment = StubEnvironment([:])
) async
    -> [String]
{
    let verifier = Verifier(index: EnvironmentIndex(reader: reader), budgetInMilliseconds: 200)
    let candidates = lines.map {
        Candidate(text: $0, source: .personal, isIrreversible: DestructiveCommand.matches($0))
    }
    return await verifier.verified(candidates, in: surface, typed: "", now: moment).map(\.text)
}

@Suite("A terminal line is shown only when what it names exists from here")
struct TerminalPathGateTests {
    @Test("A cd to a directory that was deleted is not suggested.")
    func deletedDirectory() async throws {
        let folder = try Folder()
        try folder.directory("build")
        try folder.directory("gone")
        try FileManager.default.removeItem(atPath: "\(folder.path)/gone")
        #expect(await kept(["cd gone", "cd build"], in: shell(in: folder.path)) == ["cd build"])
    }

    @Test("A relative path typed in another directory is not suggested here.")
    func relativeFromElsewhere() async throws {
        let folder = try Folder()
        try folder.directory("api/Sources/Login")
        try folder.directory("web/src")
        let here = shell(in: "\(folder.path)/web")
        #expect(await kept(["cd Sources/Login", "cd src"], in: here) == ["cd src"])
    }

    @Test("A file where a directory is needed, and a directory where a file is, are not suggested.")
    func kindMismatch() async throws {
        let folder = try Folder()
        try folder.file("notes.txt")
        try folder.directory("docs")
        let lines = ["cd notes.txt", "cat docs", "cd docs", "cat notes.txt"]
        #expect(await kept(lines, in: shell(in: folder.path)) == ["cd docs", "cat notes.txt"])
    }

    @Test("A path from home is resolved from home, and one that is not there is refused.")
    func homeExpansion() async throws {
        let missing = "~/.uttrflow-gate-\(UUID().uuidString)"
        let lines = ["cd \(missing)", "cat $HOME/\(missing.dropFirst(2))", "cd ~", "cd $HOME"]
        #expect(await kept(lines, in: shell(in: nil)) == ["cd ~", "cd $HOME"])
    }

    @Test("Quotes and escaped spaces name one path, checked whole.")
    func quotedPaths() async throws {
        let folder = try Folder()
        try folder.directory("My Folder")
        let lines = [
            #"cd "My Folder""#, #"cd My\ Folder"#, "cd 'My Folder'", #"cd "My Files""#, #"cd My\ Files"#,
        ]
        let expected = [#"cd "My Folder""#, #"cd My\ Folder"#, "cd 'My Folder'"]
        #expect(await kept(lines, in: shell(in: folder.path)) == expected)
    }

    @Test("Without a directory that exists, a relative path is not suggested and an absolute one still is.")
    func unknownDirectory() async throws {
        let folder = try Folder()
        try folder.file("README.md")
        let lines = ["cat README.md", "cat \(folder.path)/README.md"]
        #expect(await kept(lines, in: shell(in: nil)) == ["cat \(folder.path)/README.md"])
        #expect(await kept(lines, in: shell(in: "~/api (-zsh)")) == ["cat \(folder.path)/README.md"])
    }

    @Test("A cd earlier in the line moves where the later paths are read from.")
    func cdMovesTheLine() async throws {
        let folder = try Folder()
        try folder.file("build/out.log")
        let lines = ["cd build && cat out.log", "cat out.log", "cd build || cat out.log"]
        #expect(await kept(lines, in: shell(in: folder.path)) == ["cd build && cat out.log"])
    }

    @Test("A checkout names a branch the repository's refs hold.")
    func branches() async throws {
        let folder = try Folder()
        try folder.file(".git/refs/heads/main", contents: "0123456789abcdef0123456789abcdef01234567\n")
        try folder.file(
            ".git/refs/remotes/origin/release", contents: "0123456789abcdef0123456789abcdef01234567\n")
        let lines = [
            "git checkout main", "git checkout gone", "git switch release", "git switch fix/nowhere",
        ]
        #expect(await kept(lines, in: shell(in: folder.path)) == ["git checkout main", "git switch release"])
    }

    @Test("A destructive line is never offered, however it is written.")
    func destructive() async throws {
        let folder = try Folder()
        try folder.directory("build")
        let lines = ["rm -rf build", "/bin/rm -rf build", "git push --force-with-lease", "ls build"]
        #expect(await kept(lines, in: shell(in: folder.path)) == ["ls build"])
        let verifier = Verifier(index: EnvironmentIndex(reader: StubEnvironment([:])))
        let prose = Surface(bundleIdentifier: "com.example.notes", role: "AXTextArea")
        let standing = await verifier.standing(
            ["git push --force origin main", "git push origin main"], after: "git p", in: prose, now: moment)
        #expect(standing == ["git push origin main"])
    }

    @Test("A model's line with a path that is not here is dropped before the machine has answered.")
    func generatedLinesAreChecked() async throws {
        let folder = try Folder()
        try folder.file(".env")
        let verifier = Verifier(index: EnvironmentIndex(reader: StubEnvironment([:])))
        let standing = await verifier.standing(
            ["vim .env.vim", "vim .env"], after: "vim .e", in: shell(in: folder.path), now: moment)
        #expect(standing == ["vim .env"])
    }
}
