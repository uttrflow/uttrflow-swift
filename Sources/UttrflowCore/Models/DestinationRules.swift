/// The table every destination is read from; a new app is a new row here and nowhere else.
public enum DestinationRules {
    /// Postico's identifier, named so a corpus case, fixture or default cannot mistype it.
    public static let postico = "at.eggerapps.Postico"
    /// TablePlus's identifier, named so a corpus case, fixture or default cannot mistype it.
    public static let tablePlus = "com.tinyapp.TablePlus"
    /// Numbers's identifier, named so a corpus case, fixture or default cannot mistype it.
    public static let numbers = "com.apple.iWork.Numbers"
    /// Excel's identifier, named so a corpus case, fixture or default cannot mistype it.
    public static let excel = "com.microsoft.Excel"
    /// Word's identifier, named so a corpus case, fixture or default cannot mistype it.
    public static let word = "com.microsoft.Word"
    /// Pages's identifier, named so a corpus case, fixture or default cannot mistype it.
    public static let pages = "com.apple.iWork.Pages"
    /// TextEdit's identifier, named so a corpus case, fixture or default cannot mistype it.
    public static let textEdit = "com.apple.TextEdit"
    /// Notes's identifier, named so a corpus case, fixture or default cannot mistype it.
    public static let notes = "com.apple.Notes"
    /// Reminders's identifier, named so a corpus case, fixture or default cannot mistype it.
    public static let reminders = "com.apple.reminders"
    /// Calendar's identifier, named so a corpus case, fixture or default cannot mistype it.
    public static let calendar = "com.apple.ical"
    /// Things's identifier, named so a corpus case, fixture or default cannot mistype it.
    public static let things = "com.culturedcode.ThingsMac"
    /// OmniFocus's identifier, named so a corpus case, fixture or default cannot mistype it.
    public static let omniFocus = "com.omnigroup.OmniFocus3"
    /// Fantastical's identifier, named so a corpus case, fixture or default cannot mistype it.
    public static let fantastical = "com.flexibits.fantastical2.mac"
    /// Todoist's identifier, named so a corpus case, fixture or default cannot mistype it.
    public static let todoist = "com.todoist.mac.Todoist"
    /// Terminal's identifier, named so a corpus case, fixture or default cannot mistype it.
    public static let terminal = "com.apple.Terminal"
    /// iTerm2's identifier, named so a corpus case, fixture or default cannot mistype it.
    public static let iTerm = "com.googlecode.iterm2"
    /// Xcode's identifier, named so a corpus case, fixture or default cannot mistype it.
    public static let xcode = "com.apple.dt.Xcode"
    /// Cursor's identifier, named so a corpus case, fixture or default cannot mistype it.
    public static let cursor = "com.todesktop.230313mzl4w4u92"
    /// Visual Studio Code's identifier, named so a corpus case, fixture or default cannot mistype it.
    public static let vsCode = "com.microsoft.VSCode"
    /// Zed's identifier, named so a corpus case, fixture or default cannot mistype it.
    public static let zed = "dev.zed.Zed"
    /// Slack's identifier, named so a corpus case, fixture or default cannot mistype it.
    public static let slack = "com.tinyspeck.slackmacgap"
    /// Messages's identifier, named so a corpus case, fixture or default cannot mistype it.
    public static let messages = "com.apple.MobileSMS"
    /// Mail's identifier, named so a corpus case, fixture or default cannot mistype it.
    public static let mail = "com.apple.mail"
    /// Outlook's identifier, named so a corpus case, fixture or default cannot mistype it.
    public static let outlook = "com.microsoft.Outlook"

    /// DataGrip also matches JetBrains' broad code-editor prefix; the classifier chooses its longer SQL prefix.
    public static let standard: [DestinationRule] = [
        DestinationRule(
            bundlePrefixes: [
                postico, tablePlus, "com.jetbrains.datagrip",
                "org.jkiss.dbeaver", "org.pgadmin.pgadmin4", "com.sequelpro", "com.sequel-ace",
                "com.mongodb.compass", "org.RedisLabs.RedisInsight",
            ],
            titleContains: ["pgAdmin", "pgAdmin 4"],
            nameWords: ["tableplus", "postico", "datagrip", "dbeaver", "pgadmin", "sequel"],
            kind: .sqlEditor
        ),
        DestinationRule(
            bundlePrefixes: [numbers, excel],
            titleContains: [
                "Google Sheets", "Excel", "Excel for the web", "Microsoft Excel",
                "Microsoft Excel for the web",
            ],
            nameWords: ["numbers", "excel"],
            kind: .spreadsheet
        ),
        DestinationRule(
            bundlePrefixes: [
                word, pages, textEdit,
            ],
            titleContains: ["Google Docs"],
            nameWords: ["textedit", "pages", "word"],
            kind: .documentEditor
        ),
        DestinationRule(
            bundlePrefixes: [notes, "notion.id", "md.obsidian", "net.shinyfrog.bear"],
            nameWords: ["notes", "notion", "obsidian", "bear", "craft", "drafts"],
            kind: .notes
        ),
        DestinationRule(
            bundlePrefixes: [
                reminders, calendar, things,
                omniFocus, fantastical, todoist,
            ],
            destination: .document, terminalStop: .never
        ),
        DestinationRule(
            bundlePrefixes: [
                terminal, iTerm, "dev.warp.Warp",
                "net.kovidgoyal.kitty", "org.alacritty", "com.mitchellh.ghostty",
                "com.github.wez.wezterm", "co.zeit.hyper", "org.tabby",
            ],
            nameWords: [
                "terminal", "iterm", "iterm2", "warp", "kitty", "alacritty", "ghostty", "wezterm",
                "tabby",
            ],
            kind: .terminal
        ),
        DestinationRule(
            bundlePrefixes: [
                xcode, cursor, vsCode,
                zed, "com.jetbrains.intellij", "com.jetbrains.pycharm",
                "com.jetbrains.goland", "com.jetbrains.rider", "com.jetbrains.webstorm",
                "com.jetbrains.phpstorm", "com.jetbrains.rubymine", "com.jetbrains.clion",
                "com.jetbrains.datagrip", "com.jetbrains.appcode", "com.jetbrains.mps",
                "com.sublimetext", "com.panic.Nova",
                "com.visualstudio.code", "org.vim.MacVim", "com.google.antigravity",
            ],
            nameWords: [
                "xcode", "code", "zed", "sublime", "cursor", "nova", "intellij", "pycharm", "goland",
                "vim", "neovim", "emacs",
            ],
            kind: .codeEditor
        ),
        DestinationRule(
            bundlePrefixes: [
                slack, "net.whatsapp", "desktop.whatsapp", "ru.keepcoder.Telegram",
                "org.telegram", "com.hnc.Discord", messages, "com.microsoft.teams",
                "org.whispersystems.signal",
            ],
            titleContains: [
                "Slack", "Discord", "Messages", "WhatsApp", "Telegram", "Telegram Web", "Teams",
                "Microsoft Teams", "Signal",
            ],
            nameWords: [
                "slack", "discord", "messages", "whatsapp", "telegram", "teams", "signal",
            ],
            kind: .chat
        ),
        DestinationRule(
            bundlePrefixes: [
                mail, outlook, "com.superhuman", "com.readdle.smartemail",
            ],
            titleContains: ["Gmail", "Mail", "Outlook", "Spark", "Superhuman"],
            nameWords: ["mail", "outlook", "spark", "superhuman"],
            kind: .email
        ),
    ]

    /// The Chromium browsers, named here with every other app, for the reads that treat their engine differently.
    public static let chromiumBrowsers: Set<String> = [
        "com.google.Chrome", "com.google.Chrome.beta", "com.google.Chrome.dev", "com.google.Chrome.canary",
        "org.chromium.Chromium", "com.microsoft.edgemac", "com.microsoft.edgemac.Beta",
        "com.microsoft.edgemac.Dev", "com.microsoft.edgemac.Canary", "com.brave.Browser",
        "com.brave.Browser.beta", "com.brave.Browser.nightly", "com.vivaldi.Vivaldi",
        "com.operasoftware.Opera", "company.thebrowser.Browser",
    ]

    /// Every bundle prefix the rows of these kinds name, lowercased, for a module that asks only by identifier.
    public static func bundlePrefixes(of kinds: Set<AppKind>) -> [String] {
        standard.filter { $0.kind.map(kinds.contains) ?? false }
            .flatMap(\.bundlePrefixes).map { $0.lowercased() }
    }
}
