import Testing

@testable import UttrflowPredict

/// The shape of the word a line ends on.
private func shape(_ line: String) -> LineShape? { CompletionToken(line).map(LineShape.of) }

@Suite("Reading a command line as its shell does")
struct LineShapeTests {
    @Test("The first word is the program, however the line is indented or wrapped.")
    func firstWordIsTheProgram() {
        #expect(shape("gi") == LineShape(command: nil, kind: .program))
        #expect(shape("sudo gi") == LineShape(command: nil, kind: .program))
        #expect(shape("sudo -E gi") == LineShape(command: nil, kind: .program))
        #expect(shape("ls && gi") == LineShape(command: nil, kind: .program))
        #expect(shape("cat x | gr") == LineShape(command: nil, kind: .program))
    }

    @Test("A command's arguments are what the command takes, flags left out of the count.")
    func argumentsFollowTheCommand() {
        #expect(shape("cd pro") == LineShape(command: "cd", kind: .directory))
        #expect(shape("ls -la Sour") == LineShape(command: "ls", kind: .file))
        #expect(shape("git chec") == LineShape(command: "git", kind: .subcommand(of: "git")))
        #expect(shape("git checkout -b fe") == LineShape(command: "git", kind: .branch))
        #expect(shape("git add Sour") == LineShape(command: "git", kind: .file))
        #expect(shape("git commit -m fix") == LineShape(command: "git", kind: .free))
        #expect(shape("make ver") == LineShape(command: "make", kind: .subcommand(of: "make")))
        #expect(shape("make verify ins") == LineShape(command: "make", kind: .subcommand(of: "make")))
        #expect(shape("npm ru") == LineShape(command: "npm", kind: .subcommand(of: "npm")))
        #expect(shape("npm run de") == LineShape(command: "npm", kind: .subcommand(of: "npm run")))
        #expect(shape("npm run dev --") == LineShape(command: "npm", kind: .free))
        #expect(shape("docker compose u") == LineShape(command: "docker", kind: .free))
        #expect(shape("grep -r TODO Sour") == LineShape(command: "grep", kind: .file))
        #expect(shape("grep -r TO") == LineShape(command: "grep", kind: .free))
        #expect(shape("find . -na") == LineShape(command: "find", kind: .free))
        #expect(shape("find Sour") == LineShape(command: "find", kind: .directory))
        #expect(shape("myapp ser") == LineShape(command: "myapp", kind: .free))
    }

    @Test("A new simple command begins after an operator, and a wrapper hands its arguments on.")
    func operatorsAndWrappers() {
        #expect(shape("make verify && cd pro") == LineShape(command: "cd", kind: .directory))
        #expect(shape("cd x; git chec") == LineShape(command: "git", kind: .subcommand(of: "git")))
        #expect(shape("time make ver") == LineShape(command: "make", kind: .subcommand(of: "make")))
    }
}
