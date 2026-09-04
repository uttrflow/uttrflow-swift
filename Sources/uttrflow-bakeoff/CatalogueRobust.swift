import UttrflowPredict

extension FixtureCatalogue {
    /// Lines that strain the parser and the prompt: marks, emoji, odd spacing, long lines, finished lines, tiny prefixes.
    static let robust: [Scenario] =
        [marks, emoji, spacingCommand, spacingProse, unicode, long] + complete + short

    private static let marks = Scenario(
        category: "robust", name: "marks",
        situation: GenerationSituation(
            application: "Safari", field: "Search products", windowTitle: "Brightleaf Store",
            recentLines: ["MitoActive™ serum", "Zenlight® lamp", "kettle red"]),
        cuts: [.afterWord(2), .midWord(4)], determinacy: .any, band: 1...60,
        lines: [
            "what is the price of MitoActive™ serum", "is the Zenlight® lamp in stock",
            "does the Aurora™ kettle come in red", "Kestrel Labs® return policy",
            "© 2026 Brightleaf Ltd all rights reserved",
        ])

    private static let emoji = Scenario(
        category: "robust", name: "emoji", situation: casualChat,
        cuts: [.afterWord(2), .afterWord(3)], determinacy: .any, band: 1...40, forbidden: ["Priya:", "Me:"],
        lines: [
            "on my way 🚗 be there soon", "happy birthday 🎂 have a great day", "🔥🔥 that was insane",
            "ok 👍 sending now", "lol 😂 same here",
        ])

    private static let spacingCommand = Scenario(
        category: "robust", name: "spacing-command",
        situation: terminal(
            directory: "/Users/me/projects/api", title: "api — zsh",
            scrollback: "$ git status\nOn branch main",
            recent: ["git status", "docker compose up -d", "ls -la"]),
        cuts: [], determinacy: .command, band: 1...48,
        lines: [
            Line("git  status", cuts: [.characters(5), .characters(7)]),
            Line("docker  compose up", cuts: [.characters(8), .characters(11)]),
        ])

    private static let spacingProse = Scenario(
        category: "robust", name: "spacing-prose", situation: casualChat,
        cuts: [], determinacy: .any, band: 1...40, forbidden: ["Priya:", "Me:"],
        lines: [
            Line("see you  tomorrow", cuts: [.characters(9), .characters(12)]),
            Line("the report  is attached", cuts: [.characters(12), .characters(14)]),
        ])

    private static let unicode = Scenario(
        category: "robust", name: "unicode",
        situation: GenerationSituation(
            application: "Notes", field: "Note Body Text View",
            preceding: "Notes from the café — Thursday’s meeting moved, again.", windowTitle: "Journal",
            recentLines: ["Thursday’s meeting moved, again.", "Notes from the café", "wait… what?"],
            isMultiline: true),
        cuts: [.afterWord(2), .midWord(3)], determinacy: .any, band: 1...80,
        forbidden: ["meeting moved, again"],
        lines: [
            "she said “let’s go” and left", "the meeting — moved to Thursday — is now optional",
            "wait… what time is it", "café near the station opens at 7", "a naïve approach won’t scale",
        ])

    private static let long = Scenario(
        category: "robust", name: "long",
        situation: GenerationSituation(
            application: "Pages", field: "Body", document: "Draft.pages",
            preceding: "The following paragraphs describe the method in full, one long sentence at a time.",
            windowTitle: "Draft", recentLines: ["The following paragraphs describe the method in full."],
            isMultiline: true),
        cuts: [.characters(120), .characters(200)], determinacy: .any, band: 1...160,
        forbidden: ["describe the method in full"],
        lines: [
            """
            When the person pauses for long enough the coordinator reads the field once, assembles the register \
            from what it finds there, hands the model the last lines on screen together with the person's own \
            recent lines, and draws whatever comes back as a ghost after the caret.
            """,
            """
            The evaluation set exists because a number measured on twenty-nine hand-written situations says very \
            little about what a person will see in an application nobody thought to test, and a thousand \
            generated situations at least say where the model tends to go wrong.
            """,
            """
            Nothing about an application is written into the code, so a suggestion in a terminal reads like a \
            command and a suggestion in a chat reads like a reply only because the hints computed from the \
            screen and from the person's own lines told the model which it was looking at.
            """,
        ])

    /// Lines already complete, where the right answer is no completion at all.
    private static let complete: [Scenario] = [
        Scenario(
            category: "robust", name: "complete-chat", situation: casualChat, cuts: [.whole],
            determinacy: .nothing,
            band: 1...40, lines: ["Thanks, see you tomorrow.", "See you at 8!", "Ok, on my way."]),
        Scenario(
            category: "robust", name: "complete-mail",
            situation: GenerationSituation(
                application: "Mail", field: "Message body", windowTitle: "Re: August invoice",
                surroundings:
                    "From: Sam\nHi, could you share the invoice for August when you get a chance? Thanks, Sam",
                recentLines: ["Please find the document attached.", "Kind regards,"], isMultiline: true),
            cuts: [.whole], determinacy: .nothing, band: 1...120,
            lines: ["Please find the invoice attached.", "Kind regards,"]),
        Scenario(
            category: "robust", name: "complete-sql",
            situation: editor(
                database: "shop_prod", script: "SELECT * FROM users LIMIT 10;",
                recent: ["SELECT * FROM users LIMIT 10;"]),
            cuts: [.whole], determinacy: .nothing, band: 1...80, lines: ["SELECT count(*) FROM orders;"]),
    ]

    /// One- and two-character prefixes, where one character is refused and two are answered with anything.
    private static let short: [Scenario] = [
        Scenario(
            category: "robust", name: "short-command",
            situation: terminal(
                directory: "/Users/me/projects/api", title: "api — zsh",
                scrollback: "$ git status\nOn branch main",
                recent: ["git status", "ls -la", "git pull"]),
            cuts: [], determinacy: .any, band: 1...48,
            lines: [
                Line("git status", slug: "g", cuts: [.characters(1)], determinacy: .nothing),
                Line("git status", slug: "gi", cuts: [.characters(2)]),
                Line("ls -la", slug: "l", cuts: [.characters(1)], determinacy: .nothing),
                Line("ls -la", slug: "ls", cuts: [.characters(2)]),
                Line("  ok", slug: "blank", cuts: [.characters(2)], determinacy: .nothing),
            ]),
        Scenario(
            category: "robust", name: "short-chat", situation: casualChat, cuts: [], determinacy: .any,
            band: 1...40,
            forbidden: ["Priya:", "Me:"],
            lines: [
                Line("on my way", slug: "o", cuts: [.characters(1)], determinacy: .nothing),
                Line("on my way", slug: "on", cuts: [.characters(2)]),
            ]),
        Scenario(
            category: "robust", name: "short-sql",
            situation: editor(
                database: "shop_prod", script: "SELECT * FROM users LIMIT 10;",
                recent: ["SELECT * FROM users LIMIT 10;"]),
            cuts: [], determinacy: .any, band: 1...80,
            lines: [
                Line("SELECT * FROM users", slug: "s", cuts: [.characters(1)], determinacy: .nothing),
                Line("SELECT * FROM users", slug: "se", cuts: [.characters(2)]),
            ]),
        Scenario(
            category: "robust", name: "short-url",
            situation: GenerationSituation(
                application: "Chrome", field: "Address and search bar", windowTitle: "New Tab",
                recentLines: ["github.com/brightleaf/api", "localhost:3000"]),
            cuts: [], determinacy: .any, band: 1...60,
            lines: [
                Line("github.com", slug: "g", cuts: [.characters(1)], determinacy: .nothing),
                Line("github.com", slug: "gi", cuts: [.characters(2)]),
            ]),
    ]

    /// The friend chat the robustness lines are typed into, so parser strain is measured in a known register.
    static let casualChat = GenerationSituation(
        application: "Chat", field: "Message", windowTitle: "Priya",
        surroundings: "Priya: are you coming tonight?\nMe: yes!\nPriya: we're at the usual place from 8",
        recentLines: ["yes!", "on my way", "running late, sorry", "save me a seat"], isMultiline: true)
}
