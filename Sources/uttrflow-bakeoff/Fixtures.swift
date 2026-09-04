import UttrflowEval
import UttrflowPredict

/// One situation the generator is measured on: where the caret is, what is around it, and what would count as right.
struct Fixture {
    /// The category first, then the case, as `category/case…`, so hit rates can be read per category.
    let name: String
    let situation: GenerationSituation
    let typed: String
    /// What counts as right here: the acceptable continuations, the length band, the text never to echo.
    let expectation: CompletionExpectation

    init(_ name: String, _ situation: GenerationSituation, typed: String, expectation: CompletionExpectation) {
        self.name = name
        self.situation = situation
        self.typed = typed
        self.expectation = expectation
    }

    init(
        _ name: String, _ situation: GenerationSituation, typed: String, acceptable: [String] = [],
        band: ClosedRange<Int>, forbidden: [String] = []
    ) {
        self.init(
            name, situation, typed: typed,
            expectation: CompletionExpectation(acceptable: acceptable, band: band, forbidden: forbidden))
    }

    /// Whether any of the completions continues the line the way the fixture expects.
    func hits(_ completions: [String]) -> Bool { expectation.hits(completions, typed: typed) }

    /// Whether the first completion keeps to the register: the expected length, and none of the context echoed.
    func conforms(_ completions: [String]) -> Bool { expectation.conforms(completions, typed: typed) }

    /// The category half of the name.
    var category: String { String(name.split(separator: "/").first ?? "") }

    /// Every situation the generator is held to: the hand-written cases first, then the generated catalogue.
    static let all: [Fixture] = handwritten + FixtureCatalogue.all
}

/// The scrollback a terminal shows before its prompt, which is what a shell command is continued from.
private let scrollback =
    "$ git status\nOn branch main\nnothing to commit, working tree clean\n$ ls -la\ntotal 16"

private func terminal(_ preceding: String? = scrollback, recent: [String]) -> GenerationSituation {
    GenerationSituation(
        application: "Terminal", field: "AXTextArea", document: "/Users/me/projects/app",
        preceding: preceding,
        windowTitle: "app — zsh", recentLines: recent)
}

private let commands = [
    "git commit -m 'fix'", "ls -la", "docker compose up -d", "npm run build", "git checkout main",
]

private let sql = GenerationSituation(
    application: "DBeaver", field: "SQL editor", document: "orders_prod",
    preceding: "SELECT * FROM users LIMIT 10;",
    windowTitle: "orders_prod — Script",
    recentLines: ["SELECT * FROM users LIMIT 10;", "SELECT count(*) FROM orders;"],
    isMultiline: true)

private let addressBar = GenerationSituation(
    application: "Chrome", field: "Address and search bar", windowTitle: "New Tab",
    recentLines: [
        "github.com/uttrflow/uttrflow-swift", "linear.app/uttrflow/team", "github.com/uttrflow/backend",
    ])

private let friendThread = """
    Priya: where did the notarisation log go?
    Me: in dist/, one sec
    Priya: found it, thanks!
    Priya: are you coming tonight?
    """

private let friendChat = GenerationSituation(
    application: "Chat", field: "Message", windowTitle: "Priya", surroundings: friendThread,
    recentLines: ["on my way", "running late, sorry", "yes!", "in dist/, one sec"], isMultiline: true)

private let familyChat = GenerationSituation(
    application: "Chat", field: "Message", windowTitle: "Mum",
    surroundings: "Mum: Happy birthday! Hope you have a wonderful day\nMum: call me when you are free",
    recentLines: ["love you too", "will call in the evening", "thank you so much!"], isMultiline: true)

private let casualGroup = GenerationSituation(
    application: "Chat", field: "Type a message", windowTitle: "College group",
    surroundings:
        "Rahul: bro the match was insane 🔥\nAmit: last over!!\nRahul: we have to watch the next one together",
    recentLines: ["haha yes", "count me in", "bro that was wild"], isMultiline: true)

private let workChat = GenerationSituation(
    application: "Chat", field: "Message", windowTitle: "#platform",
    surroundings: "PM: Standup moved to 10:30 tomorrow, please confirm\nDev: Confirmed.",
    recentLines: ["Confirmed, thanks.", "Works for me.", "I will send the numbers after lunch."],
    isMultiline: true)

private let mailReply = GenerationSituation(
    application: "Mail", field: "Message body", windowTitle: "Re: August invoice",
    surroundings: "From: Sam\nHi, could you share the invoice for August when you get a chance? Thanks, Sam",
    recentLines: [
        "Please find the document attached.", "Let me know if anything else is needed.", "Best regards",
    ],
    isMultiline: true)

private let notes = GenerationSituation(
    application: "Notes", field: "Note Body Text View",
    preceding: "The release goes out on Thursday. We measured latency on the larger model and it held.",
    windowTitle: "Release notes",
    recentLines: [
        "The release goes out on Thursday.", "We measured latency on the larger model and it held.",
        "Nobody reads the second paragraph.",
    ],
    isMultiline: true)

private let shoppingList = GenerationSituation(
    application: "Notes", field: "Note Body Text View", preceding: "milk\neggs\nbread",
    windowTitle: "Groceries", recentLines: ["milk", "eggs", "bread", "coffee"], isMultiline: true)

private let code = GenerationSituation(
    application: "Editor", field: "Source", document: "Math.swift",
    preceding: "func add(a: Int, b: Int) -> Int {\n    return a + b\n}\n",
    recentLines: ["func add(a: Int, b: Int) -> Int {", "    return a + b", "}"], isMultiline: true)

private let search = GenerationSituation(
    application: "Finder", field: "Search", windowTitle: "Documents",
    recentLines: ["invoice august", "tax 2025", "invoice july"])

extension Fixture {
    /// The cases written one by one, across the registers people actually type in.
    static let handwritten: [Fixture] = [
        Fixture(
            "terminal/git-c", terminal(recent: commands), typed: "git c", acceptable: ["ommit", "heckout"],
            band: 4...40),
        Fixture(
            "terminal/git-ch", terminal(recent: commands), typed: "git ch", acceptable: ["eckout"],
            band: 5...40),
        Fixture(
            "terminal/docker-r", terminal(recent: commands), typed: "docker r", acceptable: ["un", "m"],
            band: 1...60),
        Fixture(
            "terminal/ls-dash", terminal(recent: commands), typed: "ls -", acceptable: ["l", "a", "h"],
            band: 1...12),
        Fixture(
            "terminal/npm-r", terminal(recent: commands), typed: "npm r", acceptable: ["un"], band: 2...30),
        Fixture(
            "terminal/kubectl", terminal(recent: commands), typed: "kubectl get p", acceptable: ["ods"],
            band: 3...40),
        Fixture(
            "terminal/brew", terminal(recent: commands), typed: "brew ins", acceptable: ["tall"], band: 4...40
        ),
        Fixture(
            "terminal/cd", terminal(recent: ["cd ~/projects/app", "cd ~/projects"]), typed: "cd ~/pro",
            acceptable: ["jects"], band: 5...30),
        Fixture("sql/from-u", sql, typed: "SELECT * FROM u", acceptable: ["sers"], band: 4...60),
        Fixture(
            "sql/where", sql, typed: "SELECT count(*) FROM orders WHERE ", band: 5...80,
            forbidden: ["LIMIT 10;"]),
        Fixture("sql/update", sql, typed: "UPDATE users SET ", band: 5...80),
        Fixture("url/git", addressBar, typed: "git", acceptable: ["hub.com"], band: 3...60),
        Fixture("url/lin", addressBar, typed: "lin", acceptable: ["ear.app"], band: 3...60),
        Fixture("chat/yes", friendChat, typed: "yes", band: 1...60, forbidden: ["Priya:", "Me:"]),
        Fixture(
            "chat/on-my", friendChat, typed: "on m", acceptable: ["y way"], band: 3...60,
            forbidden: ["Priya:"]),
        Fixture(
            "chat/running", friendChat, typed: "running l", acceptable: ["ate"], band: 3...60,
            forbidden: ["Priya:"]),
        Fixture("chat/sure", workChat, typed: "Sure,", band: 3...90, forbidden: ["PM:", "Dev:"]),
        Fixture(
            "chat/confirmed", workChat, typed: "Con", acceptable: ["firmed"], band: 5...90, forbidden: ["PM:"]
        ),
        Fixture(
            "chat/thanks-mum", familyChat, typed: "thank", acceptable: ["s", " you"], band: 1...80,
            forbidden: ["Mum:"]),
        Fixture(
            "chat/will-call", familyChat, typed: "will c", acceptable: ["all"], band: 3...80,
            forbidden: ["Mum:"]),
        Fixture("chat/haha", casualGroup, typed: "haha", band: 1...60, forbidden: ["Rahul:", "Amit:"]),
        Fixture(
            "chat/count", casualGroup, typed: "count", acceptable: [" me in"], band: 3...60,
            forbidden: ["Rahul:"]),
        Fixture(
            "mail/please-find", mailReply, typed: "Please find", acceptable: [" the", " attached"],
            band: 4...120, forbidden: ["From: Sam"]),
        Fixture(
            "mail/let-me", mailReply, typed: "Let me", acceptable: [" know"], band: 4...120,
            forbidden: ["From: Sam"]),
        Fixture(
            "notes/the-next", notes, typed: "The next", band: 4...120,
            forbidden: ["release goes out on Thursday"]),
        Fixture(
            "notes/we-should", notes, typed: "We should", band: 4...120,
            forbidden: ["measured latency on the larger"]),
        Fixture("notes/butter", shoppingList, typed: "bu", acceptable: ["tter"], band: 2...20),
        Fixture(
            "code/func-sub", code, typed: "func sub", acceptable: ["tract", "("], band: 1...90,
            forbidden: ["return a + b"]),
        Fixture("search/inv", search, typed: "inv", acceptable: ["oice"], band: 3...30),
    ]
}
