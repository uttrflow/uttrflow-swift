import Testing
import UttrflowCore

@testable import UttrflowAI

@Suite("Screen candidates: readings the window is already showing")
struct ScreenCandidatesTests {
    private let source = ScreenCandidates()
    private let word = Draft.Word("payment sheet", confidence: 0.3)

    @Test("reads the window title, the selection and the text either side of the caret")
    func readsEveryField() {
        let words = ScreenCandidates.words(
            on: .showing(
                title: "PaymentSheet.swift", selection: "fetchInvoices()", preceding: "call the ",
                following: " before"))
        #expect(words == ["PaymentSheet", "swift", "fetchInvoices", "call", "the", "before"])
    }

    @Test("drops a key shown beside the caret and keeps the prose around it")
    func dropsASecretShapedRun() {
        let words = ScreenCandidates.words(
            on: .showing(
                title: "credentials", selection: nil, preceding: "export key ASIAY34FZKBOKMUTVV7A then ",
                following: " later"))
        #expect(words == ["credentials", "export", "key", "then", "later"])
    }

    @Test("offers the identifier that spells a spoken run with its spaces closed up")
    func matchesAnIdentifier() async {
        let found = await source.candidates(for: word, in: .showing(title: "PaymentSheet.swift — Uttrflow"))
        #expect(found == ["PaymentSheet"])
    }

    @Test("offers a screen word that sounds like the doubtful one")
    func matchesBySound() async {
        let found = await source.candidates(
            for: Draft.Word("cash", confidence: 0.3), in: .showing(title: "Cache.swift"))
        #expect(found == ["Cache"])
    }

    @Test("offers an accented Latin name shown on screen for its plain spelling")
    func matchesAccentedName() async {
        let found = await source.candidates(
            for: Draft.Word("Muller", confidence: 0.3), in: .showing(title: "Müller"))
        #expect(found == ["Müller"])
    }

    @Test("offers nothing when the window shows nothing that sounds or spells alike")
    func offersNothing() async {
        #expect(await source.candidates(for: word, in: .showing(title: "#ios-bugs")).isEmpty)
    }

    @Test("offers nothing at all when the screen said nothing")
    func offersNothingWithoutAScreen() async {
        #expect(await source.candidates(for: word, in: .unknown).isEmpty)
    }

    @Test("passes over a word too short to be a spelling")
    func ignoresShortWords() {
        #expect(!ScreenCandidates.words(on: .showing(title: "a of Cache")).contains("of"))
    }

    @Test("offers a repeated screen word once")
    func offersEachWordOnce() {
        #expect(ScreenCandidates.words(on: .showing(title: "Cache Cache cache")) == ["Cache"])
    }

    @Test("stops reading after the words the screen is allowed to spend")
    func capsTheScreen() {
        let long = String(repeating: "wxyz ", count: ScreenCandidates.maximumWordsOnScreen + 50)
        #expect(ScreenCandidates.words(on: .showing(selection: long)).count == 1)
        let many = (1...(ScreenCandidates.maximumWordsOnScreen + 50)).map { "word\($0)" }
            .joined(separator: " ")
        #expect(
            ScreenCandidates.words(on: .showing(selection: many)).count
                == ScreenCandidates.maximumWordsOnScreen)
    }

    @Test("refuses an ordinary screen word that merely collides on sound and opens differently")
    func refusesAnOrdinaryCollision() async {
        let made = await source.candidates(
            for: Draft.Word("made", confidence: 0.42),
            in: .showing(title: "parser.rs", preceding: "pub mod parser;\nlet x = "))
        #expect(!made.contains("mod"))
        let but = await source.candidates(
            for: Draft.Word("but", confidence: 0.42), in: .showing(title: "bot.py"))
        #expect(!but.contains("bot"))
        let mean = await source.candidates(
            for: Draft.Word("mean", confidence: 0.42), in: .showing(title: "main.go"))
        #expect(!mean.contains("main"))
    }

    @Test("refuses what the dictionary's own sound source would refuse for the same word")
    func refusesWhatTheSiblingRefuses() async {
        let screen = await source.candidates(
            for: Draft.Word("made", confidence: 0.42),
            in: .showing(title: "parser.rs", preceding: "pub mod parser;"))
        let phonetic = await PhoneticCandidates().candidates(
            for: Draft.Word("made", confidence: 0.42), in: .showing(title: "parser.rs"))
        #expect(screen.isEmpty && phonetic.isEmpty)
    }

    @Test("offers no span at all for a sentence whose only match is such a collision")
    func offersNoSpanForACollision() async {
        let spans = await DoubtfulWords.standard.spans(
            in: .heard("i ?made a change to the parser", unsure: 0.42),
            for: .showing(title: "parser.rs", preceding: "pub mod parser;\nlet x = "))
        let everyCandidate = spans.flatMap(\.candidates).map(\.spelling)
        #expect(
            !everyCandidate.contains("mod"),
            "screen collision 'mod' must not reach the prompt, got \(everyCandidate)")
    }

    @Test("still offers a screen word that sounds alike and opens alike")
    func keepsAReadingThatOpensAlike() async {
        let found = await source.candidates(
            for: Draft.Word("cash", confidence: 0.42), in: .showing(title: "Cache.swift"))
        #expect(found == ["Cache"])
    }

    @Test("still offers a spelling with the spaces closed up, whatever it opens with")
    func keepsAClosedUpSpelling() async {
        let sheet = await source.candidates(
            for: word, in: .showing(title: "PaymentSheet.swift — Uttrflow"))
        #expect(sheet == ["PaymentSheet"])
        let mount = await source.candidates(
            for: Draft.Word("a mount", confidence: 0.42), in: .showing(title: "amount owing"))
        #expect(mount == ["amount"])
    }

    // MARK: - One reading of the screen per piece

    /// The batch answer is the source's real answer now, so the two must not be allowed to drift apart.
    @Test("answers a whole piece exactly as it answers each run on its own")
    func batchAgreesWithSingleRuns() async {
        let situation = Situation.showing(
            title: "PaymentSheet.swift \u{2014} Uttrflow", preceding: "let cache = Cache(")
        let runs = [
            Draft.Word("payment sheet", confidence: 0.42), Draft.Word("cash", confidence: 0.42),
            Draft.Word("nothing like it", confidence: 0.42),
        ]

        let together = await source.candidates(for: runs, in: situation)
        var separately: [[Reading]] = []
        for run in runs { separately.append(await source.candidates(for: run, in: situation)) }

        #expect(together == separately)
    }

    /// A source that derives nothing from the screen keeps answering one run at a time, through the default.
    @Test("gives every run an answer, in the order the runs were asked")
    func answersEveryRunInOrder() async {
        let runs = [
            Draft.Word("payment sheet", confidence: 0.42), Draft.Word("cash", confidence: 0.42),
        ]

        let found = await source.candidates(
            for: runs, in: .showing(title: "PaymentSheet.swift", preceding: "let cache = Cache("))

        #expect(found.count == runs.count)
        #expect(found.first == ["PaymentSheet"])
    }
}
