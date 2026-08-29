public import UttrflowCore
public import Foundation

/// A phrase you say, and the block of text you get instead.
///
/// One snippet, ready to draw.
public struct SnippetRow: Sendable, Equatable, Identifiable {
    public let id: UUID
    public let trigger: MainPill
    public let text: String
    public let timesUsed: String
    /// "Today", "Tuesday", "12 Aug" — or "Never", because a snippet nobody has used is
    /// worth spotting.
    public let lastUsed: String
    public let actions: [MainAction]

    public init(
        id: UUID, trigger: MainPill, text: String, timesUsed: String, lastUsed: String,
        actions: [MainAction]
    ) {
        self.id = id
        self.trigger = trigger
        self.text = text
        self.timesUsed = timesUsed
        self.lastUsed = lastUsed
        self.actions = actions
    }
}

/// The snippet being written, in the row where it will end up.
///
/// Inline rather than a sheet: a snippet is two fields, and a modal window over two
/// fields makes adding one feel like a chore that has to be worth it.
public struct SnippetEditor: Sendable, Equatable {
    /// The snippet being changed, or `nil` when this is a new one.
    public let editing: UUID?
    public let trigger: String
    public let text: String
    public let triggerLabel: String
    public let textLabel: String
    /// "Editing" or "New". Absent from neither, so the row is never ambiguous.
    public let badge: MainPill
    /// Why this cannot be saved yet, in words. Absent when it can.
    public let problem: String?
    public let save: MainAction
    public let cancel: MainAction

    public var canSave: Bool { problem == nil }

    public init(
        editing: UUID?,
        trigger: String,
        text: String,
        triggerLabel: String,
        textLabel: String,
        badge: MainPill,
        problem: String?,
        save: MainAction,
        cancel: MainAction
    ) {
        self.editing = editing
        self.trigger = trigger
        self.text = text
        self.triggerLabel = triggerLabel
        self.textLabel = textLabel
        self.badge = badge
        self.problem = problem
        self.save = save
        self.cancel = cancel
    }
}

/// What the user is part-way through writing.
///
/// Held apart from the stored snippets because a half-typed trigger is not a snippet,
/// and letting it into the list would make an empty trigger something the matcher could
/// one day try to match.
public struct SnippetDraft: Sendable, Equatable {
    public let editing: UUID?
    public let trigger: String
    public let text: String

    public init(editing: UUID? = nil, trigger: String = "", text: String = "") {
        self.editing = editing
        self.trigger = trigger
        self.text = text
    }
}

/// Everything the snippets page is drawn from.
public struct SnippetsSnapshot: Sendable, Equatable {
    public let snippets: [Snippet]
    /// Set while the inline editor is open.
    public let draft: SnippetDraft?
    /// Why the last Save did not happen, when the store refused it. See
    /// ``DictionarySnapshot/refusal``.
    public let refusal: String?
    public let query: String
    public let now: Date

    public init(
        snippets: [Snippet] = [], draft: SnippetDraft? = nil, refusal: String? = nil,
        query: String = "", now: Date
    ) {
        self.snippets = snippets
        self.draft = draft
        self.refusal = refusal
        self.query = query
        self.now = now
    }
}

/// What the snippets page shows.
public struct SnippetsPresentation: Sendable, Equatable {
    public let chrome: MainPageChrome
    /// "5 snippets".
    public let caption: String
    public let rows: [SnippetRow]
    public let editor: SnippetEditor?
    /// Set when there is nothing to list *and* nothing being written — an empty state
    /// under an open editor would be telling the user off for the thing they are doing.
    public let emptyState: MainEmptyState?
    /// The worked example on the empty page: a trigger and what it types.
    public let example: SnippetExample?
    public let footnote: String?

    public init(
        chrome: MainPageChrome,
        caption: String,
        rows: [SnippetRow],
        editor: SnippetEditor?,
        emptyState: MainEmptyState?,
        example: SnippetExample?,
        footnote: String?
    ) {
        self.chrome = chrome
        self.caption = caption
        self.rows = rows
        self.editor = editor
        self.emptyState = emptyState
        self.example = example
        self.footnote = footnote
    }
}

/// The one snippet shown to somebody who has none, so the idea lands before the form does.
public struct SnippetExample: Sendable, Equatable {
    public let heading: String
    public let trigger: MainPill
    public let text: String

    public init(heading: String, trigger: MainPill, text: String) {
        self.heading = heading
        self.trigger = trigger
        self.text = text
    }
}

/// Turns stored snippets into the page that edits them.
public enum SnippetsPresenter {
    public static let searchPlaceholder = "Search snippets"

    public static func page(
        for snapshot: SnippetsSnapshot,
        calendar: Calendar = .autoupdatingCurrent,
        locale: Locale = .autoupdatingCurrent
    ) -> SnippetsPresentation {
        let listed = matches(snapshot.snippets, query: snapshot.query, locale: locale)
        let rows = listed.map {
            row(for: $0, now: snapshot.now, calendar: calendar, locale: locale)
        }
        let editor = snapshot.draft.map { self.editor(for: $0, in: snapshot) }

        return SnippetsPresentation(
            chrome: MainPageChrome(
                title: "Snippets",
                caption: "Short triggers that expand into whatever you like.",
                search: snapshot.snippets.isEmpty
                    ? nil
                    : MainSearchField(placeholder: searchPlaceholder, query: snapshot.query),
                addAction: MainAction(
                    title: "New Snippet", symbolName: "plus", intent: .addSnippet)),
            caption: MainFormatting.count(snapshot.snippets.count, "snippet", "snippets"),
            rows: rows,
            editor: editor,
            emptyState: rows.isEmpty && editor == nil ? emptyState(for: snapshot) : nil,
            example: rows.isEmpty && editor == nil && snapshot.snippets.isEmpty ? example : nil,
            footnote: rows.isEmpty
                ? nil
                : """
                Say the trigger anywhere in a sentence and Uttrflow swaps in the text. Triggers \
                are matched on what you said, so “my address” works whether you pause around it \
                or not.
                """)
    }

    static let example = SnippetExample(
        heading: "For example",
        trigger: MainPill(text: "my address", tone: .accent),
        text: "Flat 402, Example Residences, Bengaluru")

    // MARK: - Searching

    /// Matches the trigger and the text. The text matters because the trigger is the
    /// half people forget — you remember the address, not what you called it.
    static func matches(_ snippets: [Snippet], query: String, locale: Locale) -> [Snippet] {
        let needle = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !needle.isEmpty else { return snippets }
        return snippets.filter { snippet in
            [snippet.trigger, snippet.expansion].contains {
                $0.range(
                    of: needle, options: [.caseInsensitive, .diacriticInsensitive], range: nil,
                    locale: locale) != nil
            }
        }
    }

    // MARK: - One snippet

    static func row(
        for snippet: Snippet, now: Date, calendar: Calendar, locale: Locale
    ) -> SnippetRow {
        SnippetRow(
            id: snippet.id,
            trigger: MainPill(text: snippet.trigger, tone: .accent),
            text: snippet.expansion,
            timesUsed: "\(snippet.timesUsed)",
            lastUsed: snippet.lastUsed.map {
                MainFormatting.day($0, now: now, calendar: calendar, locale: locale)
            } ?? "Never",
            actions: [
                MainAction(title: "Edit", symbolName: "pencil", intent: .editSnippet(snippet.id)),
                MainAction(
                    title: "Delete", symbolName: "trash", intent: .forgetSnippet(snippet.id),
                    isDestructive: true),
            ])
    }

    // MARK: - Writing one

    static func editor(for draft: SnippetDraft, in snapshot: SnippetsSnapshot) -> SnippetEditor {
        SnippetEditor(
            editing: draft.editing,
            trigger: draft.trigger,
            text: draft.text,
            triggerLabel: "When I say",
            textLabel: "Type this",
            badge: MainPill(text: draft.editing == nil ? "New" : "Editing"),
            problem: problem(with: draft, in: snapshot),
            save: MainAction(
                title: "Save",
                intent: .saveSnippet(
                    trigger: draft.trigger, text: draft.text, replacing: draft.editing)),
            cancel: MainAction(title: "Cancel", intent: .cancelSnippetEdit))
    }

    /// Why a draft cannot be saved, said before the button is pressed.
    ///
    /// A duplicate trigger is refused rather than allowed to shadow the older snippet:
    /// two snippets that answer to one phrase means one of them silently never fires,
    /// and the user has no way to find out which.
    static func problem(with draft: SnippetDraft, in snapshot: SnippetsSnapshot) -> String? {
        let trigger = draft.trigger.trimmingCharacters(in: .whitespacesAndNewlines)
        if trigger.isEmpty { return "A snippet needs something to say." }
        // The store's refusal wins over this page's own rules: it is the more recent
        // fact, and it is about the attempt the user actually made.
        if let refusal = snapshot.refusal { return refusal }
        if draft.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return "A snippet needs something to type."
        }
        // Compared on the matcher's own view of the trigger, so "my address" and
        // "My address:" are recognised as the same snippet rather than saved twice.
        let key = Snippet(trigger: trigger, expansion: " ", created: .distantPast).triggerWords
        let clash = snapshot.snippets.contains {
            $0.id != draft.editing && $0.triggerWords == key
        }
        return clash ? "You already have a snippet for “\(trigger)”." : nil
    }

    // MARK: - Nothing to show

    static func emptyState(for snapshot: SnippetsSnapshot) -> MainEmptyState {
        let query = snapshot.query.trimmingCharacters(in: .whitespacesAndNewlines)
        if !query.isEmpty {
            return MainEmptyState(
                symbolName: "magnifyingglass",
                title: "No matches",
                message: "No snippet of yours mentions “\(query)”.")
        }
        return MainEmptyState(
            symbolName: "doc.on.doc",
            title: "No snippets yet",
            message: """
                A snippet turns something you say into a block of text you would rather not say \
                out loud every time — an address, a standup format, a sign-off.
                """,
            action: MainAction(title: "New Snippet", symbolName: "plus", intent: .addSnippet))
    }
}
