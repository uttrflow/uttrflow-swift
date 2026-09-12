/// The table every destination is read from; a new app is a new row here and nowhere else.
public enum DestinationRules {
    /// Tried in order: the SQL row sits ahead of the editors because DataGrip shares JetBrains' prefix.
    public static let standard: [DestinationRule] = [
        DestinationRule(
            bundlePrefixes: [
                "at.eggerapps.Postico", "com.tinyapp.TablePlus", "com.jetbrains.datagrip",
                "org.jkiss.dbeaver", "org.pgadmin.pgadmin4", "com.sequelpro", "com.sequel-ace",
            ],
            titleContains: ["pgAdmin"],
            nameWords: ["tableplus", "postico", "datagrip", "dbeaver", "pgadmin", "sequel"],
            kind: .sqlEditor
        ),
        DestinationRule(
            bundlePrefixes: ["com.apple.iWork.Numbers", "com.microsoft.Excel"],
            titleContains: ["Google Sheets"],
            nameWords: ["numbers", "excel"],
            kind: .spreadsheet
        ),
        DestinationRule(
            bundlePrefixes: [
                "com.microsoft.Word", "com.apple.iWork.Pages", "com.apple.TextEdit",
            ],
            titleContains: ["Google Docs"],
            nameWords: ["textedit", "pages", "word"],
            kind: .documentEditor
        ),
        DestinationRule(
            bundlePrefixes: ["com.apple.Notes", "notion.id", "md.obsidian", "net.shinyfrog.bear"],
            nameWords: ["notes", "notion", "obsidian", "bear", "craft", "drafts"],
            kind: .notes
        ),
        DestinationRule(
            bundlePrefixes: [
                "com.apple.Terminal", "com.googlecode.iterm2", "dev.warp.Warp",
                "net.kovidgoyal.kitty", "org.alacritty", "com.mitchellh.ghostty",
            ],
            nameWords: ["terminal", "iterm", "iterm2", "warp", "kitty", "alacritty", "ghostty"],
            kind: .terminal
        ),
        DestinationRule(
            bundlePrefixes: [
                "com.apple.dt.Xcode", "com.todesktop.230313mzl4w4u92", "com.microsoft.VSCode",
                "dev.zed.Zed", "com.jetbrains.", "com.sublimetext", "com.panic.Nova",
            ],
            nameWords: [
                "xcode", "code", "zed", "sublime", "cursor", "nova", "intellij", "pycharm", "goland",
                "vim", "neovim", "emacs",
            ],
            kind: .codeEditor
        ),
        DestinationRule(
            bundlePrefixes: [
                "com.tinyspeck.slackmacgap", "net.whatsapp", "desktop.whatsapp", "ru.keepcoder.Telegram",
                "org.telegram", "com.hnc.Discord", "com.apple.MobileSMS", "com.microsoft.teams",
                "org.whispersystems.signal",
            ],
            nameWords: [
                "slack", "discord", "messages", "whatsapp", "telegram", "teams", "signal",
            ],
            kind: .chat
        ),
        DestinationRule(
            bundlePrefixes: [
                "com.apple.mail", "com.microsoft.Outlook", "com.superhuman", "com.readdle.smartemail",
            ],
            titleContains: ["Gmail"],
            nameWords: ["mail", "outlook", "spark", "superhuman"],
            kind: .email
        ),
    ]
}
