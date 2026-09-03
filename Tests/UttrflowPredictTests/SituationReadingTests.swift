import Testing

@testable import UttrflowPredict

@Suite("Reading a situation off a window")
struct SituationReadingTests {
    @Test("An editor's title says which branch is checked out.")
    func editorBranch() {
        let situation = SituationReading.read(windowTitle: "main — myrepo")
        #expect(situation?.branch == "main")
        #expect(situation?.environment == nil)
    }

    @Test("A database client's title says which deployment and which database a tab is on.")
    func databaseTab() {
        let situation = SituationReading.read(windowTitle: "prod@analytics — TablePlus")
        #expect(situation?.environment == .production)
        #expect(situation?.connection == "analytics")
    }

    @Test("The deployment may be written on either side of the connection.")
    func databaseTabReversed() {
        let situation = SituationReading.read(windowTitle: "analytics@prod — TablePlus")
        #expect(situation?.environment == .production)
        #expect(situation?.connection == "analytics")
    }

    @Test("A deployment listed beside a database names that database.")
    func deploymentBesideDatabase() {
        let situation = SituationReading.read(tabTitle: "qa · orders_db")
        #expect(situation?.environment == .quality)
        #expect(situation?.connection == "orders_db")
    }

    @Test("A database written before its deployment is found too.")
    func databaseBeforeDeployment() {
        let situation = SituationReading.read(tabTitle: "orders_db · qa")
        #expect(situation?.environment == .quality)
        #expect(situation?.connection == "orders_db")
    }

    @Test("A shell sitting in a directory says nothing about the situation, only about the corpus.")
    func workingDirectoryIsNotASituation() {
        #expect(SituationReading.read(windowTitle: "~/projects/foo — zsh") == nil)
    }

    @Test("A prompt that labels its branch is believed whatever the branch is called.")
    func labelledBranch() {
        let situation = SituationReading.read(windowTitle: "➜  uttrflow git:(naveen/spike) ✗")
        #expect(situation?.branch == "naveen/spike")
    }

    @Test("A branch marked with the git glyph is read the same way.")
    func glyphBranch() {
        #expect(SituationReading.read(tabTitle: "⎇ release/2026.09")?.branch == "release/2026.09")
        #expect(SituationReading.read(tabTitle: "⎇")?.branch == nil)
    }

    @Test("A branch in brackets is read only when its own name says it is one.")
    func bracketedBranch() {
        #expect(SituationReading.read(windowTitle: "myrepo [main]")?.branch == "main")
        #expect(SituationReading.read(windowTitle: "myrepo (feat/tab)")?.branch == "feat/tab")
        #expect(SituationReading.read(windowTitle: "Inbox (2481)") == nil)
    }

    @Test("The file in front of the user is read from the title that names it.")
    func openFile() {
        let situation = SituationReading.read(
            windowTitle: "● Ranking.swift — uttrflow-swift", workingDirectory: "~/projects/uttrflow-swift")
        #expect(situation?.file == "ranking.swift")
        #expect(situation?.branch == nil)
    }

    @Test("The project's own folder name is never read as a branch or a file.")
    func projectNameIsDiscounted() {
        #expect(SituationReading.read(windowTitle: "main — main", workingDirectory: "/Users/x/main") == nil)
    }

    @Test("A tab is nearer than its window, so it wins wherever the two disagree.")
    func tabBeatsWindow() {
        let situation = SituationReading.read(
            windowTitle: "prod@analytics — TablePlus", tabTitle: "qa@analytics")
        #expect(situation?.environment == .quality)
        #expect(situation?.connection == "analytics")
    }

    @Test("What only the window says still counts when the tab is silent about it.")
    func windowFillsTheGaps() {
        let situation = SituationReading.read(windowTitle: "main — myrepo", tabTitle: "qa · orders_db")
        #expect(situation?.branch == "main")
        #expect(situation?.environment == .quality)
    }

    @Test("A title nothing in it is recognisable returns nothing rather than a guess.")
    func unrecognisableTitles() {
        #expect(SituationReading.read(windowTitle: "Untitled") == nil)
        #expect(SituationReading.read(windowTitle: "Slack | general | Acme") == nil)
        #expect(SituationReading.read(windowTitle: "") == nil)
        #expect(SituationReading.read(windowTitle: "Inbox (2,481) - naveen@example.com - Gmail") == nil)
        #expect(SituationReading.read(windowTitle: "staging.example.com/orders — Chrome") == nil)
        #expect(SituationReading.read() == nil)
    }

    @Test("A user at a host is not a connection, however much it looks like one.")
    func userAtHostIsNotAConnection() {
        #expect(SituationReading.read(windowTitle: "naveen@macbook: ~/projects/foo") == nil)
    }

    @Test("A deployment beside something capitalised names no database.")
    func applicationNamesAreNotDatabases() {
        let situation = SituationReading.read(windowTitle: "prod — Chrome")
        #expect(situation?.environment == .production)
        #expect(situation?.connection == nil)
    }

    @Test("A title is cut on the punctuation applications list facts with.")
    func titlesAreCutOnPunctuation() {
        #expect(SituationReading.segments(of: "a — b") == ["a", "b"])
        #expect(SituationReading.segments(of: "a – b | c · d") == ["a", "b", "c", "d"])
        #expect(SituationReading.segments(of: "a - b") == ["a", "b"])
        #expect(SituationReading.segments(of: "host: ~/dir") == ["host", "~/dir"])
        #expect(SituationReading.segments(of: "orders-db") == ["orders-db"])
        #expect(SituationReading.segments(of: "git:(main)") == ["git:(main)"])
        #expect(SituationReading.segments(of: "https://example.com") == ["https://example.com"])
    }

    @Test("Prompt decoration is stripped off a fact before it is read.")
    func decorationIsStripped() {
        #expect(SituationReading.stripped("  ● main ✗ ") == "main")
        #expect(SituationReading.stripped("\"main\"") == "main")
        #expect(SituationReading.stripped("") == "")
    }

    @Test("Only a name that could be a git reference is considered as a branch.")
    func branchShapes() {
        #expect(SituationReading.isBranchShaped("main"))
        #expect(SituationReading.isBranchShaped("MASTER"))
        #expect(SituationReading.isBranchShaped("feature/tab-complete"))
        #expect(!SituationReading.isBranchShaped("orders_db"))
        #expect(!SituationReading.isBranchShaped("naveen/spike"))
        #expect(!SituationReading.isBranchShaped("~/projects/foo"))
        #expect(!SituationReading.isBranchShaped("feat/a b"))
        #expect(!SituationReading.isBranchShaped(""))
        #expect(!SituationReading.isBranchShaped(String(repeating: "a", count: 81)))
    }

    @Test("A pair with no deployment on either side names nothing.")
    func pairsWithoutADeployment() {
        #expect(SituationReading.environmentPair(in: "naveen@macbook") == nil)
        #expect(SituationReading.environmentPair(in: "analytics") == nil)
        #expect(SituationReading.environmentPair(in: "a@b@c") == nil)
        #expect(SituationReading.environmentPair(in: "prod@TablePlus")?.1 == nil)
    }

    @Test("A database name is lowercase, long enough to be one, and not the tool printing it.")
    func databaseIdentifiers() {
        #expect(SituationReading.databaseIdentifier(in: "orders_db") == "orders_db")
        #expect(SituationReading.databaseIdentifier(in: "analytics-2") == "analytics-2")
        #expect(SituationReading.databaseIdentifier(in: "a") == nil)
        #expect(SituationReading.databaseIdentifier(in: "zsh") == nil)
        #expect(SituationReading.databaseIdentifier(in: "prod") == nil)
        #expect(SituationReading.databaseIdentifier(in: "TablePlus") == nil)
        #expect(SituationReading.databaseIdentifier(in: "2orders") == nil)
        #expect(SituationReading.databaseIdentifier(in: "orders db") == nil)
        #expect(SituationReading.databaseIdentifier(in: String(repeating: "a", count: 65)) == nil)
    }

    @Test("A file is recognised by an extension this project knows, not by having a dot in it.")
    func fileNames() {
        #expect(SituationReading.fileName(in: "Ranking.swift") == "Ranking.swift")
        #expect(SituationReading.fileName(in: "schema.sql") == "schema.sql")
        #expect(SituationReading.fileName(in: "example.com") == nil)
        #expect(SituationReading.fileName(in: "Sources/App.swift") == nil)
        #expect(SituationReading.fileName(in: "my app.swift") == nil)
        #expect(SituationReading.fileName(in: "Makefile") == nil)
        #expect(SituationReading.fileName(in: ".swift") == nil)
    }

    @Test("A marker with nothing after it encloses nothing.")
    func enclosureNeedsBothEnds() {
        #expect(SituationReading.enclosed(in: "main", after: "(", before: ")") == nil)
        #expect(SituationReading.enclosed(in: "(main", after: "(", before: ")") == nil)
        #expect(SituationReading.enclosed(in: "()", after: "(", before: ")") == nil)
        #expect(SituationReading.enclosed(in: "(main)", after: "(", before: ")") == "main")
    }

    @Test("A run of characters longer than what it is looked for in is never found.")
    func searchingForTooMuch() {
        #expect(SituationReading.firstIndex(of: Array("abcd"), in: Array("abc")) == nil)
        #expect(SituationReading.firstIndex(of: [], in: Array("abc")) == nil)
        #expect(SituationReading.firstIndex(of: Array("bc"), in: Array("abc")) == 1)
        #expect(SituationReading.firstIndex(of: Array("x"), in: Array("abc")) == nil)
    }

    @Test("A working directory names the project, and a path that names none says nothing.")
    func projectNames() {
        #expect(SituationReading.projectName(of: "/Users/x/projects/Foo") == "foo")
        #expect(SituationReading.projectName(of: "~/projects/foo/") == "foo")
        #expect(SituationReading.projectName(of: "/") == nil)
        #expect(SituationReading.projectName(of: nil) == nil)
    }
}
