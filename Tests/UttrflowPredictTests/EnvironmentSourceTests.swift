import Foundation
import Testing

@testable import UttrflowPredict

/// A machine that says what a test tells it to, and counts how often it is asked; a kind it was told nothing about is one it cannot read.
actor StubEnvironment: EnvironmentReading {
    private let answers: [EnvironmentKind: [String]]
    private let delay: Duration?
    private(set) var reads = 0

    init(_ answers: [EnvironmentKind: [String]], delay: Duration? = nil) {
        self.answers = answers
        self.delay = delay
    }

    func values(of kind: EnvironmentKind, in directory: String) async -> [String]? {
        reads += 1
        if let delay { try? await Task.sleep(for: delay) }
        return answers[kind]
    }
}

/// A terminal sitting in a working directory, which is the only surface this source answers for.
let terminal = Surface(
    bundleIdentifier: "com.example.terminal", role: "AXTextArea", scope: "/repo")

/// A fixed moment, so every cache lifetime in this suite is exact rather than nearly right.
let moment = Date(timeIntervalSince1970: 1_800_000_000)

/// The candidates a warmed source offers, which takes two passes because the first only asks.
func offered(
    _ answers: [EnvironmentKind: [String]],
    typing typed: String,
    in surface: Surface = terminal,
    at now: Date = moment
) async -> [String] {
    let index = EnvironmentIndex(reader: StubEnvironment(answers))
    let source = EnvironmentSource(index: index)
    _ = await source.candidates(for: surface, matching: typed, now: now)
    await index.settle()
    return await source.candidates(for: surface, matching: typed, now: now).map(\.text)
}

@Suite("What exists on this machine right now")
struct EnvironmentSourceTests {
    @Test("A field with no scope is offered nothing, because there is no directory to read.")
    func withoutScope() async {
        let anywhere = Surface(bundleIdentifier: "com.example.notes", role: "AXTextArea")
        #expect(await offered([.file: ["notes.md"]], typing: "no", in: anywhere).isEmpty)
    }

    @Test("A web field is offered nothing, because its scope is a host rather than a directory.")
    func webScopeIsNotADirectory() async {
        let browser = Surface(
            bundleIdentifier: "com.example.browser", role: "AXTextField", scope: "example.com")
        #expect(await offered([.file: ["example.md"]], typing: "ex", in: browser).isEmpty)
    }

    @Test("A directory written with a tilde is still a directory.")
    func tildeIsADirectory() async {
        let home = Surface(
            bundleIdentifier: "com.example.terminal", role: "AXTextArea", scope: "~/work")
        #expect(await offered([.file: ["report.md"]], typing: "cat re", in: home) == ["cat report.md"])
    }

    @Test("The first word is completed from the programs and aliases this machine has.")
    func firstWordIsACommand() async {
        let answers: [EnvironmentKind: [String]] = [
            .executable: ["grep"], .alias: ["gs"], .branch: ["gold"], .file: ["gone.txt"],
        ]
        #expect(await offered(answers, typing: "g") == ["grep", "gs"])
    }

    @Test(
        "An argument is completed from what its command takes: branches after checkout, files after cat, directories after cd."
    )
    func laterWordIsAnArgument() async {
        let answers: [EnvironmentKind: [String]] = [
            .executable: ["grep"], .alias: ["gs"], .branch: ["gold"], .file: ["gone.txt", "go"],
            .directory: ["go"],
        ]
        #expect(await offered(answers, typing: "git checkout g") == ["git checkout gold"])
        #expect(await offered(answers, typing: "cat g") == ["cat go", "cat gone.txt"])
        #expect(await offered(answers, typing: "cd g") == ["cd go"])
    }

    @Test("A word a command reads as text is still offered the names here, as a shell offers them.")
    func freeWordsAreOfferedFiles() async {
        #expect(await offered([.file: ["hello.txt"]], typing: "echo hel") == ["echo hello.txt"])
    }

    @Test("A path is completed under the directory it points into, and the candidate carries the path.")
    func pathsAreCompletedWhereTheyPoint() async {
        let answers: [EnvironmentKind: [String]] = [
            .directories(under: "Sources"): ["UttrflowPredict", "Uttrflow"], .directory: ["Sources"],
        ]
        #expect(
            await offered(answers, typing: "cd Sources/Utt") == [
                "cd Sources/Uttrflow", "cd Sources/UttrflowPredict",
            ])
    }

    @Test(
        "A path the shell resolves from the terminal's directory, from home or from root, as the shell would."
    )
    func pathsResolveLikeTheShell() {
        #expect(SystemEnvironmentReader.resolve(".", from: "/repo") == "/repo")
        #expect(SystemEnvironmentReader.resolve("Sources", from: "/repo") == "/repo/Sources")
        #expect(SystemEnvironmentReader.resolve("../other", from: "/repo/app") == "/repo/other")
        #expect(SystemEnvironmentReader.resolve("/etc", from: "/repo") == "/etc")
        #expect(SystemEnvironmentReader.resolve("~", from: "/repo").hasPrefix("/"))
        #expect(!SystemEnvironmentReader.resolve("~/x", from: "/repo").contains("~"))
    }

    @Test("Indentation before the command does not make it an argument.")
    func leadingSpacesKeepTheFirstWord() async {
        #expect(await offered([.executable: ["swift"]], typing: "  sw") == ["  swift"])
    }

    @Test("A candidate carries the whole line, not only the word it finishes.")
    func candidatesCarryTheWholeLine() async {
        #expect(
            await offered([.branch: ["feature/predict"]], typing: "git checkout fea")
                == ["git checkout feature/predict"])
    }

    @Test("A line ending in a space is offered nothing, because no word has been started.")
    func nothingToFinish() async {
        #expect(await offered([.branch: ["main"]], typing: "git checkout ").isEmpty)
    }

    @Test("An empty field is offered nothing at all.")
    func emptyFieldIsQuiet() async {
        #expect(await offered([.executable: ["swift"]], typing: "").isEmpty)
    }

    @Test("A word that is already complete is not offered back.")
    func alreadyTyped() async {
        #expect(await offered([.branch: ["main"]], typing: "git switch main").isEmpty)
    }

    @Test("Matching ignores case, and the candidate keeps the machine's own spelling.")
    func matchingIgnoresCase() async {
        #expect(await offered([.file: ["README.md"]], typing: "cat rea") == ["cat README.md"])
    }

    @Test("The shortest completion comes first, and equal lengths sort alphabetically.")
    func shortestFirst() async {
        let branches = ["main-and-more", "mainline", "maintain", "main-x"]
        #expect(
            await offered([.branch: branches], typing: "git switch m").map {
                String($0.dropFirst("git switch ".count))
            } == ["main-x", "mainline", "maintain", "main-and-more"])
    }

    @Test("A name that is both a branch and a file is offered once.")
    func duplicatesCollapse() async {
        #expect(await offered([.branch: ["docs"], .file: ["docs"]], typing: "ls d") == ["ls docs"])
    }

    @Test("No more than eight of one kind reach the ranking, however large the directory.")
    func floodsAreCapped() async {
        let many = (0..<40).map { "file\($0).txt" }
        let candidates = await offered([.file: many], typing: "ls f")
        #expect(candidates.count == EnvironmentSource.maximumPerKind)
    }

    @Test("Every candidate says it came from the environment and brings no corpus evidence.")
    func candidatesAreEnvironmental() async {
        let index = EnvironmentIndex(reader: StubEnvironment([.branch: ["main"]]))
        let source = EnvironmentSource(index: index)
        _ = await source.candidates(for: terminal, matching: "git switch m", now: moment)
        await index.settle()
        let candidates = await source.candidates(for: terminal, matching: "git switch m", now: moment)
        #expect(candidates.map(\.source) == [.environment])
        #expect(candidates.allSatisfy { $0.evidence == nil && !$0.isIrreversible })
    }

    @Test("A machine that answers nothing offers nothing.")
    func emptyMachineIsQuiet() async {
        #expect(await offered([:], typing: "git switch m").isEmpty)
    }
}

@Suite("Never waiting on the machine")
struct EnvironmentIndexTests {
    @Test("The first keystroke is answered from nothing, since the read has only just started.")
    func firstKeystrokeIsEmpty() async {
        let index = EnvironmentIndex(reader: StubEnvironment([.branch: ["main"]]))
        #expect(await index.values(of: .branch, in: "/repo", now: moment) == nil)
        await index.settle()
        #expect(await index.values(of: .branch, in: "/repo", now: moment) == ["main"])
    }

    @Test("A slow machine is left behind rather than waited for.")
    func slowReadsAreAbandoned() async {
        let index = EnvironmentIndex(
            reader: StubEnvironment([.branch: ["main"]], delay: .seconds(2)))
        let started = ContinuousClock.now
        #expect(await index.values(of: .branch, in: "/repo", now: moment) == nil)
        #expect(ContinuousClock.now - started < .milliseconds(500))
    }

    @Test("A burst of keystrokes asks the machine once, not once each.")
    func oneReadPerBurst() async {
        let reader = StubEnvironment([.file: ["notes.md"]], delay: .milliseconds(20))
        let index = EnvironmentIndex(reader: reader)
        for _ in 0..<5 { _ = await index.values(of: .file, in: "/repo", now: moment) }
        await index.settle()
        #expect(await reader.reads == 1)
    }

    @Test("An answer is believed for its lifetime and read again after it.")
    func staleAnswersAreReadAgain() async {
        let reader = StubEnvironment([.file: ["notes.md"]])
        let index = EnvironmentIndex(reader: reader)
        _ = await index.values(of: .file, in: "/repo", now: moment)
        await index.settle()

        let believed = moment.addingTimeInterval(EnvironmentIndex.lifetimeInSeconds - 1)
        #expect(await index.values(of: .file, in: "/repo", now: believed) == ["notes.md"])
        await index.settle()
        #expect(await reader.reads == 1)

        let stale = moment.addingTimeInterval(EnvironmentIndex.lifetimeInSeconds + 1)
        _ = await index.values(of: .file, in: "/repo", now: stale)
        await index.settle()
        #expect(await reader.reads == 2)
    }

    @Test("Two directories are two answers, because what exists in each is different.")
    func directoriesAreSeparate() async {
        let reader = StubEnvironment([.file: ["notes.md"]])
        let index = EnvironmentIndex(reader: reader)
        _ = await index.values(of: .file, in: "/one", now: moment)
        _ = await index.values(of: .file, in: "/two", now: moment)
        await index.settle()
        #expect(await reader.reads == 2)
    }
}

@Suite("Reading a shell's aliases")
struct ShellAliasesTests {
    @Test("An alias declaration yields the name it binds.")
    func plainAlias() {
        #expect(ShellAliases.names(in: "alias gs='git status'") == ["gs"])
    }

    @Test("Indentation and several declarations are read in the order they appear.")
    func severalAliases() {
        let configuration = """
            export EDITOR=vim
              alias ll="ls -la"
            alias gp='git push'
            """
        #expect(ShellAliases.names(in: configuration) == ["ll", "gp"])
    }

    @Test("A line that is not an alias declaration is ignored.")
    func otherLines() {
        #expect(ShellAliases.names(in: "aliased=1\n# alias gs='git status'\n").isEmpty)
    }

    @Test("An alias with no binding is ignored, because there is no name to read.")
    func noBinding() {
        #expect(ShellAliases.names(in: "alias\nalias -p\n").isEmpty)
    }

    @Test("A shell's flags are not names, so a global alias is ignored.")
    func flagsAreNotNames() {
        #expect(ShellAliases.names(in: "alias -g L='| less'").isEmpty)
    }

    @Test("A name a shell would have to quote is ignored.")
    func quotedNamesAreIgnored() {
        #expect(ShellAliases.names(in: "alias 'my thing'='ls'\nalias =x\n").isEmpty)
    }

    @Test("Digits, dots, dashes and underscores are all part of a name.")
    func nameCharacters() {
        #expect(ShellAliases.names(in: "alias g.2_x-y=ls") == ["g.2_x-y"])
    }
}
