/// What kind of text a field holds, which is what decides whether a branch name belongs in it.
public enum TextKind: String, Sendable, Hashable, CaseIterable {
    /// A command line.
    case shell
    /// A query.
    case sql
    /// An address.
    case url
    /// Source, in a language the field does not name.
    case code
    /// Sentences meant for a person.
    case prose
}

/// Somewhere worth asking for candidates besides what this user has typed into the field before.
public enum Consultation: Sendable, Hashable {
    /// A fact this machine can read about itself, such as a branch or a file beside the working directory.
    case machine(EnvironmentKind)
    /// What this user has already run in a shell.
    case shellHistory
    /// The tables, schemas and columns of the database this tab is connected to.
    case databaseSchema
    /// Addresses this user has already visited.
    case browsingHistory
    /// The files open in the application right now.
    case openDocuments
    /// The fixed vocabulary of the language itself, such as SQL's keywords.
    case languageKeywords
}

/// What one application's fields hold, and what may be consulted to finish them.
public struct Dialect: Sendable, Hashable {
    /// A stable name, so the diagnostics page can say which dialect was chosen.
    public let name: String
    /// The kind of text the field holds.
    public let kind: TextKind
    /// Where to look for candidates, most worth consulting first.
    public let consultations: [Consultation]
    /// The one sentence a model is told about the field before it is asked to continue it.
    public let briefing: String

    public init(name: String, kind: TextKind, consultations: [Consultation], briefing: String) {
        self.name = name
        self.kind = kind
        self.consultations = consultations
        self.briefing = briefing
    }
}

/// Which dialect each application speaks, as a table rather than a switch spread through the code.
public enum DialectRegistry {
    /// A terminal: commands this user has run, and the branches and files of the directory it sits in.
    public static let terminal = Dialect(
        name: "terminal",
        kind: .shell,
        consultations: [
            .shellHistory, .machine(.executable), .machine(.alias), .machine(.gitSubcommand),
            .machine(.gitAlias), .machine(.branch), .machine(.file),
        ],
        briefing: "A shell command line. Continue it with a command, a flag, a branch or a path.")

    /// A database client: a query against the schema the current tab is connected to.
    public static let databaseClient = Dialect(
        name: "database-client",
        kind: .sql,
        consultations: [.databaseSchema, .languageKeywords, .shellHistory],
        briefing: "A SQL query. Continue it with a keyword, a table or a column of the connected schema.")

    /// A browser: somewhere this user has already been.
    public static let browser = Dialect(
        name: "browser",
        kind: .url,
        consultations: [.browsingHistory],
        briefing: "A web address. Continue it with a host or path this user has visited.")

    /// An editor: source, and the names already in the project around it.
    public static let editor = Dialect(
        name: "editor",
        kind: .code,
        consultations: [.openDocuments, .machine(.file), .machine(.branch)],
        briefing: "Source code. Continue it with an identifier or path from this project.")

    /// An API client: a request against a host this user has already called.
    public static let apiClient = Dialect(
        name: "api-client",
        kind: .url,
        consultations: [.browsingHistory, .shellHistory],
        briefing: "An API request. Continue it with a host, a path or a header this user has used.")

    /// Anything else, which assumes the least and consults nothing outside the corpus.
    public static let prose = Dialect(
        name: "prose",
        kind: .prose,
        consultations: [],
        briefing: "Ordinary writing. Continue it with words this user has written here before.")

    /// What an application nobody has described is taken to hold.
    public static let fallback = prose

    /// Every application described here, by bundle identifier.
    public static let byBundleIdentifier: [String: Dialect] = [
        "com.apple.Terminal": terminal,
        "com.googlecode.iterm2": terminal,
        "dev.warp.Warp-Stable": terminal,
        "com.mitchellh.ghostty": terminal,
        "net.kovidgoyal.kitty": terminal,
        "io.alacritty": terminal,
        "com.github.wez.wezterm": terminal,
        "co.zeit.hyper": terminal,

        "com.tinyapp.TablePlus": databaseClient,
        "com.sequel-ace.sequel-ace": databaseClient,
        "com.sequelpro.SequelPro": databaseClient,
        "com.jetbrains.datagrip": databaseClient,
        "com.postgresapp.Postgres2": databaseClient,
        "com.eggerapps.Postico": databaseClient,

        "com.apple.Safari": browser,
        "com.google.Chrome": browser,
        "com.microsoft.edgemac": browser,
        "com.brave.Browser": browser,
        "org.mozilla.firefox": browser,
        "company.thebrowser.Browser": browser,

        "com.microsoft.VSCode": editor,
        "com.todesktop.230313mzl4w4u92": editor,
        "com.apple.dt.Xcode": editor,
        "dev.zed.Zed": editor,
        "com.sublimetext.4": editor,
        "com.jetbrains.intellij": editor,
        "com.jetbrains.pycharm": editor,
        "com.jetbrains.WebStorm": editor,
        "org.vim.MacVim": editor,
        "com.neovide.neovide": editor,

        "com.postmanlabs.mac": apiClient,
        "com.konghq.insomnia": apiClient,
        "com.usebruno.app": apiClient,
        "com.luckymarmot.Paw": apiClient,

        "com.apple.mail": prose,
        "com.apple.Notes": prose,
        "com.tinyspeck.slackmacgap": prose,
        "notion.id": prose,
        "md.obsidian": prose,
    ]

    /// The dialect an application speaks, falling back to prose rather than to nothing.
    public static func dialect(for bundleIdentifier: String) -> Dialect {
        byBundleIdentifier[bundleIdentifier] ?? fallback
    }

    /// The dialect a field speaks, which is its application's until a field says otherwise.
    public static func dialect(for surface: Surface) -> Dialect {
        let application = dialect(for: surface.bundleIdentifier)
        guard application.kind == .url, surface.role == "AXTextArea" else { return application }
        return prose
    }
}
