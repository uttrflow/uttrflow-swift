import Testing

@testable import UttrflowPredict

/// The shape of the word a line ends on.
private func shape(_ line: String) -> LineShape? { CompletionToken(line).map(LineShape.of) }
private func shape(afterSpace leading: String) -> LineShape {
    LineShape.of(CompletionToken(leading: leading, token: ""))
}

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
        #expect(shape("git checkout -b fe") == LineShape(command: "git", kind: .free))
        #expect(shape("git log READ") == LineShape(command: "git", kind: .branchOrFile))
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

    @Test("After a bare `--` git takes only paths, whatever the verb before it takes.")
    func gitAfterTheEndOfOptionsTakesPaths() {
        for line in [
            "git checkout -- m", "git checkout main -- Sour", "git switch -- m", "git merge -- m",
            "git log -- S", "git log --oneline -- Sour", "git diff HEAD -- READ",
        ] {
            #expect(shape(line) == LineShape(command: "git", kind: .file), "\(line)")
        }
        for leading in ["git checkout -- ", "git log -- "] {
            let token = CompletionToken(leading: leading, token: "")
            #expect(LineShape.of(token) == LineShape(command: "git", kind: .file), "\(leading)")
        }
        #expect(shape("git checkout m") == LineShape(command: "git", kind: .branch))
        #expect(shape("git log --oneline m") == LineShape(command: "git", kind: .branchOrFile))
        #expect(shape("rm -- -f") == LineShape(command: "rm", kind: .file))
    }

    @Test("A branch a git verb creates is a new name, never an existing branch; where it starts from is one.")
    func gitNewBranchNamesAreFree() {
        for line in [
            "git checkout -b feat", "git checkout -B feat", "git checkout --orphan feat",
            "git switch -c feat",
            "git switch -C feat", "git switch --create feat", "git worktree add -b feat", "git branch feat",
            "git branch -m old feat", "git branch --list fe",
        ] {
            #expect(shape(line) == LineShape(command: "git", kind: .free), "\(line)")
        }
        for line in [
            "git checkout feat", "git checkout -b new ma", "git switch -c new ma", "git switch ma",
            "git branch -d feat", "git branch -D feat", "git branch --delete feat", "git branch -m feat",
            "git branch new ma", "git branch --contains ma", "git branch -u orig",
        ] {
            #expect(shape(line) == LineShape(command: "git", kind: .branch), "\(line)")
        }
    }

    @Test("A new simple command begins after an operator, and a wrapper hands its arguments on.")
    func operatorsAndWrappers() {
        #expect(shape("make verify && cd pro") == LineShape(command: "cd", kind: .directory))
        #expect(shape("cd x; git chec") == LineShape(command: "git", kind: .subcommand(of: "git")))
        #expect(shape("time make ver") == LineShape(command: "make", kind: .subcommand(of: "make")))
    }

    @Test("Wrapper options consume their values before the wrapped command is read.")
    func wrapperOptionsConsumeValues() {
        for line in [
            "sudo -u deploy git chec", "sudo -g operators make ver", "doas -u deploy git chec",
            "env -u PATH git chec", "env -C /tmp git chec", "nice -n 10 make ver", "sudo -E git chec",
            "sudo -u deploy env -u PATH git chec",
        ] {
            let expectedCommand = line.contains("make") ? "make" : "git"
            let expectedKind: ArgumentKind =
                expectedCommand == "make" ? .subcommand(of: "make") : .subcommand(of: "git")
            #expect(shape(line) == LineShape(command: expectedCommand, kind: expectedKind), "\(line)")
        }
        #expect(shape(afterSpace: "sudo -u deploy git checkout ") == LineShape(command: "git", kind: .branch))
        #expect(
            shape(afterSpace: "nice -n 10 make ") == LineShape(command: "make", kind: .subcommand(of: "make"))
        )
        #expect(shape(afterSpace: "env FOO=1 cd ") == LineShape(command: "cd", kind: .directory))
    }

    @Test("An operator run into the word before it still starts a new command.")
    func operatorsAdjacentToThePriorWord() {
        #expect(shape("git status&& gi") == LineShape(command: nil, kind: .program))
        #expect(shape("git status|| gi") == LineShape(command: nil, kind: .program))
        #expect(shape("cat file| gr") == LineShape(command: nil, kind: .program))
        #expect(shape("make build; gi") == LineShape(command: nil, kind: .program))
    }

    @Test("A quoted or escaped operator character stays part of the word, so it never ends a command.")
    func quotedAndEscapedOperatorsDoNotSplit() {
        #expect(shape("echo \"a && b\" nex") == LineShape(command: "echo", kind: .free))
        #expect(shape("git commit -m foo\\; gi") == LineShape(command: "git", kind: .free))
    }
}

@Suite("Reading a command line through the user's aliases")
struct LineShapeAliasTests {
    private let aliases: [String: [String]] = [
        "g": ["git"], "gco": ["git", "checkout"], "gs": ["git", "status"], "loop": ["loop"], "a": ["b"],
        "b": ["a"],
    ]

    private func shape(_ line: String) -> LineShape? {
        CompletionToken(line).map { LineShape.of($0, aliases: aliases) }
    }

    @Test("An alias for a program takes that program's verbs.")
    func aliasedProgram() {
        #expect(shape("g chec") == LineShape(command: "git", kind: .subcommand(of: "git")))
    }

    @Test("An alias that carries a verb reads the words after it as that verb's arguments.")
    func aliasedVerb() {
        #expect(shape("gco fe") == LineShape(command: "git", kind: .branch))
        #expect(shape("gs sta") == LineShape(command: "git", kind: .free))
    }

    @Test("An alias behind a wrapper is read too.")
    func behindWrapper() {
        #expect(shape("sudo g chec") == LineShape(command: "git", kind: .subcommand(of: "git")))
    }

    @Test("Aliases that name themselves or each other stop expanding.")
    func cycle() {
        #expect(shape("loop x") == LineShape(command: "loop", kind: .free))
        #expect(shape("a x") != nil)
    }

    @Test("Without aliases a shorthand is an unknown program.")
    func withoutAliases() {
        #expect(CompletionToken("g chec").map(LineShape.of) == LineShape(command: "g", kind: .free))
    }
}

@Suite("Reading what a shell's aliases run")
struct ShellAliasExpansionTests {
    @Test("A quoted body becomes the words it runs.")
    func quotedBody() {
        let text = "alias gs='git status'\nalias g=git\n  alias ll=\"ls -la\"\n"
        #expect(
            ShellAliases.expansions(in: text) == [
                "gs": ["git", "status"], "g": ["git"], "ll": ["ls", "-la"],
            ])
    }

    @Test("A body the shell must run to settle is left out.")
    func unsettledBody() {
        let text =
            "alias a='git status | head'\nalias b='echo $(date)'\nalias c='ls; pwd'\nalias d='*'\nalias e=''\n"
        #expect(ShellAliases.expansions(in: text).isEmpty)
    }

    @Test("A later declaration of a name replaces an earlier one.")
    func later() {
        #expect(ShellAliases.expansions(in: "alias g=svn\nalias g=git\n") == ["g": ["git"]])
    }
}
