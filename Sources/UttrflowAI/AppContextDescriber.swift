// Describes the frontmost app for the prompt, from the destination the one table resolved.
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
    public static func describe(_ situation: Situation) -> String? {
        let context = situation.app
        let place = [placePhrase(situation), field(context.documentName, limit: documentLimit)]
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
    private static func placePhrase(_ situation: Situation) -> String? {
        let name = field(situation.app.applicationName, limit: documentLimit)
        guard let kind = AppKind(naming: situation) else {
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

extension AppKind {
    /// How the kind reads in the prompt, article included, because the line is a noun phrase.
    var phrase: String {
        switch self {
        case .chat: "a chat app"
        case .email: "an email app"
        case .codeEditor: "a code editor"
        case .terminal: "a terminal"
        case .sqlEditor: "a SQL editor"
        case .spreadsheet: "a spreadsheet"
        case .notes: "a note taking app"
        case .documentEditor: "a document editor"
        }
    }
}
