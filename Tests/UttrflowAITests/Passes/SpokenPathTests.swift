import Testing
import UttrflowCore

@testable import UttrflowAI

@Suite("A spoken path", .bug(id: 6565))
struct SpokenPathTests {
    private let prose = SpokenPunctuationPass()
    private let terminal = SpokenPunctuationPass(destination: .terminal)

    @Test(
        "writes a path that opens with a home or dot root, or holds a hidden name",
        arguments: [
            ("tilde slash dot s s h slash config holds the jump host", "~/.ssh/config holds the jump host"),
            ("the config is in tilde slash dot config slash app", "the config is in ~/.config/app"),
            ("cd tilde slash projects", "cd ~/projects"),
            ("run dot slash scripts slash build dot sh", "run ./scripts/build.sh"),
            ("the helpers are in dot dot slash lib slash util", "the helpers are in ../lib/util"),
            ("slash home slash sam slash dot bashrc is long", "/home/sam/.bashrc is long"),
            ("slash etc slash nginx slash sites dash enabled", "/etc/nginx/sites-enabled"),
        ]
    )
    func writesRootedPaths(input: String, expected: String) {
        #expect(cleaned(input, by: prose) == expected)
    }

    @Test(
        "writes a hidden file named by a dot before a name the lexicon writes as a file ending",
        arguments: [
            (
                "copy dot env dot example to dot env and set the port",
                "copy .env.example to .env and set the port"
            ),
            ("edit the dot env file", "edit the .env file"),
            ("rename it to dot gitignore", "rename it to .gitignore"),
            ("dot env holds the keys", ".env holds the keys"),
            ("open the dot env dot local file", "open the .env.local file"),
        ]
    )
    func writesHiddenFiles(input: String, expected: String) {
        #expect(cleaned(input, by: prose) == expected)
    }

    @Test(
        "leaves dot and tilde in prose as words",
        arguments: [
            "dot the i's and cross the t's", "dot your i's before you sign", "a tilde over the n",
            "the tilde key is broken", "connect the dots", "the dot md files", "a dot json",
            "keep the dot env out of the repo", "learn swift dot go", "put a dot on the map",
            "a tilde slash accent", "she said dot dot dot and left", "dot com companies",
        ]
    )
    func leavesProse(input: String) {
        #expect(cleaned(input, by: prose) == input)
    }

    @Test(
        "writes labels joined by slash as a path at a command line, where no path word announces one",
        arguments: [
            ("grep error logs slash app dot log", "grep error logs/app.log"),
            ("tail var slash log slash system dot log", "tail var/log/system.log"),
            ("cd slash tmp", "cd /tmp"),
            ("cd slash users slash sam", "cd /users/sam"),
            ("cd tilde slash projects", "cd ~/projects"),
        ]
    )
    func writesCommandLinePaths(input: String, expected: String) {
        #expect(cleaned(input, by: terminal) == expected)
    }

    @Test("leaves the same unannounced words as prose outside a command line")
    func leavesUnannouncedProsePaths() {
        let unannounced = "grep error logs slash app dot log"
        #expect(cleaned(unannounced, by: prose) == unannounced)
        #expect(cleaned("cd slash tmp", by: prose) == "cd slash tmp")
    }

    @Test(
        "writes the reported dictations through every pass",
        arguments: [
            (
                AppContext(applicationName: "Terminal", bundleIdentifier: "com.apple.Terminal"),
                "grep dash r error logs slash app dot log pipe sort pipe uniq dash c pipe sort dash n r pipe head dash twenty",
                "grep -r error logs/app.log | sort | uniq -c | sort -nr | head -20"
            ),
            (
                AppContext.unknown,
                "tilde slash dot s s h slash config holds the jump host and it needs mode six hundred",
                "~/.ssh/config holds the jump host and it needs mode 600."
            ),
            (
                AppContext.unknown,
                "copy dot env dot example to dot env and set the port",
                "Copy .env.example to .env and set the port."
            ),
        ]
    )
    func writesReportedDictations(app: AppContext, spoken: String, expected: String) {
        let situation = SituationResolver.resolve(from: app)
        let formatter = DestinationFormatter.standard(for: situation.destination)
        let pipeline = CleaningPipeline.standard(for: formatter, situation: situation)
        #expect(pipeline.run(Draft(text: spoken)).text == expected)
    }

    /// The pass converts rather than deletes, so the root and the hidden name's dot sit inside its own grant.
    @Test("leaves the meaning guard nothing to answer for")
    func removalsAreAuthorised() {
        let draft = prose.apply(Draft(text: "copy tilde slash dot s s h slash config to dot env"))
        #expect(RemovalAudit.unauthorised(in: draft, grants: CleaningPipeline.standard.grants).isEmpty)
        #expect(
            MeaningPreservationGuard().verdict(draft: draft, rewritten: "Copy ~/.ssh/config to .env.")
                == .accepted)
    }
}
