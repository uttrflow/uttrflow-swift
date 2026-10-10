import Testing
import UttrflowCore

@testable import UttrflowPredict

/// Situations named by what is on screen and what the person wrote, never by an application.
private let thread = """
    Priya: where did the notarisation log go?
    Me: in dist/, one sec
    Priya: found it, thanks!
    Priya: are you coming tonight?
    """

/// A chat: short turns on screen, and the person's own lines short and casual.
private let friendChat = GenerationSituation(
    application: "Chat", surroundings: thread, recentLines: ["on my way", "running late, sorry", "yes!"],
    isMultiline: true)

/// A terminal: one line at a time, and mostly symbols.
private let shell = GenerationSituation(
    application: "Terminal", preceding: "$ git status\n$ ls -la",
    recentLines: ["git commit -m 'fix'", "ls -la", "docker compose up -d"])

/// A document: paragraphs on screen, and the person's own lines full sentences.
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
        // A terse person's budget follows their own lines, and their terseness is not quoted as the length to write.
        #expect(register.maxTokens == Register.tokenRange.lowerBound)
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

    @Test("Sentence punctuation in a short chat reply does not make it code.")
    func sentencePunctuationKeepsAChatReplyInProse() {
        let chat = GenerationSituation(
            application: "Chat",
            surroundings: "Priya: ready?\nMe: almost.\nPriya: let me know!",
            recentLines: ["ok, will do.", "sure, I'll send it."],
            isMultiline: true)
        let register = Register.infer(from: chat, typed: "I'm good, thanks!")

        #expect(register.isConversational)
        #expect(register.symbolShare < Register.symbolicShare)
        #expect(register.kind == "reply")
        #expect(register.endsAtSentence)
        #expect(!register.hints.contains("the text here is commands, code or queries rather than prose"))
    }

    @Test("Other scripts' commas and stops read as prose, never as a command's symbols.")
    func otherScriptsSentencePunctuationIsProse() {
        #expect(Register.symbolShare(of: ["我们明天开会，你来吗？好的。"]) == 0)
        #expect(Register.symbolShare(of: ["今日は雨です、傘を持って。"]) == 0)
        #expect(Register.symbolShare(of: ["मैं कल आऊँगा। ठीक है।"]) == 0)
    }

    @Test("A symbol-heavy conversation keeps the reply profile unless its field is a code destination.")
    func symbolHeavyConversationKeepsTheReplyProfile() {
        let chat = GenerationSituation(
            application: "Chat", field: "Message #engineering",
            preceding: "Links: https://example.com/a?b=c, https://example.com/d?e=f",
            surroundings: "Priya: see https://example.com/a?b=c\nMe: got it\nPriya: thanks!",
            recentLines: ["see https://example.com/a?b=c", "thanks!"], isMultiline: true)
        let register = Register.infer(from: chat, typed: "I can review https://example.com/change?a=b.")

        #expect(register.isConversational)
        #expect(register.symbolShare > Register.symbolicShare)
        #expect(register.kind == "reply")
        #expect(register.endsAtSentence)
        #expect(register.registerContinuationLimit == 80)
        #expect(register.longestContinuation <= 80)
        #expect(!register.hints.contains("the text here is commands, code or queries rather than prose"))

        let codeDestination = GenerationSituation(
            application: "Editor", isCodeDestination: true,
            surroundings: chat.surroundings, recentLines: chat.recentLines)
        let codeRegister = Register.infer(from: codeDestination, typed: "open(url: link")
        #expect(codeRegister.kind == "command, query or line of code")
        #expect(!codeRegister.endsAtSentence)
        #expect(codeRegister.registerContinuationLimit == 120)
        #expect(codeRegister.hints.contains("the text here is commands, code or queries rather than prose"))
    }

    @Test("Short command structure counts while unstructured punctuation remains prose.")
    func symbolShareNeedsEnoughVisibleCharacters() {
        #expect(Register.symbolShare(of: ["ls -la"]) > Register.symbolicShare)
        #expect(Register.symbolShare(of: ["\"I'm good, thanks!\""]) == 0)
        #expect(Register.symbolShare(of: ["ls | grep x"]) > Register.symbolicShare)
    }

    @Test("Flags and paths make short command punctuation evidence for the command register.")
    func commandPunctuationCountsAsSymbolEvidence() {
        let terminal = GenerationSituation(application: "Terminal")
        let command = "command, query or line of code"

        #expect(Register.infer(from: terminal, typed: "ls -la").kind == command)
        #expect(Register.infer(from: terminal, typed: "git commit -m 'fix'").kind == command)
        #expect(Register.infer(from: terminal, typed: "./a.b").kind == command)
        #expect(Register.symbolShare(of: ["git commit -m 'fix'"]) == 3.0 / 16.0)
        #expect(Register.symbolShare(of: ["./a.b"]) == 3.0 / 5.0)
    }

    @Test("Emoji in a chat are prose, not symbols, so the line stays a reply.")
    func emojiAreNotSymbols() {
        let chat = GenerationSituation(
            application: "Chat", field: "Message", surroundings: thread,
            recentLines: ["haha 😂😂", "ok 👍", "see you 🙏", "love it ❤️", "yes 👍🏽", "family 👨‍👩‍👧"],
            isMultiline: true)
        let register = Register.infer(from: chat, typed: "sounds")
        #expect(register.symbolShare <= Register.symbolicShare)
        #expect(register.kind == "reply")
        #expect(register.hints.contains("this person writes casually, without sentence punctuation"))
        #expect(!register.hints.contains("the text here is commands, code or queries rather than prose"))
        #expect(Register.symbolShare(of: ["😂👍🙏"]) == 0)
        #expect(Register.symbolShare(of: ["ls | grep x 🙂"]) > 0)
        #expect(!Register.isPictograph("#"))
        #expect(!Register.isPictograph("1"))
        #expect(!Register.isPictograph("$"))
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
        #expect(
            Register.infer(from: GenerationSituation(application: "Browser"), typed: "github.com")
                .writesAddresses)
        // A label cannot establish the address-bar boundary without evidence from the person's own lines.
        let bare = GenerationSituation(application: "Browser", field: "Search or enter website name")
        #expect(!Register.infer(from: bare, typed: "git").writesAddresses)
        // The same combined field with the person's queries in it is a search field, whatever it is called.
        let searched = GenerationSituation(
            application: "Browser", field: "Search or enter website name",
            recentLines: ["swift actors tutorial", "weather tomorrow", "flights to goa december"])
        #expect(!Register.infer(from: searched, typed: "bookcase ").writesAddresses)
        #expect(!Register.infer(from: bare, typed: "git").answersFromHistoryAlone)
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
        let addressBar = GenerationSituation(
            application: "Browser", field: "Address and search bar",
            recentLines: ["github.com/example", "example.com/docs"])
        #expect(Register.infer(from: addressBar, typed: "git").kind.hasPrefix("web address, a host and path"))
    }

    @Test("A known SQL destination names the line as code before any history exists.")
    func knownSqlDestinationNamesTheKindWithoutHistory() {
        let destination = DestinationClassifier.classify(AppContext(applicationName: "DBeaver"))
        let sqlEditor = GenerationSituation(
            application: "DBeaver", isCodeDestination: destination.rawValue == "sqlEditor")
        let register = Register.infer(from: sqlEditor, typed: "SELECT id, name FROM")
        #expect(sqlEditor.recentLines.isEmpty)
        #expect(destination.rawValue == "sqlEditor")
        #expect(register.kind == "command, query or line of code")
        #expect(register.hints.contains("the text here is commands, code or queries rather than prose"))
    }

    @Test("The token budget is half the typical length, held between the shortest and longest pass allowed.")
    func theBudgetFollowsTheLength() {
        #expect(register(length: 10).maxTokens == 24)
        #expect(register(length: 100).maxTokens == 50)
        #expect(register(length: 400).maxTokens == 96)
        #expect(register(length: nil, symbols: 0.4).maxTokens == 32)
        #expect(register(length: nil, conversational: true).maxTokens == 48)
        #expect(register(length: 10, conversational: true).maxTokens == 24)
    }

    @Test(
        "A continuation is held to a multiple of this person's typical line, or to its register's own limit.")
    func theContinuationFollowsTheLength() {
        #expect(register(length: 9).longestContinuation == 27)
        #expect(register(length: 20, conversational: true).longestContinuation == 60)
        #expect(register(length: 3).longestContinuation == Register.shortestAllowance)
        #expect(register(length: 200).longestContinuation == 160)
        #expect(register(length: 200, conversational: true).longestContinuation == 80)
        #expect(register(length: nil, conversational: true).longestContinuation == 80)
        #expect(register(length: nil, symbols: 0.4).longestContinuation == 120)
        #expect(register(length: nil).longestContinuation == 160)
        let addresses = Register(
            isMultiline: false, typicalLength: nil, isConversational: false, symbolShare: 0.3,
            usesSentenceCase: nil, writesAddresses: true)
        #expect(addresses.longestContinuation == 80)
    }

    @Test("Prose ends at its first sentence; a command, a query and an address do not.")
    func onlyProseEndsAtASentence() {
        #expect(register(length: nil, conversational: true).endsAtSentence)
        #expect(register(length: 40).endsAtSentence)
        #expect(!register(length: 40, symbols: 0.3).endsAtSentence)
        let addresses = Register(
            isMultiline: false, typicalLength: nil, isConversational: false, symbolShare: 0,
            usesSentenceCase: nil, writesAddresses: true)
        #expect(!addresses.endsAtSentence)
    }

    @Test("Two turns are not a conversation, and long turns are a document however many there are.")
    func conversationsNeedShortTurns() {
        #expect(!Register.isConversation(["Priya: hi", "Me: hello"]))
        #expect(Register.isConversation(["Priya: hi", "Me: hello", "Priya: how are you?"]))
        let paragraphs = (0..<5).map {
            "\($0 % 2 == 0 ? "Priya" : "Me"): " + String(repeating: "word ", count: 60)
        }
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
    private func register(field: String?, accessibilityRole: String? = nil) -> Register {
        var situation = GenerationSituation(application: "App", field: field)
        situation.accessibilityRole = accessibilityRole
        return Register.infer(from: situation, typed: "ni")
    }

    @Test("A field label cannot declare a history-only search register")
    func labelsDoNotDeclareSearchBoxes() {
        for name in ["Search", "Search products", "Find in page", "Search this Mac"] {
            #expect(!register(field: name).answersFromHistoryAlone, "\(name)")
        }
        for name in ["Message #research", "Message #findings", "Message #user-research", "Reply to Kathurl"] {
            #expect(!register(field: name).answersFromHistoryAlone, "\(name)")
        }
        #expect(register(field: "Search", accessibilityRole: "AXSearchField").isSearchField)
        #expect(register(field: "Search", accessibilityRole: "AXSearchField").answersFromHistoryAlone)
        var search = GenerationSituation(application: "App", field: "Search")
        search.accessibilityRole = "AXSearchField"
        let chosen = search.choosing(["notebook"])
        #expect(chosen.accessibilityRole == "AXSearchField")
        #expect(Register.infer(from: chosen, typed: "no").answersFromHistoryAlone)
    }

    @Test("Arbitrary page labels cannot turn a plain text field into search or address input")
    func pageLabelsDoNotSteerRegisterGates() {
        for name in ["Search", "Search results notes", "Search or enter address", "URL", "URL optional"] {
            let result = register(field: name, accessibilityRole: "AXTextField")
            #expect(!result.isSearchField, "\(name)")
            #expect(!result.writesAddresses, "\(name)")
            #expect(!result.answersFromHistoryAlone, "\(name)")
        }
        #expect(!register(field: "Search", accessibilityRole: "AXTextField").isSearchField)
        #expect(!register(field: "URL", accessibilityRole: "AXTextField").writesAddresses)
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

    @Test("Address-shaped recent lines answer from history without trusting field labels")
    func addressBarsAnswerFromHistory() {
        #expect(!register(field: "Address and search bar").answersFromHistoryAlone)
        let ownAddresses = Register.infer(
            from: GenerationSituation(
                application: "Browser", field: "Location",
                recentLines: ["github.com/uttrflow", "linear.app/team", "example.com/docs"]),
            typed: "git")
        #expect(ownAddresses.answersFromHistoryAlone)
    }
}
