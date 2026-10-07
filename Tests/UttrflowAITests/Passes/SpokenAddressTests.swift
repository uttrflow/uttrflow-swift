import Testing
import UttrflowCore

@testable import UttrflowAI

@Suite("A spoken address")
struct SpokenAddressTests {
    private let sut = SpokenPunctuationPass()

    @Test(
        "writes the address where the words spell one",
        arguments: [
            ("forward the logs to support at example.com", "forward the logs to support@example.com"),
            ("write to Sam dot Jones at Example dot com", "write to Sam.Jones@example.com"),
            ("visit Example dot com slash Docs", "visit example.com/Docs"),
            (
                "forward the logs to support at example dot com",
                "forward the logs to support@example.com"
            ),
            (
                "please send the contract to first.last at example.com by tonight",
                "please send the contract to first.last@example.com by tonight"
            ),
            (
                "please send the contract to priya dot shah at example dot com by tonight",
                "please send the contract to priya.shah@example.com by tonight"
            ),
            (
                "my work address is ops-team at mail.example.org",
                "my work address is ops-team@mail.example.org"
            ),
            (
                "my work address is ops-team at mail dot example dot org",
                "my work address is ops-team@mail.example.org"
            ),
            (
                "email me at sam at example dot com when it is ready",
                "email me at sam@example.com when it is ready"
            ),
            (
                "write to info at example dot com and billing at example dot net",
                "write to info@example.com and billing@example.net"
            ),
            ("contact support at example.com today", "contact support@example.com today"),
            ("cc billing at example dot com", "cc billing@example.com"),
        ]
    )
    func writesTheAddress(input: String, expected: String) {
        #expect(cleaned(input, by: sut) == expected)
    }

    /// The sentence's own stop sits on the domain's last word, so the address keeps it and the words either side of it.
    @Test(
        "keeps the marks the address stood with",
        arguments: [
            (
                "my work address is ops-team at mail.example.org.",
                "my work address is ops-team@mail.example.org."
            ),
            ("send it to support at example dot com.", "send it to support@example.com."),
            (
                "write to info at example dot com, and billing at example dot net",
                "write to info@example.com, and billing@example.net"
            ),
        ]
    )
    func keepsItsMarks(input: String, expected: String) {
        #expect(cleaned(input, by: sut) == expected)
    }

    @Test("leaves a piece ending on www dot alone, with no host after it to read")
    func wwwDotAtTheEnd() {
        #expect(cleaned("the site is www dot", by: sut) == "the site is www dot")
    }

    @Test(
        "leaves an ordinary at alone",
        arguments: [
            "look at example.com",
            "look at example.com when you have a minute",
            "i'll look at example.com",
            "we met at the office at five",
            "meet me at the office",
            "the docs are available at example.com",
            "the file is at example.com",
            "the invoice at example.com is wrong",
            "please send the report at example.com",
            "he works at Example dot com offices",
            "email me at example.com",
            "we are at 10.30 already",
            "send the invoice at 5 dot 30",
            "forward the logs to support, at example.com",
            "forward the logs to support at (example.com)",
            "it is just at the corner",
            "the car is parked at the airport",
            "it is not at all clear",
            "it is not at the front desk",
            "she is out at the shops",
            "the file is open at line ten",
            "the problem is right at the start",
        ]
    )
    func leavesOrdinaryAtAlone(input: String) {
        #expect(cleaned(input, by: sut) == input)
    }

    /// A bare number run after "at" is a time or a quantity, not a handle: "is it at three" reads as prose.
    @Test(
        "leaves is pronoun at number alone",
        arguments: [
            "what time is it at three thirty",
            "what time is it at five",
            "meet me at three thirty",
            "call me at five",
            "arrive at two thirty pm",
            "we are at ten am",
            "what time is it at five o clock",
            "see you at seven",
            "the talk is at ten",
        ]
    )
    func leavesPronounAtNumberAlone(input: String) {
        #expect(cleaned(input, by: sut) == input)
    }

    /// A domain needs an ending the pass knows, because guessing at one is how ordinary prose is rewritten.
    @Test(
        "leaves a domain whose ending it does not know",
        arguments: [
            "forward the logs to support at example.wibble",
            "forward the logs to support at example dot wibble",
            "forward the logs to support at example",
        ]
    )
    func leavesAnUnknownEnding(input: String) {
        #expect(cleaned(input, by: sut) == input)
    }

    @Test(
        "writes dictated web addresses paths filenames and identifiers",
        arguments: [
            ("visit example dot com slash docs", "visit example.com/docs"),
            ("the site is www dot example dot com", "the site is www.example.com"),
            ("go to https colon slash slash example dot com", "go to https://example.com"),
            ("go to w w w dot example dot org", "go to www.example.org"),
            ("visit w w w dot example dot com slash pricing", "visit www.example.com/pricing"),
            ("the url is h t t p s colon slash slash example dot com", "the url is https://example.com"),
            ("the url is http colon slash slash example dot com", "the url is http://example.com"),
            (
                "the docs live at docs dot example dot com slash api slash v two",
                "the docs live at docs.example.com/api/v2"
            ),
            ("open package dot json", "open package.json"),
            ("edit the dot env file", "edit the .env file"),
            ("update the readme dot md first", "update the readme.md first"),
            ("bump the version in package dot json", "bump the version in package.json"),
            ("the settings live in config dot yaml", "the settings live in config.yaml"),
            ("open main dot swift", "open main.swift"),
            ("the path is slash users slash sam slash notes", "the path is /users/sam/notes"),
            ("my handle is at sam underscore dev", "my handle is @sam_dev"),
            ("my handle is sam at discord", "my handle is sam@discord"),
            ("my handle is sam at example dot com", "my handle is sam@example.com"),
            ("the variable is user underscore id", "the variable is user_id"),
            ("Visit example dot com slash pricing.", "Visit example.com/pricing."),
            ("The site is example dot org slash docs slash intro.", "The site is example.org/docs/intro."),
            (
                "The url is https colon slash slash example dot com slash docs.",
                "The url is https://example.com/docs."
            ),
            ("The path is slash users slash sam slash notes.", "The path is /users/sam/notes."),
        ]
    )
    func writesSpokenAddresses(input: String, expected: String) {
        #expect(cleaned(input, by: sut) == expected)
    }

    @Test(
        "writes a label spoken with digits, an underscore, a hyphen or a plus tag",
        arguments: [
            ("email sam dot jones nine nine at example dot com", "email sam.jones99@example.com"),
            ("email sam dot jones 99 at example dot com", "email sam.jones99@example.com"),
            ("send it to team twenty one at example dot org", "send it to team21@example.org"),
            ("send it to sam underscore jones at example dot com", "send it to sam_jones@example.com"),
            ("email sam plus invoices at example dot com", "email sam+invoices@example.com"),
            ("email ops dash team at example dot com", "email ops-team@example.com"),
            ("email ops hyphen team at example dot net", "email ops-team@example.net"),
            ("email sam at my dash mail dot example dot com", "email sam@my-mail.example.com"),
            (
                "write to sam underscore lee two at mail dash box dot example dot org",
                "write to sam_lee2@mail-box.example.org"
            ),
            ("cc sam plus news underscore feed at example dot com", "cc sam+news_feed@example.com"),
            ("my handle is sam underscore jones at example dot com", "my handle is sam_jones@example.com"),
            ("email j dot doe two thousand at example dot com", "email j.doe2000@example.com"),
            (
                "forward it to build underscore bot at ci dash runner dot example dot net",
                "forward it to build_bot@ci-runner.example.net"
            ),
            (
                "contact help plus urgent at support dot example dot io",
                "contact help+urgent@support.example.io"
            ),
            ("email sam dot lee 2024 at example dot co dot uk", "email sam.lee2024@example.co.uk"),
        ]
    )
    func writesJoinedLabels(input: String, expected: String) {
        #expect(cleaned(input, by: sut) == expected)
    }

    @Test(
        "writes no address from prose that says a joiner or a number near at",
        arguments: [
            "plus the dash at the end",
            "the plus side at example dot com",
            "we met nine at example dot com",
            "it is plus two at the moment",
            "add a dash at the start",
            "she ran nine miles at dawn",
            "the score was five plus three at half time",
            "send the report at example dot com",
            "we met at nine at example dot com",
            "it went from plus to minus at the close",
            "type a dash at the prompt",
            "he scored twenty at the game",
        ]
    )
    func leavesJoinerProse(input: String) {
        #expect(!cleaned(input, by: sut).contains("@"))
    }

    @Test(
        "keeps ordinary dot and slash words",
        arguments: [
            "a dot on the map",
            "a slash in prices",
            "put a dot on the map",
            "the dot md files",
            "a dot json",
            "learn swift dot go",
            "type main dot swift",
            "there is a slash in prices",
        ]
    )
    func keepsOrdinaryWords(input: String) {
        #expect(cleaned(input, by: sut) == input)
    }

    /// Nothing is announced across a sentence end, so an address's words must all sit in one sentence.
    @Test(
        "leaves words that straddle a sentence end",
        arguments: [
            "send it. support at example.com",
            "write to info at example dot com. And billing at example dot net",
        ]
    )
    func leavesWordsAcrossASentenceEnd(input: String) {
        let cleaned = cleaned(input, by: sut)
        #expect(!cleaned.contains("support@") && !cleaned.contains("billing@"))
    }

    @Test("records the address on the first word and the rest as removed")
    func provenance() {
        let draft = sut.apply(Draft(text: "cc billing at example dot com"))
        #expect(draft.words[1].state == .replaced(by: SpokenPunctuationPass.id, from: "billing"))
        #expect(draft.words[2].state == .removed(by: SpokenPunctuationPass.id))
        #expect(draft.words[4].state == .removed(by: SpokenPunctuationPass.id))
        #expect(draft.text == "cc billing@example.com")
    }

    /// The pass converts rather than deletes, so the words it dropped are covered by its own grant.
    @Test("leaves the meaning guard nothing to answer for")
    func removalsAreAuthorised() {
        let draft = sut.apply(Draft(text: "cc billing at example dot com"))
        #expect(RemovalAudit.unauthorised(in: draft, grants: CleaningPipeline.standard.grants).isEmpty)
        #expect(
            MeaningPreservationGuard().verdict(draft: draft, rewritten: "Cc billing@example.com.")
                == .accepted)
    }

    @Test(
        "writes hosts, ports, paths and queries said with explicit separators",
        arguments: [
            ("cd slash users slash sam", "cd /users/sam"),
            ("the file is at slash etc slash hosts", "the file is at /etc/hosts"),
            ("connect to localhost colon eight thousand", "connect to localhost:8000"),
            ("connect to example dot com colon eight thousand", "connect to example.com:8000"),
            ("open localhost colon three thousand slash admin", "open localhost:3000/admin"),
            ("the server is at ten dot zero dot zero dot one", "the server is at 10.0.0.1"),
            ("ssh to ten dot zero dot zero dot one colon twenty two", "ssh to 10.0.0.1:22"),
            ("visit acme dash shop dot example dot com", "visit acme-shop.example.com"),
            (
                "open example dot com slash search question mark q equals cats",
                "open example.com/search?q=cats"
            ),
            (
                "open example dot com slash search question mark q equals cats and page equals two",
                "open example.com/search?q=cats&page=two"
            ),
            ("http colon slash slash ten dot zero dot zero dot one slash docs", "http://10.0.0.1/docs"),
        ]
    )
    func writesHostsAndPaths(input: String, expected: String) {
        #expect(cleaned(input, by: sut) == expected)
    }

    @Test(
        "writes a relative path or branch name that a file ending or a path word cues",
        arguments: [
            ("open src slash components slash button dot ts", "open src/components/button.ts"),
            (
                "copy dist slash bundle dot js to the release folder",
                "copy dist/bundle.js to the release folder"
            ),
            ("edit src slash app slash main dot swift", "edit src/app/main.swift"),
            ("look at docs slash setup dot md first", "look at docs/setup.md first"),
            (
                "the test lives in tests slash unit slash parser dot py",
                "the test lives in tests/unit/parser.py"
            ),
            ("open lib slash utils slash date underscore format dot ts", "open lib/utils/date_format.ts"),
            ("open scripts slash build dash app dot sh", "open scripts/build-app.sh"),
            ("open src slash main dot rs.", "open src/main.rs."),
            (
                "Open app slash models slash user dot rb, then run it.",
                "Open app/models/user.rb, then run it."
            ),
            ("the file is config slash settings dot yaml", "the file is config/settings.yaml"),
            ("check out the branch feature slash login dash page", "check out the branch feature/login-page"),
            ("create a branch fix slash crash dash on dash launch", "create a branch fix/crash-on-launch"),
            ("merge the branch release slash one dot two", "merge the branch release/1.2"),
            ("push the branch release slash v two dot zero", "push the branch release/v2.0"),
            ("switch to branch bugfix slash issue dash 42", "switch to branch bugfix/issue-42"),
            ("the branch is chore slash update underscore deps", "the branch is chore/update_deps"),
            ("rename the branch hotfix slash login", "rename the branch hotfix/login"),
            ("the folder is assets slash images", "the folder is assets/images"),
            ("put it in the directory build slash output", "put it in the directory build/output"),
            ("the path is src slash utils", "the path is src/utils"),
            ("the folder is public slash fonts slash inter", "the folder is public/fonts/inter"),
            ("open the file src slash index dot html", "open the file src/index.html"),
            ("delete the file tmp slash cache dot json", "delete the file tmp/cache.json"),
            ("the folder is docs slash api slash v one", "the folder is docs/api/v1"),
            ("save to the folder exports slash march", "save to the folder exports/march"),
            ("edit test slash helpers dot go", "edit test/helpers.go"),
            ("open packages slash core slash index dot ts", "open packages/core/index.ts"),
            ("the branch user slash sam slash spike", "the branch user/sam/spike"),
            ("open ios slash app slash info dot json", "open ios/app/info.json"),
            ("see web slash style dot css", "see web/style.css"),
        ]
    )
    func writesRelativePaths(input: String, expected: String) {
        #expect(cleaned(input, by: sut) == expected)
    }

    @Test(
        "leaves a slash in prose as words where nothing cues a path",
        arguments: [
            "and slash or", "w slash o", "input slash output", "he slash she", "read slash write access",
            "the client slash server model", "my friend slash roommate", "a pass slash fail grade",
            "the on slash off switch", "his singer slash songwriter career", "a yes slash no question",
            "the owner slash operator", "a love slash hate thing", "the buy slash sell button",
            "a writer slash director", "the start slash stop key", "lunch slash dinner tonight",
            "a part time slash full time role", "the kitchen slash dining room", "a cafe slash bar",
        ]
    )
    func leavesProseSlashes(input: String) {
        #expect(cleaned(input, by: sut) == input)
    }

    @Test(
        "writes a file reference's line and column joined to the file",
        arguments: [
            ("the error is in main dot py colon forty two colon seven", "the error is in main.py:42:7"),
            ("see main dot py colon forty", "see main.py:40"),
            ("open router dot swift colon one hundred eighteen", "open router.swift:118"),
            ("check app dot js colon twelve", "check app.js:12"),
            ("the warning is at config dot yaml colon three colon one", "the warning is at config.yaml:3:1"),
            ("look at index dot html colon two hundred", "look at index.html:200"),
            ("line utils dot rs colon one thousand two hundred five", "line utils.rs:1205"),
            ("parser dot ts colon nine colon fourteen fails", "parser.ts:9:14 fails"),
            ("notes dot md colon 7", "notes.md:7"),
            ("edit src slash app slash main dot swift colon forty two", "edit src/app/main.swift:42"),
            (
                "open tests slash unit slash parser dot py colon ten colon three",
                "open tests/unit/parser.py:10:3"
            ),
            ("dist slash bundle dot js colon one colon two hundred", "dist/bundle.js:1:200"),
            ("connect to localhost colon three thousand", "connect to localhost:3000"),
            ("ssh to ten dot zero dot zero dot one colon twenty two", "ssh to 10.0.0.1:22"),
            ("open example dot com colon eight thousand eighty", "open example.com:8080"),
            ("the file is main dot py colon forty two.", "the file is main.py:42."),
            ("data dot csv colon five colon six", "data.csv:5:6"),
            ("read schema dot json colon eighty eight", "read schema.json:88"),
            ("in build dot sh colon fifteen", "in build.sh:15"),
            ("go to readme dot txt colon one", "go to readme.txt:1"),
        ]
    )
    func writesFileReferences(input: String, expected: String) {
        #expect(cleaned(input, by: sut) == expected)
    }

    @Test(
        "leaves a colon that is not a reference to the clause rule",
        arguments: [
            "the ratio is three colon one", "the ratio is two colon one", "localhost is fine",
            "main dot py is long", "one dot two", "note colon the build failed", "at five colon thirty",
        ]
    )
    func leavesNonReferenceColons(input: String) {
        #expect(cleaned(input, by: sut).firstMatch(of: /\S:\d/) == nil)
    }

    @Test(
        "leaves ordinary slashes, dots and colons as words",
        arguments: [
            "and slash or", "he made a slash with his sword", "use a dot here", "the dot com bubble",
            "localhost is fine", "one dot two", "the ratio is two colon one", "a slash users slash sam",
        ]
    )
    func leavesOrdinaryWords(input: String) {
        #expect(cleaned(input, by: sut) == input)
    }

    /// A piece can end anywhere inside an address, so every reader stops at the piece's last word.
    @Test(
        "stops at a piece that ends mid address",
        arguments: [
            "go to www dot", "www dot", "connect to localhost colon", "the server is ten dot zero dot",
            "open example dot com slash search question mark", "open example dot com colon",
            "cd slash users slash", "q equals",
        ]
    )
    func stopsAtPieceEnd(input: String) {
        #expect(!cleaned(input, by: sut).isEmpty)
    }
}
