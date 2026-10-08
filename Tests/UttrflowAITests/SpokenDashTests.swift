import Testing
import UttrflowCore

@testable import UttrflowAI

@Suite("Spoken dash in technical destinations", .bug(id: 2502))
struct SpokenDashTests {
    @Test("writes long options and hyphenated names in terminals and editors")
    func writesTechnicalDashes() async throws {
        for destination in [Destination.terminal, .codeEditor, .sqlEditor, .document] {
            for (spoken, expected) in [
                ("Run npm install dash dash save dev", "Run npm install --save-dev"),
                ("Run git log dash dash oneline", "Run git log --oneline"),
                ("The branch is fix dash login dash bug", "The branch is fix-login-bug"),
                ("Git commit dash m fix the bug", "Git commit -m fix the bug"),
                ("Ls dash la", "Ls -la"),
            ] {
                let app = AppContext()
                let situation = Situation(app: app, insertion: app.insertionPoint, destination: destination)
                let request = TransformationRequest(
                    transcription: .fixture(text: spoken, language: .english), situation: situation)
                let result = try await RuleBasedTransformer().transform(request)
                // The dash is the subject here; the full stop is whatever the place's stop policy says.
                let stops = DestinationFormatter.registry[destination]?.terminalStop == .always
                #expect(result.text == expected + (stops ? "." : ""))
            }
        }
    }

    @Test("keeps paired clause dashes as em dashes in prose")
    func keepsProseDash() async throws {
        let request = TransformationRequest(
            transcription: .fixture(
                text: "we went home dash it was late", language: .english))
        #expect(try await RuleBasedTransformer().transform(request).text == "We went home — it was late.")
    }

    @Test("keeps a prose dash an em dash when a command noun is elsewhere in the sentence")
    func keepsProseDashBesideCommandNouns() {
        for (spoken, expected) in [
            ("i merged the branch dash it fixes the bug", "i merged the branch — it fixes the bug"),
            ("the new branch dash we should delete it", "the new branch — we should delete it"),
            (
                "she is in command dash we think dash of the unit",
                "she is in command — we think — of the unit"
            ),
            ("the terminal dash so it seems dash is old", "the terminal — so it seems — is old"),
            ("the branch is fix dash login dash bug", "the branch is fix-login-bug"),
            ("git commit dash m fix the bug", "git commit -m fix the bug"),
        ] {
            let draft = Draft(text: spoken)
            #expect(SpokenPunctuationPass().apply(draft).text == expected)
        }
    }

    @Test("decides a pair of spoken dashes as one: both marks or neither", .bug(id: 4446))
    func decidesDashPairsTogether() {
        for (spoken, expected) in [
            ("the price dash about ten dollars dash is fine", "the price — about ten dollars — is fine"),
            ("the build dash which failed twice dash is green", "the build — which failed twice — is green"),
            ("the files dash all of them dash are gone", "the files — all of them — are gone"),
            ("open monday dash friday dash next week", "open monday — friday — next week"),
            ("my sister dash the doctor dash called", "my sister dash the doctor dash called"),
            ("send it dash off dash now", "send it dash off dash now"),
            ("run ls dash l and then dash a", "run ls -l and then -a"),
        ] {
            #expect(SpokenPunctuationPass().apply(Draft(text: spoken)).text == expected)
        }
    }
}

@Suite("Command-line flags read from the spoken command table")
struct CommandLineFlagTests {
    @Test("a dash at a shell prompt is an option marker, said short, long or double")
    func writesFlagsAtAPrompt() {
        for (spoken, expected) in [
            ("docker run dash d nginx", "docker run -d nginx"),
            ("git push double dash force", "git push --force"),
            ("cargo build dash dash release", "cargo build --release"),
        ] {
            #expect(SpokenPunctuationPass(destination: .terminal).apply(Draft(text: spoken)).text == expected)
        }
    }

    @Test("a determiner before a doubled dash makes it a noun at a shell prompt, not an option")
    func determinerNamesTheDash() {
        let prose = "make a double dash across the yard before the rain"
        #expect(SpokenPunctuationPass(destination: .terminal).apply(Draft(text: prose)).text == prose)
        #expect(
            SpokenPunctuationPass(destination: .terminal).apply(Draft(text: "make dash dash help")).text
                == "make --help")
    }

    @Test("a program the lexicon knows makes the dashes after it options in prose")
    func readsCommandsFromTheLexicon() {
        let draft = Draft(text: "run brew install dash dash cask firefox")
        #expect(SpokenPunctuationPass().apply(draft).text == "run brew install --cask firefox")
    }

    @Test(
        "joins every dash-separated segment of a long option, a spoken no or with included",
        .bug(id: 4443),
        arguments: [Destination.terminal, .codeEditor])
    func joinsMultiSegmentFlags(destination: Destination) {
        for (spoken, expected) in [
            ("git push dash dash force dash with dash lease", "git push --force-with-lease"),
            ("git commit dash dash no dash verify", "git commit --no-verify"),
            ("docker build dash dash no dash cache", "docker build --no-cache"),
            ("git log dash dash no dash merges dash first dash parent", "git log --no-merges-first-parent"),
            ("npm install dash dash save dev", "npm install --save-dev"),
            ("yarn add dash dash dev", "yarn add --dev"),
            ("git commit dash dash no dash verify dash m wip", "git commit --no-verify -m wip"),
            ("docker run dash dash rm dash p eighty nginx", "docker run --rm -p eighty nginx"),
        ] {
            let corrected = SelfCorrectionPass().apply(Draft(text: spoken))
            #expect(SpokenPunctuationPass(destination: destination).apply(corrected).text == expected)
        }
    }

    @Test("yarn, a program the lexicon knows, still makes its dashes options in prose")
    func keepsYarnAsACommand() {
        let draft = Draft(text: "yarn add dash dash dev")
        #expect(SpokenPunctuationPass().apply(draft).text == "yarn add --dev")
    }
}

@Suite("Short options spelled letter by letter or said as a number", .bug(id: 4073))
struct ShortOptionClusterTests {
    static let cases: [(String, String)] = [
        ("ls dash l", "ls -l"),
        ("ls dash l a", "ls -la"),
        ("rm dash r f build", "rm -rf build"),
        ("tar dash x z v f archive", "tar -xzvf archive"),
        ("tar dash c z v f out", "tar -czvf out"),
        ("ps dash e f", "ps -ef"),
        ("sort dash r n", "sort -rn"),
        ("rsync dash a v z h src", "rsync -avzh src"),
        ("ls dash l a h t r s", "ls -lahtrs"),
        ("ls dash capital r", "ls -R"),
        ("cp dash capital r v src", "cp -Rv src"),
        ("du dash s h", "du -sh"),
        ("grep dash r n i todo", "grep -rni todo"),
        ("chmod dash capital r x", "chmod -Rx"),
        ("ls dash la", "ls -la"),
        ("head dash twenty", "head -20"),
        ("tail dash five hundred", "tail -500"),
        ("head dash 20", "head -20"),
        ("head dash twenty file", "head -20 file"),
        ("git log dash three", "git log -3"),
        ("netstat dash t u l p n", "netstat -tulpn"),
        ("git commit dash a m fix", "git commit -am fix"),
        ("docker run dash i t ubuntu", "docker run -it ubuntu"),
        ("ssh dash v host", "ssh -v host"),
        ("ls dash l a.", "ls -la."),
    ]

    @Test("joins a spelled cluster or a spoken number into one option at a prompt and in an editor")
    func joinsClustersInTechnicalDestinations() {
        for destination in [Destination.terminal, .codeEditor] {
            for (spoken, expected) in Self.cases {
                let written = SpokenPunctuationPass(destination: destination).apply(Draft(text: spoken)).text
                #expect(written == expected)
            }
        }
    }

    @Test("joins them in plain text after a program the lexicon knows")
    func joinsClustersAfterACommandInProse() {
        for (spoken, expected) in [
            ("run ls dash l a", "run ls -la"),
            ("run rm dash r f build", "run rm -rf build"),
            ("run tar dash x z v f archive", "run tar -xzvf archive"),
            ("run ls dash capital r", "run ls -R"),
        ] {
            #expect(SpokenPunctuationPass().apply(Draft(text: spoken)).text == expected)
        }
    }

    @Test("keeps prose dashes and names unread as options")
    func leavesProseAndNames() {
        for (spoken, expected) in [
            ("we went home dash it was late", "we went home — it was late"),
            ("she won dash a b c", "she won — a b c"),
        ] {
            #expect(SpokenPunctuationPass().apply(Draft(text: spoken)).text == expected)
        }
    }
}
