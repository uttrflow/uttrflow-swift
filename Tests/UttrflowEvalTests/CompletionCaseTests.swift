import Testing

@testable import UttrflowEval

/// How a full line becomes the cases a completion harness runs, decided without a model or a situation.
@Suite("Completion cases from cut lines")
struct CompletionCaseTests {
    let line = "git checkout main"

    @Test("A cut after a word keeps the space; into a word keeps that many characters; halfway rounds down.")
    func cutsFall() {
        #expect(LineCut.afterWord(1).typed(of: line) == "git ")
        #expect(LineCut.afterWord(2).typed(of: line) == "git checkout ")
        #expect(LineCut.afterWord(3).typed(of: line) == nil)
        #expect(LineCut.intoWord(2, by: 1).typed(of: line) == "git c")
        #expect(LineCut.intoWord(2, by: 8).typed(of: line) == nil)
        #expect(LineCut.midWord(2).typed(of: line) == "git chec")
        #expect(LineCut.midWord(3).typed(of: line) == "git checkout ma")
        #expect(LineCut.midWord(1).typed(of: "a b") == nil)
        #expect(LineCut.characters(3).typed(of: line) == "git")
        #expect(LineCut.characters(17).typed(of: line) == nil)
        #expect(LineCut.whole.typed(of: line) == line)
        #expect(LineCut.afterWord(0).typed(of: line) == nil)
    }

    @Test("Words are runs of non-space characters, so double spaces and leading indentation do not make words.")
    func wordsSkipSpaces() {
        #expect(LineCut.words(in: Array("  return  a")) == [2..<8, 10..<11])
        #expect(LineCut.afterWord(1).typed(of: "git  status") == "git ")
        #expect(LineCut.words(in: []).isEmpty)
    }

    @Test("A segment cut inside a word determines the rest of that word and of every sibling sharing the prefix.")
    func segmentAcceptable() {
        let siblings = ["git commit -m 'fix'", "git clone", "svn checkout"]
        let got = CompletionExpectation.acceptable(
            for: line, typed: "git c", determinacy: .word, among: siblings)
        #expect(got == ["heckout", "ommit", "lone"])
        let none = CompletionExpectation.acceptable(
            for: line, typed: "git ", determinacy: .word, among: siblings)
        #expect(none.isEmpty)
        let path = CompletionExpectation.acceptable(
            for: "cd ~/projects/web", typed: "cd ~/pr", determinacy: .segment(until: [" ", "/"]), among: [])
        #expect(path == ["ojects"])
        let boundary = CompletionExpectation.acceptable(
            for: "localhost:3000/dashboard", typed: "localhost:3000", determinacy: .segment(until: ["/"]),
            among: [])
        #expect(boundary.isEmpty)
    }

    @Test("Whole-line, any and nothing say the rest, anything, and silence respectively.")
    func otherDeterminacies() {
        #expect(
            CompletionExpectation.acceptable(for: line, typed: "git", determinacy: .line, among: ["git", "gi"])
                == [" checkout main"])
        #expect(CompletionExpectation.acceptable(for: line, typed: "git", determinacy: .any, among: []).isEmpty)
        #expect(
            CompletionExpectation.acceptable(for: line, typed: line, determinacy: .nothing, among: [])
                == [CompletionExpectation.nothing])
    }

    @Test("A hit is any completion whose continuation opens with an acceptable, or any at all when none is named.")
    func hits() {
        let named = CompletionExpectation(acceptable: ["heckout", "ommit"], band: 1...40)
        #expect(named.hits(["git Commit -m", "git clone"], typed: "git c"))
        #expect(!named.hits(["git clone"], typed: "git c"))
        let open = CompletionExpectation(band: 1...40)
        #expect(open.hits(["git clone"], typed: "git c"))
        #expect(!open.hits([], typed: "git c"))
    }

    @Test("Expecting nothing is hit and in register only by silence.")
    func nothing() {
        let silent = CompletionExpectation(acceptable: [CompletionExpectation.nothing], band: 1...40)
        #expect(silent.expectsNothing)
        #expect(silent.hits([], typed: "ls -la"))
        #expect(silent.conforms([], typed: "ls -la"))
        #expect(!silent.hits(["ls -la | head"], typed: "ls -la"))
        #expect(!silent.conforms(["ls -la | head"], typed: "ls -la"))
        #expect(!CompletionExpectation(band: 1...40).expectsNothing)
    }

    @Test("The first completion conforms when its length sits in the band and it echoes nothing forbidden.")
    func conforms() {
        let expectation = CompletionExpectation(band: 2...10, forbidden: ["Priya:"])
        #expect(expectation.conforms(["on my way"], typed: "on m"))
        #expect(!expectation.conforms(["on my way, Priya: yes"], typed: "on m"))
        #expect(!expectation.conforms(["on my way and I will be there"], typed: "on m"))
        #expect(!expectation.conforms(["on my"], typed: "on m"))
        #expect(!expectation.conforms([], typed: "on m"))
    }

    @Test("A band fits twice the longest line and never falls below its floor.")
    func band() {
        #expect(CompletionExpectation.band(fitting: ["yes", "on my way"]) == 1...20)
        #expect(CompletionExpectation.band(fitting: ["I will send the numbers after lunch."]) == 1...72)
        #expect(CompletionExpectation.band(fitting: [], atLeast: 8) == 1...8)
    }

    @Test("A slug is the first words in letters and digits, hyphenated, or a placeholder for a line without any.")
    func slugs() {
        #expect(CutLine.slug(of: "SELECT * FROM users WHERE id = 42;") == "select-from-users")
        #expect(CutLine.slug(of: "haha yes 😂") == "haha-yes")
        #expect(CutLine.slug(of: "🔥🔥") == "line")
        #expect(CutLine.slug(of: "on my way", words: 2) == "on-my")
    }

    @Test("Cases are distinct cuts that leave enough typed and something to write, named by their typed length.")
    func casesFromCuts() {
        let cut = CutLine(
            "ls -la", cuts: [.afterWord(1), .intoWord(2, by: 1), .midWord(2), .afterWord(2), .midWord(1)],
            determinacy: .word)
        let register = CutRegister(band: 1...12, forbidden: ["$ "], siblings: ["ls -l", "ls -lh"])
        let cases = cut.cases(in: register)
        #expect(cases.map(\.name) == ["ls-la/cut3", "ls-la/cut4"])
        #expect(cases.map(\.typed) == ["ls ", "ls -"])
        #expect(cases[0].expectation.acceptable.isEmpty)
        #expect(cases[1].expectation.acceptable == ["la", "l", "lh"])
        #expect(cases[1].expectation.lengthBand == 1...12)
        #expect(cases[1].expectation.forbidden == ["$ "])
    }

    @Test("A line expecting nothing keeps its whole and one-character cuts, which any other line drops.")
    func nothingKeepsShortCuts() {
        let register = CutRegister(band: 1...40)
        let silent = CutLine("git status", cuts: [.whole, .characters(1)], determinacy: .nothing)
        #expect(silent.cases(in: register).map(\.typed) == ["git status", "g"])
        #expect(silent.cases(in: register).allSatisfy { $0.expectation.expectsNothing })
        let spoken = CutLine("git status", cuts: [.whole, .characters(1), .characters(2)], determinacy: .any)
        #expect(spoken.cases(in: register).map(\.typed) == ["gi"])
        #expect(CutLine("  ok", cuts: [.characters(2)], determinacy: .any).cases(in: register).isEmpty)
        #expect(CutLine("x y", slug: "xy", cuts: [.afterWord(1)], determinacy: .any).cases(in: register).isEmpty)
    }

    @Test("A thread's speaker labels are each named once, and only long messages leave a snippet.")
    func threads() {
        let thread = """
            Priya: where did the notarisation log go?
            Me: in dist/, one sec
            Priya: found it, thanks!
            Neha (PM): Standup moved to 10:30 tomorrow, please confirm.
            a bare line with no speaker
            """
        #expect(ScreenThread.labels(in: thread) == ["Priya:", "Me:", "Neha (PM):"])
        #expect(
            ScreenThread.snippets(in: thread) == [
                "where did the notarisati", "Standup moved to 10:30 t", "a bare line with no spea",
            ])
        #expect(ScreenThread.snippets(in: thread, atLeast: 40) == ["Standup moved to 10:30 tomorrow, please "])
        #expect(ScreenThread.labels(in: "\n  \n").isEmpty)
    }
}
