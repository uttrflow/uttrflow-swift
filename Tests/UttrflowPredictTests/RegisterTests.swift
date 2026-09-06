import Testing

@testable import UttrflowPredict

/// Situations named by what is on screen and what the person wrote, never by an application.
private let thread = """
    Priya: where did the notarisation log go?
    Me: in dist/, one sec
    Priya: found it, thanks!
    Priya: are you coming tonight?
    """

private let friendChat = GenerationSituation(
    application: "Chat", surroundings: thread, recentLines: ["on my way", "running late, sorry", "yes!"],
    isMultiline: true)

private let shell = GenerationSituation(
    application: "Terminal", preceding: "$ git status\n$ ls -la",
    recentLines: ["git commit -m 'fix'", "ls -la", "docker compose up -d"])

private let essay = GenerationSituation(
    application: "Editor",
    surroundings: String(repeating: "A long paragraph of prose that runs on. ", count: 8),
    recentLines: [
        "The release goes out on Thursday.", "We should measure before we optimise.",
        "Nobody reads the second paragraph.",
    ],
    isMultiline: true)

/// A register built by hand, so a test about the budget names only the fact it varies.
private func register(length: Int?, conversational: Bool = false, symbols: Double = 0) -> Register {
    Register(
        isMultiline: true, typicalLength: length, isConversational: conversational, symbolShare: symbols,
        usesSentenceCase: nil)
}

@Suite("Reading the register off the moment")
struct RegisterTests {
    @Test(
        "Short turns on screen read as a conversation, and the person's own short casual lines set the length."
    )
    func aChatIsConversationalAndShort() {
        let register = Register.infer(from: friendChat, typed: "on m")
        #expect(register.isConversational)
        #expect(register.typicalLength == 9)
        #expect(register.usesSentenceCase == false)
        #expect(register.symbolShare < Register.symbolicShare)
        // A terse person still gets a whole reply's budget, and their terseness is not quoted as the length to write.
        #expect(register.maxTokens == Register.replyTokens)
        #expect(!register.hints.contains { $0.hasPrefix("lines here run about") })
        #expect(register.hints.contains("a conversation is on screen and the line answers its last message"))
        #expect(register.hints.contains("this person writes casually, without sentence punctuation"))
    }

    @Test("Commands are mostly symbols, one line at a time, and get a short token budget.")
    func commandsAreSymbolicAndShort() {
        let register = Register.infer(from: shell, typed: "git c")
        #expect(!register.isMultiline)
        #expect(!register.isConversational)
        #expect(register.symbolShare > Register.symbolicShare)
        #expect(register.typicalLength == 19)
        #expect(register.maxTokens == Register.tokenRange.lowerBound)
        #expect(register.hints.contains("the text here is commands, code or queries rather than prose"))
        #expect(register.hints.first == "a single-line field")
        #expect(!register.hints.contains { $0.hasPrefix("this person writes") })
    }

    @Test("Full sentences in a document read as formal prose.")
    func proseIsFormal() {
        let register = Register.infer(from: essay, typed: "We")
        #expect(register.isMultiline)
        #expect(!register.isConversational)
        #expect(register.usesSentenceCase == true)
        #expect(register.symbolShare < Register.symbolicShare)
        #expect(register.typicalLength == 34)
        #expect(register.hints.contains("this person writes in full sentences with punctuation"))
    }

    @Test(
        "With nothing of the person's own, the screen sets the length in a conversation and nothing does otherwise."
    )
    func theScreenStandsInForTheirLines() {
        let unseen = GenerationSituation(application: "Chat", surroundings: thread, isMultiline: true)
        let register = Register.infer(from: unseen, typed: "on m")
        #expect(register.typicalLength == 30)
        #expect(register.usesSentenceCase == nil)
        #expect(!register.hints.contains { $0.hasPrefix("this person writes") })
        let bare = Register.infer(from: GenerationSituation(application: "Anything"), typed: "he")
        #expect(bare.typicalLength == nil)
        #expect(bare.maxTokens == 64)
    }

    @Test("Lines shaped like web addresses read as an address bar, so a bare word is not a command.")
    func addressesAreNotCommands() {
        let addressBar = GenerationSituation(
            application: "Browser", field: "Address and search bar",
            recentLines: ["github.com/example/app", "linear.app/example/team", "news.ycombinator.com"])
        let register = Register.infer(from: addressBar, typed: "git")
        #expect(register.writesAddresses)
        #expect(
            register.hints.contains(
                "the lines here are web addresses, so the line continues into a host and path"))
        #expect(!register.hints.contains("the text here is commands, code or queries rather than prose"))
        #expect(!Register.infer(from: shell, typed: "git c").writesAddresses)
        // With no lines of the person's own, the field's own name is the evidence, in the words browsers publish.
        let bare = GenerationSituation(application: "Browser", field: "Search or enter website name")
        #expect(Register.infer(from: bare, typed: "git").writesAddresses)
        // The same combined field with the person's queries in it is a search field, whatever it is called.
        let searched = GenerationSituation(
            application: "Browser", field: "Search or enter website name",
            recentLines: ["swift actors tutorial", "weather tomorrow", "flights to goa december"])
        #expect(!Register.infer(from: searched, typed: "bookcase ").writesAddresses)
        #expect(Register.namesAddressField("Address and search bar"))
        #expect(Register.namesAddressField("Search or enter address"))
        #expect(Register.namesAddressField("URL"))
        #expect(!Register.namesAddressField("Address line 1"))
        #expect(!Register.namesAddressField("Email address"))
        #expect(!Register.namesAddressField(nil))
        #expect(Register.looksLikeAddress("docs.python.org/3/library"))
        #expect(!Register.looksLikeAddress("git commit -m 'fix'"))
        #expect(!Register.looksLikeAddress(".hidden"))
        #expect(!Register.looksLikeAddress("v1.2"))
        #expect(Register.addressShare(of: []) == 0)
    }

    @Test(
        "The kind names the line for the instruction beside it: an address, a command, a reply, or just a line."
    )
    func theKindNamesTheLine() {
        #expect(Register.infer(from: friendChat, typed: "on m").kind == "reply")
        #expect(Register.infer(from: shell, typed: "git c").kind == "command, query or line of code")
        #expect(Register.infer(from: essay, typed: "We").kind == "line")
        let addressBar = GenerationSituation(application: "Browser", field: "Address and search bar")
        #expect(Register.infer(from: addressBar, typed: "git").kind.hasPrefix("web address, a host and path"))
    }

    @Test("The token budget is half the typical length, held between the shortest and longest pass allowed.")
    func theBudgetFollowsTheLength() {
        #expect(register(length: 10).maxTokens == 24)
        #expect(register(length: 100).maxTokens == 50)
        #expect(register(length: 400).maxTokens == 96)
        #expect(register(length: nil, symbols: 0.4).maxTokens == 32)
        #expect(register(length: nil, conversational: true).maxTokens == 48)
    }

    @Test("Two lines are not a conversation, and long lines are a document however many there are.")
    func conversationsNeedShortTurns() {
        #expect(!Register.isConversation(["hi", "hello"]))
        #expect(Register.isConversation(["hi", "hello", "how are you?"]))
        let paragraphs = Array(repeating: String(repeating: "word ", count: 60), count: 5)
        #expect(!Register.isConversation(paragraphs))
        #expect(Register.lines(of: "a\n\n  \nb").count == 2)
        #expect(Register.median([]) == nil)
        #expect(Register.median([3, 1, 2]) == 2)
        #expect(Register.symbolShare(of: []) == 0)
        #expect(Register.sentenceCaseShare(of: []) == 0)
    }
}

@Suite("Fields whose answer lives in a history or nowhere")
struct HistoryOnlyRegisterTests {
    /// The register a field of this name infers, with nothing else on screen to go by.
    private func register(field: String?) -> Register {
        Register.infer(from: GenerationSituation(application: "App", field: field), typed: "ni")
    }

    @Test(
        "A box that calls itself a search, a find, a filter or a query answers from what was entered before.")
    func searchBoxesNameThemselves() {
        for name in ["Search", "Search products", "Find in page", "Search this Mac"] {
            #expect(register(field: name).answersFromHistoryAlone, "\(name)")
        }
    }

    @Test(
        "A message box, a document body and a nameless field are not searches, so the model still answers there."
    )
    func ordinaryFieldsStillAnswer() {
        // An editor calls its own field a query or a filter, and what it holds is grounded by the schema on screen.
        for name in ["Type a message", "Note Body Text View", "Subject", "Query", "Filter", nil] {
            #expect(!register(field: name).answersFromHistoryAlone, "\(name ?? "nil")")
        }
    }

    @Test("An address bar answers from history too, whether it names addresses or the person writes them.")
    func addressBarsAnswerFromHistory() {
        #expect(register(field: "Address and search bar").answersFromHistoryAlone)
        let ownAddresses = Register.infer(
            from: GenerationSituation(
                application: "Browser", field: "Location",
                recentLines: ["github.com/uttrflow", "linear.app/team", "example.com/docs"]),
            typed: "git")
        #expect(ownAddresses.answersFromHistoryAlone)
    }
}
