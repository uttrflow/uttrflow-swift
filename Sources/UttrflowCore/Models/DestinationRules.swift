/// The table every destination is read from; a new app is a new row here and nowhere else.
public enum DestinationRules {
    /// Tried in order: the SQL row sits ahead of the editors because DataGrip shares JetBrains' prefix.
    public static let standard: [DestinationRule] = [
        DestinationRule(
            bundlePrefixes: [
                "at.eggerapps.Postico", "com.tinyapp.TablePlus", "com.jetbrains.datagrip",
                "org.jkiss.dbeaver", "org.pgadmin.pgadmin4",
            ],
            titleContains: ["pgAdmin"],
            destination: .sqlEditor
        ),
        DestinationRule(
            bundlePrefixes: ["com.apple.iWork.Numbers", "com.microsoft.Excel"],
            titleContains: ["Google Sheets"],
            destination: .spreadsheet
        ),
        DestinationRule(
            bundlePrefixes: [
                "com.microsoft.Word", "com.apple.iWork.Pages", "com.apple.Notes", "com.apple.TextEdit",
            ],
            titleContains: ["Google Docs"],
            destination: .document
        ),
        DestinationRule(
            bundlePrefixes: [
                "com.apple.dt.Xcode", "com.todesktop.230313mzl4w4u92", "com.microsoft.VSCode",
                "dev.zed.Zed", "com.jetbrains.", "com.apple.Terminal", "com.googlecode.iterm2",
            ],
            destination: .codeEditor
        ),
        DestinationRule(
            bundlePrefixes: [
                "com.tinyspeck.slackmacgap", "net.whatsapp.WhatsApp", "ru.keepcoder.Telegram",
                "com.hnc.Discord", "com.apple.MobileSMS", "com.microsoft.teams2",
            ],
            destination: .messaging
        ),
        DestinationRule(
            bundlePrefixes: ["com.apple.mail", "com.microsoft.Outlook", "com.superhuman.electron"],
            titleContains: ["Gmail"],
            destination: .email
        ),
    ]
}
