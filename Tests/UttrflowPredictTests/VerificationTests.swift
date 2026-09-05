import Testing

@testable import UttrflowPredict

/// The git subcommands a machine with a repository in front of it would list.
private let subcommands: Set<String> = ["commit", "checkout", "status", "stash", "push"]

/// The word a candidate ends on, which is what the gates judge.
private func word(_ line: String) -> CompletionToken? { CompletionToken(line) }

@Suite("Correctness above habit")
struct VerificationTests {
    @Test("A word the machine vouches for is attested, however unlikely the model finds it.")
    func attestationOutranksTheModel() {
        #expect(Verification.verdict(word: "cm", known: ["cm", "commit"], modelObjects: true) == .attested)
    }

    @Test("A word one cheap slip from a name the machine knows is corrected to that name.")
    func correctsOneSlip() {
        #expect(
            Verification.verdict(word: "comit", known: subcommands, modelObjects: false)
                == .corrected("commit"))
        #expect(
            Verification.verdict(word: "stauts", known: subcommands, modelObjects: false)
                == .corrected("status"))
    }

    @Test("A machine that has said nothing has not denied anything, so the candidate stands.")
    func silenceIsNotDenial() {
        #expect(Verification.verdict(word: "comit", known: [], modelObjects: false) == .plausible)
    }

    @Test("A word the machine cannot place and the model dislikes is not offered at all.")
    func rejectsWhatNothingSupports() {
        #expect(Verification.verdict(word: "zqxjw", known: subcommands, modelObjects: true) == .rejected)
    }

    @Test("A word the machine cannot place still stands while nothing objects to it.")
    func keepsWhatNothingObjectsTo() {
        #expect(Verification.verdict(word: "zqxjw", known: subcommands, modelObjects: false) == .plausible)
    }

    @Test("Nothing under three characters is corrected, because a short word matches everything.")
    func shortWordsAreNeverCorrected() {
        #expect(Verification.nearestNeighbour(of: "cm", among: subcommands) == nil)
        #expect(Verification.nearestNeighbour(of: "", among: subcommands) == nil)
    }

    @Test("A slip in the first character is not corrected, because people rarely make one.")
    func firstCharacterIsLeftAlone() {
        #expect(Verification.nearestNeighbour(of: "xommit", among: subcommands) == nil)
    }

    @Test("A key nowhere near the intended one is too far to be a slip.")
    func distantSubstitutionIsNotASlip() {
        #expect(Verification.nearestNeighbour(of: "commiz", among: subcommands) == nil)
    }

    @Test("A neighbour beside the intended key is close enough to be a slip.")
    func adjacentSubstitutionIsASlip() {
        #expect(Verification.nearestNeighbour(of: "commir", among: subcommands) == "commit")
    }

    @Test("Two neighbours equally near are settled in one order rather than by chance.")
    func tiesAreSettledTheSameWayEveryTime() {
        #expect(Verification.nearestNeighbour(of: "abc", among: ["axbc", "abyc"]) == "abyc")
    }

    @Test("A word already in the machine's list is never corrected to something else.")
    func aKnownWordIsNotCorrected() {
        #expect(Verification.verdict(word: "stash", known: subcommands, modelObjects: false) == .attested)
    }

    @Test("The floor sits between what the 4B model gives a real line and what it gives nonsense.")
    func floorSeparatesMeasuredScores() {
        // Mean log-probabilities per token measured with `uttrflow-bakeoff score` on gemma-3-4b-it-qat-4bit.
        let realLines = [-0.18, -1.24, -0.35, -1.64, -3.26, -4.65]
        let nonsense = [-9.15, -13.60, -10.62, -11.77, -7.29]
        for score in realLines { #expect(!Verification.objects(to: .scored(score)), "\(score)") }
        for score in nonsense { #expect(Verification.objects(to: .scored(score)), "\(score)") }
    }

    @Test("The model objects only when it has scored the candidate below the floor.")
    func objectionNeedsAScore() {
        #expect(Verification.objects(to: .scored(Verification.plausibilityFloor - 1)))
        #expect(!Verification.objects(to: .scored(Verification.plausibilityFloor)))
        #expect(!Verification.objects(to: .silent))
        #expect(!Verification.objects(to: .overBudget))
    }

    @Test("The first word of a line is vouched for by programs and shell aliases.")
    func firstWordIsAProgram() throws {
        let token = try #require(word("gi"))
        #expect(Verification.attestingKinds(for: token) == [.executable, .alias])
    }

    @Test("The word after git is vouched for by git's own subcommands and the user's git aliases.")
    func gitSubcommandsVouchForTheSecondWord() throws {
        let token = try #require(word("git comit"))
        #expect(Verification.attestingKinds(for: token) == [.subcommand(of: "git"), .gitAlias])
    }

    @Test(
        "An argument is vouched for by what its command takes: a target, a branch, a file; a word read as text by nothing."
    )
    func argumentsFollowTheirCommand() throws {
        #expect(
            Verification.attestingKinds(for: try #require(word("make verif"))) == [.subcommand(of: "make")])
        #expect(Verification.attestingKinds(for: try #require(word("git checkout mai"))) == [.branch])
        #expect(Verification.attestingKinds(for: try #require(word("cat READ"))) == [.file])
        #expect(Verification.attestingKinds(for: try #require(word("echo hel"))).isEmpty)
    }

    @Test("Programs and their verbs name everything there is; paths and branches never do.")
    func closedVocabularies() {
        #expect(Verification.isClosedVocabulary([.executable, .alias]))
        #expect(Verification.isClosedVocabulary([.subcommand(of: "make")]))
        #expect(!Verification.isClosedVocabulary([.branch]))
        #expect(!Verification.isClosedVocabulary([.directories(under: "Sources")]))
    }

    @Test("A verdict says whether the machine vouched for it and whether anything may be drawn.")
    func verdictsReadTheirOwnMeaning() {
        #expect(Verdict.attested.isAttested)
        #expect(!Verdict.plausible.isAttested)
        #expect(Verdict.plausible.allowsOffering)
        #expect(Verdict.corrected("git commit").allowsOffering)
        #expect(!Verdict.rejected.allowsOffering)
    }
}

@Suite("The names git binds")
struct GitAliasesTests {
    @Test("Every alias git configuration declares is read, in the order it declares them.")
    func readsNames() {
        let configuration = """
            alias.cm commit -m
            alias.co checkout
            alias.lg log --oneline --graph
            """
        #expect(GitAliases.names(in: configuration) == ["cm", "co", "lg"])
    }

    @Test("A line that binds nothing, or binds nothing to a name, is not an alias.")
    func ignoresAnythingElse() {
        #expect(GitAliases.names(in: "user.name Someone\ncore.editor vim").isEmpty)
        #expect(GitAliases.names(in: "alias. commit").isEmpty)
        #expect(GitAliases.names(in: "").isEmpty)
    }
}

/// What the machine is asked about the last word of a line the model wrote, as `name → kinds` for each lookup.
private func asked(_ line: String) -> [String]? {
    CompletionToken(line).flatMap(Verification.attestation(for:))?.lookups.map { "\($0.word) → \($0.kinds)" }
}

/// One lookup as `asked` renders it.
private func lookup(_ word: String, _ kinds: [EnvironmentKind]) -> String { "\(word) → \(kinds)" }

/// The words a completion adds to a line, as text, with what precedes each.
private func added(_ typed: String, _ completion: String) -> [String] {
    Verification.words(of: typed + completion, addedAfter: typed).map { "\($0.leading)|\($0.token)" }
}

@Suite("What the machine can deny in a line the model wrote")
struct GeneratedAttestationTests {
    @Test("The first word is a program or an alias, and is looked up as one.")
    func firstWordIsAProgram() {
        #expect(asked("gti") == [lookup("gti", [.executable, .alias])])
    }

    @Test("The word after git is one of its subcommands or aliases; after make, one of its targets.")
    func verbsAreLookedUpWithTheirProgram() {
        #expect(asked("git chekout") == [lookup("chekout", [.subcommand(of: "git"), .gitAlias])])
        #expect(asked("make venv") == [lookup("venv", [.subcommand(of: "make")])])
        #expect(asked("npm run dev") == [lookup("dev", [.subcommand(of: "npm run")])])
        #expect(asked("sudo make instal") == [lookup("instal", [.subcommand(of: "make")])])
    }

    @Test(
        "A path is looked up by its last name under the directory before it, as the shell would resolve it.")
    func pathsAreLookedUpWhereTheyPoint() {
        #expect(
            asked("cd projects/x-growth/backend/") == [
                lookup("backend", [.directories(under: "projects/x-growth")])
            ])
        #expect(asked("Scripts/bundle.sh") == [lookup("bundle.sh", [.entries(under: "Scripts")])])
        #expect(asked("cat /etc/hosts") == [lookup("hosts", [.entries(under: "/etc")])])
        #expect(asked("cd ~/projects") == [lookup("projects", [.directories(under: "~")])])
        #expect(asked("vim ../backend/main.py") == [lookup("main.py", [.entries(under: "../backend")])])
        #expect(asked("./run.sh") == [lookup("run.sh", [.entries(under: ".")])])
    }

    @Test("Here and the parent are not names to look up, and a branch with a slash may be a path git takes.")
    func pathEdges() {
        #expect(asked("cd ..") == nil)
        #expect(asked("cd ../..") == nil)
        #expect(
            asked("git checkout feat/login") == [
                lookup("feat/login", [.branch]), lookup("login", [.entries(under: "feat")]),
            ])
    }

    @Test("A directory command narrows a path to directories; a file command and an unknown one do not.")
    func directoryCommandsWantDirectories() {
        #expect(asked("cd Sour") == [lookup("Sour", [.directory])])
        #expect(asked("ls Sour") == [lookup("Sour", [.file])])
        #expect(asked("vim .env.vim") == [lookup(".env.vim", [.file])])
        #expect(asked("myapp .env.vim") == [lookup(".env.vim", [.file])])
        #expect(asked("myapp Sources/x") == [lookup("x", [.entries(under: "Sources")])])
    }

    @Test(
        "A flag, a number, a quotation, an expansion or an address could be anything, so nothing denies it.")
    func freeWordsAreNeverAsked() {
        for line in [
            "git checkout -b", "head -n 20", "git commit -m \"fix", "echo $HOME/x", "rm *.log",
            "curl https://example.com/a", "FOO=bar", "ssh user@host:path",
        ] {
            #expect(asked(line) == nil, "\(line)")
        }
    }

    @Test("A word a command reads as text is nobody's to deny.")
    func textArgumentsAreFree() {
        #expect(asked("echo hello") == nil)
        #expect(asked("myapp serve") == nil)
        #expect(asked("git commit fix") == nil)
        #expect(asked("grep TODO") == nil)
        #expect(asked("grep TODO Sour") == [lookup("Sour", [.file])])
    }

    @Test(
        "What the machine offers to finish a word is what could vouch for it, and for a free word the names here."
    )
    func offeringsFollowTheShape() throws {
        #expect(Verification.offerings(for: try #require(word("cd pro"))).map(\.kinds) == [[.directory]])
        #expect(Verification.offerings(for: try #require(word("echo hel"))).map(\.kinds) == [[.file]])
        #expect(Verification.offerings(for: try #require(word("git checkout -"))).isEmpty)
        let token = try #require(word("cd Sources/Utt"))
        let path = try #require(Verification.offerings(for: token).first)
        #expect(path.word == "Utt")
        #expect(path.prefix == "Sources/")
    }

    @Test("The words a completion adds are the model's, including the one it finished for the typist.")
    func addedWordsAreTheModels() {
        #expect(
            added("cd projects/x-growth/", "backend/ && npm run dev") == [
                "cd |projects/x-growth/backend/", "cd projects/x-growth/backend/ |&&",
                "cd projects/x-growth/backend/ && |npm", "cd projects/x-growth/backend/ && npm |run",
                "cd projects/x-growth/backend/ && npm run |dev",
            ])
        #expect(added("vim .env", ".vim") == ["vim |.env.vim"])
        #expect(added("git ", "status") == ["git |status"])
        #expect(added("ls", "").isEmpty)
    }

    @Test(
        "A word stands while the machine has not answered, or once it names the word in any case; an empty answer denies it."
    )
    func standsOnSilenceOrAName() {
        #expect(Verification.stands(".vim", known: nil))
        #expect(Verification.stands("readme.md", known: ["README.md", ".env"]))
        #expect(!Verification.stands(".vim", known: [".env", "src"]))
        #expect(!Verification.stands("backend", known: []))
    }
}

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

@Suite("Reading the verbs a program takes")
struct ProgramVerbsTests {
    @Test("A Makefile's targets are its rule heads, without variables, recipes, special targets or patterns.")
    func makefileTargets() {
        let makefile = """
            SWIFT := xcrun swift
            .PHONY: verify build
            verify: lint test
            \t$(SWIFT) test
            build test:
            \t@echo building
            %.o: %.c
            $(TARGET): build
            # release: not yet
            """
        #expect(MakefileTargets.names(in: makefile) == ["verify", "build", "test"])
    }

    @Test("A manifest's scripts are the keys of its scripts object, whatever their commands hold.")
    func packageScripts() {
        let manifest = """
            {
              "name": "app",
              "scripts": {
                "dev": "vite",
                "build": "tsc && vite build",
                "test:unit": "vitest run --reporter=\\"dot, verbose\\"",
                "lint": "eslint ."
              },
              "dependencies": { "vite": "^5" }
            }
            """
        #expect(PackageScripts.names(in: manifest) == ["build", "dev", "lint", "test:unit"])
        #expect(PackageScripts.names(in: "{ \"name\": \"app\" }") == [])
        #expect(PackageScripts.names(in: "scripts: dev") == nil)
    }

    @Test(
        "A help page's commands are its indented names, set off from their descriptions or listed with commas."
    )
    func helpCommands() {
        let docker = """
            Usage:  docker [OPTIONS] COMMAND

            Common Commands:
              run         Create and run a new container from an image
              exec        Execute a command in a running container
              ps          List containers

            Global Options:
                  --config string      Location of client config files
              -D, --debug              Enable debug mode
            """
        #expect(HelpCommands.names(in: docker) == ["run", "exec", "ps"])
        let gh =
            "CORE COMMANDS\n  auth:          Authenticate gh and git with GitHub\n  pr:            Manage pull requests\n"
        #expect(HelpCommands.names(in: gh) == ["auth", "pr"])
        let cargo =
            "Installed Commands:\n    add                  Add dependencies\n    audit\n    b                    alias: build\n"
        #expect(HelpCommands.names(in: cargo) == ["add", "audit", "b"])
        let npm = "All commands:\n\n    access, adduser, audit, bugs,\n    completion, config\n"
        #expect(
            HelpCommands.names(in: npm) == ["access", "adduser", "audit", "bugs", "completion", "config"])
        #expect(HelpCommands.names(in: "--cache\ncommands\ninstall\n") == ["commands", "install"])
        #expect(HelpCommands.names(in: "Usage: swift [options] file\n  Compiles the file given.\n").isEmpty)
    }
}
