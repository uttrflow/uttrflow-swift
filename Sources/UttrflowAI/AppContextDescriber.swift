// Describes the frontmost app for the prompt, and recognises what sort of app it is.
public import UttrflowCore

/// Turns what the user is looking at into one prompt caption, or nil. See Docs/ai-context-line.md.
public enum AppContextDescriber {
    /// The label the prompt teaches the model to read as background.
    static let label = "Typed into:"
    /// The label the quoted screen text sits behind.
    static let selectionLabel = "nearby text:"

    /// The most window-title characters repeated; longer titles are paths and breadcrumbs.
    static let documentLimit = 60
    /// The most selection characters repeated; longer buys nothing measured. See Docs/ai-context-line.md.
    static let selectionLimit = 120

    /// The line to put above the dictation, or `nil` (never an empty string) when there is nothing to say.
    public static func describe(_ context: AppContext) -> String? {
        let place = [placePhrase(context), field(context.documentName, limit: documentLimit)]
            .compactMap { $0 }
            .joined(separator: ", ")
        let selection = field(context.selectedText, limit: selectionLimit)

        switch (place.isEmpty, selection) {
        case (true, nil):
            return nil
        case (true, let selection?):
            // A selection with no known place still uses the label the prompt teaches.
            return "\(label) an app; \(selectionLabel) \"\(selection)\""
        case (false, nil):
            return "\(label) \(place)"
        case (false, let selection?):
            return "\(label) \(place); \(selectionLabel) \"\(selection)\""
        }
    }

    // MARK: The place

    /// "a code editor (Xcode)", "a chat app", "an app called Linear", or nothing.
    private static func placePhrase(_ context: AppContext) -> String? {
        let name = field(context.applicationName, limit: documentLimit)
        guard let kind = AppKind(applicationName: name, bundleIdentifier: context.bundleIdentifier)
        else {
            // With no known kind the name is said as a noun phrase; a bare product name does nothing.
            return name.map { "an app called \($0)" }
        }
        guard let name else { return kind.phrase }
        return "\(kind.phrase) (\(name))"
    }

    // MARK: Sanitising

    /// One line with double quotes made single, so screen text cannot forge a prompt line; nil when blank.
    static func field(_ value: String?, limit: Int) -> String? {
        guard let value else { return nil }
        let flattened = TextTidy.collapseWhitespace(value).replacingOccurrences(of: "\"", with: "'")
        guard !flattened.isEmpty else { return nil }
        return truncate(flattened, to: limit)
    }

    /// Cuts at the last word boundary inside the limit, so a quotation does not end in the middle of a name.
    static func truncate(_ text: String, to limit: Int) -> String {
        guard text.count > limit else { return text }
        let head = text.prefix(limit)
        let cut = head.lastIndex(of: " ").map { head[..<$0] } ?? head
        // A single word longer than the budget keeps the hard cut rather than becoming a lone ellipsis.
        let kept = cut.isEmpty ? head : cut
        return "\(kept)…"
    }
}

/// The sort of application, recognised from the bundle identifier first and the application name second.
enum AppKind: String, Sendable, Equatable, CaseIterable {
    case chat
    case email
    case codeEditor
    case sqlEditor
    case terminal
    case browser
    case notes
    case documentEditor

    /// How the kind reads in the prompt, article included, because the line is a noun phrase.
    var phrase: String {
        switch self {
        case .chat: "a chat app"
        case .email: "an email app"
        case .codeEditor: "a code editor"
        case .sqlEditor: "a SQL editor"
        case .terminal: "a terminal"
        case .browser: "a web browser"
        case .notes: "a note taking app"
        case .documentEditor: "a document editor"
        }
    }

    /// Recognises the kind from the bundle identifier, else from the name, else fails.
    init?(applicationName: String?, bundleIdentifier: String?) {
        if let bundleIdentifier, let kind = Self.byBundleIdentifier(bundleIdentifier) {
            self = kind
            return
        }
        if let applicationName, let kind = Self.byName(applicationName) {
            self = kind
            return
        }
        return nil
    }

    /// Bundle prefixes matched lower-cased, so one `com.jetbrains` entry covers every JetBrains editor.
    private static let bundlePrefixes: [(String, AppKind)] = [
        ("com.tinyspeck.slackmacgap", .chat),
        ("com.hnc.discord", .chat),
        ("com.apple.mobilesms", .chat),
        ("net.whatsapp", .chat),
        ("desktop.whatsapp", .chat),
        ("org.telegram", .chat),
        ("com.microsoft.teams", .chat),
        ("com.apple.mail", .email),
        ("com.microsoft.outlook", .email),
        ("com.readdle.smartemail", .email),
        ("com.superhuman", .email),
        ("com.apple.dt.xcode", .codeEditor),
        ("com.microsoft.vscode", .codeEditor),
        ("dev.zed.zed", .codeEditor),
        ("com.sublimetext", .codeEditor),
        ("com.jetbrains", .codeEditor),
        ("com.panic.nova", .codeEditor),
        ("com.todesktop", .codeEditor),  // Cursor
        ("com.tinyapp.tableplus", .sqlEditor),
        ("eggerapps.postico", .sqlEditor),
        ("com.sequelpro", .sqlEditor),
        ("com.sequel-ace", .sqlEditor),
        ("org.jkiss.dbeaver", .sqlEditor),
        ("com.apple.terminal", .terminal),
        ("com.googlecode.iterm2", .terminal),
        ("dev.warp.warp", .terminal),
        ("net.kovidgoyal.kitty", .terminal),
        ("org.alacritty", .terminal),
        ("com.mitchellh.ghostty", .terminal),
        ("com.apple.safari", .browser),
        ("com.google.chrome", .browser),
        ("org.mozilla.firefox", .browser),
        ("company.thebrowser", .browser),
        ("com.microsoft.edgemac", .browser),
        ("com.apple.notes", .notes),
        ("notion.id", .notes),
        ("md.obsidian", .notes),
        ("net.shinyfrog.bear", .notes),
        ("com.apple.textedit", .documentEditor),
        ("com.apple.iwork.pages", .documentEditor),
        ("com.microsoft.word", .documentEditor),
    ]

    /// Matches DataGrip before the `com.jetbrains` prefix it shares with the editors.
    private static func byBundleIdentifier(_ identifier: String) -> AppKind? {
        let lowered = identifier.lowercased()
        if lowered.hasPrefix("com.jetbrains.datagrip") { return .sqlEditor }
        return bundlePrefixes.first { lowered.hasPrefix($0.0) }?.1
    }

    /// Words matched whole in the application name, so "Notes for Slack" is not a note taking app.
    private static let nameWords: [(String, AppKind)] = [
        ("slack", .chat), ("discord", .chat), ("messages", .chat), ("whatsapp", .chat),
        ("telegram", .chat), ("teams", .chat), ("signal", .chat),
        ("mail", .email), ("outlook", .email), ("spark", .email), ("superhuman", .email),
        ("xcode", .codeEditor), ("code", .codeEditor), ("zed", .codeEditor),
        ("sublime", .codeEditor), ("cursor", .codeEditor), ("nova", .codeEditor),
        ("intellij", .codeEditor), ("pycharm", .codeEditor), ("goland", .codeEditor),
        ("vim", .codeEditor), ("neovim", .codeEditor), ("emacs", .codeEditor),
        ("tableplus", .sqlEditor), ("postico", .sqlEditor), ("datagrip", .sqlEditor),
        ("dbeaver", .sqlEditor), ("pgadmin", .sqlEditor), ("sequel", .sqlEditor),
        ("terminal", .terminal), ("iterm", .terminal), ("iterm2", .terminal),
        ("warp", .terminal), ("kitty", .terminal), ("alacritty", .terminal),
        ("ghostty", .terminal),
        ("safari", .browser), ("chrome", .browser), ("firefox", .browser),
        ("arc", .browser), ("edge", .browser), ("brave", .browser),
        ("notes", .notes), ("notion", .notes), ("obsidian", .notes), ("bear", .notes),
        ("craft", .notes), ("drafts", .notes),
        ("textedit", .documentEditor), ("pages", .documentEditor), ("word", .documentEditor),
    ]

    /// The kind whose word appears whole in `name`, if any.
    private static func byName(_ name: String) -> AppKind? {
        let words = Set(TextTidy.words(name))
        return nameWords.first { words.contains($0.0) }?.1
    }
}
