import Testing

@testable import UttrflowPredict

@Suite("Reading a situation off a window")
struct FieldSituationReadingTests {
    @Test("An editor's title says which branch is checked out.")
    func editorBranch() {
        let situation = FieldSituationReading.read(windowTitle: "main — myrepo")
        #expect(situation?.branch == "main")
        #expect(situation?.environment == nil)
    }

    @Test("A database client's title says which deployment and which database a tab is on.")
    func databaseTab() {
        let situation = FieldSituationReading.read(windowTitle: "prod@analytics — TablePlus")
        #expect(situation?.environment == .production)
        #expect(situation?.connection == "analytics")
    }

    @Test("The deployment may be written on either side of the connection.")
    func databaseTabReversed() {
        let situation = FieldSituationReading.read(windowTitle: "analytics@prod — TablePlus")
        #expect(situation?.environment == .production)
        #expect(situation?.connection == "analytics")
    }

    @Test("A deployment listed beside a database names that database.")
    func deploymentBesideDatabase() {
        let situation = FieldSituationReading.read(tabTitle: "qa · orders_db")
        #expect(situation?.environment == .quality)
        #expect(situation?.connection == "orders_db")
    }

    @Test("A database written before its deployment is found too.")
    func databaseBeforeDeployment() {
        let situation = FieldSituationReading.read(tabTitle: "orders_db · qa")
        #expect(situation?.environment == .quality)
        #expect(situation?.connection == "orders_db")
    }

    @Test("A shell sitting in a directory says nothing about the situation, only about the corpus.")
    func workingDirectoryIsNotASituation() {
        #expect(FieldSituationReading.read(windowTitle: "~/projects/foo — zsh") == nil)
    }

    @Test("A prompt that labels its branch is believed whatever the branch is called.")
    func labelledBranch() {
        let situation = FieldSituationReading.read(windowTitle: "➜  uttrflow git:(naveen/spike) ✗")
        #expect(situation?.branch == "naveen/spike")
    }

    @Test("A branch marked with the git glyph is read the same way.")
    func glyphBranch() {
        #expect(FieldSituationReading.read(tabTitle: "⎇ release/2026.09")?.branch == "release/2026.09")
        #expect(FieldSituationReading.read(tabTitle: "⎇")?.branch == nil)
    }

    @Test("A branch in brackets is read only when its own name says it is one.")
    func bracketedBranch() {
        #expect(FieldSituationReading.read(windowTitle: "myrepo [main]")?.branch == "main")
        #expect(FieldSituationReading.read(windowTitle: "myrepo (feat/tab)")?.branch == "feat/tab")
        #expect(FieldSituationReading.read(windowTitle: "Inbox (2481)") == nil)
    }

    @Test("The file in front of the user is read from the title that names it.")
    func openFile() {
        let situation = FieldSituationReading.read(
            windowTitle: "● Ranking.swift — uttrflow-swift", workingDirectory: "~/projects/uttrflow-swift")
        #expect(situation?.file == "ranking.swift")
        #expect(situation?.branch == nil)
    }

    @Test("The project's own folder name is never read as a branch or a file.")
    func projectNameIsDiscounted() {
        #expect(
            FieldSituationReading.read(
                windowTitle: "main — main", workingDirectory: "/Users/x/main") == nil)
    }

    @Test("A tab is nearer than its window, so it wins wherever the two disagree.")
    func tabBeatsWindow() {
        let situation = FieldSituationReading.read(
            windowTitle: "prod@analytics — TablePlus", tabTitle: "qa@analytics")
        #expect(situation?.environment == .quality)
        #expect(situation?.connection == "analytics")
    }

    @Test("What only the window says still counts when the tab is silent about it.")
    func windowFillsTheGaps() {
        let situation = FieldSituationReading.read(windowTitle: "main — myrepo", tabTitle: "qa · orders_db")
        #expect(situation?.branch == "main")
        #expect(situation?.environment == .quality)
    }

    @Test("A title nothing in it is recognisable returns nothing rather than a guess.")
    func unrecognisableTitles() {
        #expect(FieldSituationReading.read(windowTitle: "Untitled") == nil)
        #expect(FieldSituationReading.read(windowTitle: "Slack | general | Acme") == nil)
        #expect(FieldSituationReading.read(windowTitle: "") == nil)
        #expect(FieldSituationReading.read(windowTitle: "Inbox (2,481) - naveen@example.com - Gmail") == nil)
        #expect(FieldSituationReading.read(windowTitle: "staging.example.com/orders — Chrome") == nil)
        #expect(FieldSituationReading.read() == nil)
    }

    @Test("A user at a host is not a connection, however much it looks like one.")
    func userAtHostIsNotAConnection() {
        #expect(FieldSituationReading.read(windowTitle: "naveen@macbook: ~/projects/foo") == nil)
    }

    @Test("A deployment beside something capitalised names no database.")
    func applicationNamesAreNotDatabases() {
        let situation = FieldSituationReading.read(windowTitle: "prod — Chrome")
        #expect(situation?.environment == .production)
        #expect(situation?.connection == nil)
    }

    @Test("A title is cut on the punctuation applications list facts with.")
    func titlesAreCutOnPunctuation() {
        #expect(FieldSituationReading.segments(of: "a — b") == ["a", "b"])
        #expect(FieldSituationReading.segments(of: "a – b | c · d") == ["a", "b", "c", "d"])
        #expect(FieldSituationReading.segments(of: "a - b") == ["a", "b"])
        #expect(FieldSituationReading.segments(of: "host: ~/dir") == ["host", "~/dir"])
        #expect(FieldSituationReading.segments(of: "orders-db") == ["orders-db"])
        #expect(FieldSituationReading.segments(of: "git:(main)") == ["git:(main)"])
        #expect(FieldSituationReading.segments(of: "https://example.com") == ["https://example.com"])
    }

    @Test("Prompt decoration is stripped off a fact before it is read.")
    func decorationIsStripped() {
        #expect(FieldSituationReading.stripped("  ● main ✗ ") == "main")
        #expect(FieldSituationReading.stripped("\"main\"") == "main")
        #expect(FieldSituationReading.stripped("") == "")
    }

    @Test("Only a name that could be a git reference is considered as a branch.")
    func branchShapes() {
        #expect(FieldSituationReading.isBranchShaped("main"))
        #expect(FieldSituationReading.isBranchShaped("MASTER"))
        #expect(FieldSituationReading.isBranchShaped("feature/tab-complete"))
        #expect(!FieldSituationReading.isBranchShaped("orders_db"))
        #expect(!FieldSituationReading.isBranchShaped("naveen/spike"))
        #expect(!FieldSituationReading.isBranchShaped("~/projects/foo"))
        #expect(!FieldSituationReading.isBranchShaped("feat/a b"))
        #expect(!FieldSituationReading.isBranchShaped(""))
        #expect(!FieldSituationReading.isBranchShaped(String(repeating: "a", count: 81)))
    }

    @Test("A pair with no deployment on either side names nothing.")
    func pairsWithoutADeployment() {
        #expect(FieldSituationReading.environmentPair(in: "naveen@macbook") == nil)
        #expect(FieldSituationReading.environmentPair(in: "analytics") == nil)
        #expect(FieldSituationReading.environmentPair(in: "a@b@c") == nil)
        #expect(FieldSituationReading.environmentPair(in: "prod@TablePlus")?.1 == nil)
    }

    @Test("A database name is lowercase, long enough to be one, and not the tool printing it.")
    func databaseIdentifiers() {
        #expect(FieldSituationReading.databaseIdentifier(in: "orders_db") == "orders_db")
        #expect(FieldSituationReading.databaseIdentifier(in: "analytics-2") == "analytics-2")
        #expect(FieldSituationReading.databaseIdentifier(in: "a") == nil)
        #expect(FieldSituationReading.databaseIdentifier(in: "zsh") == nil)
        #expect(FieldSituationReading.databaseIdentifier(in: "prod") == nil)
        #expect(FieldSituationReading.databaseIdentifier(in: "TablePlus") == nil)
        #expect(FieldSituationReading.databaseIdentifier(in: "2orders") == nil)
        #expect(FieldSituationReading.databaseIdentifier(in: "orders db") == nil)
        #expect(FieldSituationReading.databaseIdentifier(in: String(repeating: "a", count: 65)) == nil)
    }

    @Test("A file is recognised by an extension this project knows, not by having a dot in it.")
    func fileNames() {
        #expect(FieldSituationReading.fileName(in: "Ranking.swift") == "Ranking.swift")
        #expect(FieldSituationReading.fileName(in: "schema.sql") == "schema.sql")
        #expect(FieldSituationReading.fileName(in: "example.com") == nil)
        #expect(FieldSituationReading.fileName(in: "Sources/App.swift") == nil)
        #expect(FieldSituationReading.fileName(in: "my app.swift") == nil)
        #expect(FieldSituationReading.fileName(in: "Makefile") == nil)
        #expect(FieldSituationReading.fileName(in: ".swift") == nil)
    }

    @Test("A marker with nothing after it encloses nothing.")
    func enclosureNeedsBothEnds() {
        #expect(FieldSituationReading.enclosed(in: "main", after: "(", before: ")") == nil)
        #expect(FieldSituationReading.enclosed(in: "(main", after: "(", before: ")") == nil)
        #expect(FieldSituationReading.enclosed(in: "()", after: "(", before: ")") == nil)
        #expect(FieldSituationReading.enclosed(in: "(main)", after: "(", before: ")") == "main")
    }

    @Test("A run of characters longer than what it is looked for in is never found.")
    func searchingForTooMuch() {
        #expect(FieldSituationReading.firstIndex(of: Array("abcd"), in: Array("abc")) == nil)
        #expect(FieldSituationReading.firstIndex(of: [], in: Array("abc")) == nil)
        #expect(FieldSituationReading.firstIndex(of: Array("bc"), in: Array("abc")) == 1)
        #expect(FieldSituationReading.firstIndex(of: Array("x"), in: Array("abc")) == nil)
    }

    @Test("A working directory names the project, and a path that names none says nothing.")
    func projectNames() {
        #expect(FieldSituationReading.projectName(of: "/Users/x/projects/Foo") == "foo")
        #expect(FieldSituationReading.projectName(of: "~/projects/foo/") == "foo")
        #expect(FieldSituationReading.projectName(of: "/") == nil)
        #expect(FieldSituationReading.projectName(of: nil) == nil)
    }
}
