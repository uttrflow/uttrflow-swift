// The home page: what it shows and the presenter that draws it from the app's state.
public import Foundation
public import UttrflowAccount
public import UttrflowCore
public import UttrflowHistory
public import UttrflowSettings

/// What the home page shows, drawn only from values the pages behind it also use.
public struct HomePresentation: Sendable, Equatable {
    /// "Good morning, Naveen" — or just "Good morning" when there is no name to use.
    public let greeting: String
    /// One sentence under the greeting saying where things stand.
    public let subtitle: String
    /// The big figures, across the top.
    public let figures: [MainStatistic]
    /// The last few dictations, newest first. Empty on a quiet day.
    public let recent: [HomeRow]
    /// "Today" when every row is from today, "Recent" once the list reaches back into yesterday.
    public let recentTitle: String
    /// Where the whole list lives, offered only when there is more than is shown.
    public let seeAll: MainAction?
    /// The one thing worth doing next, when there is one; absent when nothing is outstanding.
    public let nextStep: MainEmptyState?
    /// The line under the greeting, in parts, so the shortcut can be drawn as keys.
    public let hint: HomeHint
    /// The clipboard shown working; absent when the user has turned its shortcut off.
    public let demonstration: HomeDemonstration?
    /// Whether Uttrflow can hear you, said in words above the greeting.
    public let status: HomeStatus
    /// Who is signed in, and the way to the page about them; always present.
    public let account: HomeAccount

    /// Builds a page from its parts.
    public init(
        greeting: String,
        subtitle: String,
        figures: [MainStatistic],
        recent: [HomeRow],
        recentTitle: String,
        seeAll: MainAction?,
        nextStep: MainEmptyState?,
        hint: HomeHint,
        demonstration: HomeDemonstration?,
        status: HomeStatus,
        account: HomeAccount
    ) {
        self.greeting = greeting
        self.subtitle = subtitle
        self.figures = figures
        self.recent = recent
        self.recentTitle = recentTitle
        self.seeAll = seeAll
        self.nextStep = nextStep
        self.hint = hint
        self.demonstration = demonstration
        self.status = status
        self.account = account
    }
}

/// The line under the greeting in three parts, so the shortcut is drawn as keys.
public struct HomeHint: Sendable, Equatable {
    /// The words before the keys.
    public let lead: String
    /// The shortcut as separate caps — "⌥", "Space" — so they can be drawn as keys.
    public let keys: [String]
    /// The words after the keys.
    public let trail: String

    /// Builds the line from its three parts.
    public init(lead: String, keys: [String], trail: String) {
        self.lead = lead
        self.keys = keys
        self.trail = trail
    }

    /// The whole line as one sentence, for a screen reader and the menu bar.
    public var sentence: String {
        "\(lead) \(keys.joined()) \(trail)"
    }
}

/// Whether Uttrflow can listen, as one sentence above the greeting rather than a colour.
public struct HomeStatus: Sendable, Equatable {
    /// The sentence itself.
    public let text: String
    /// Whether the ring is drawn lit; false while anything stops a dictation starting.
    public let isReady: Bool

    /// Builds the status from its sentence and its ring.
    public init(text: String, isReady: Bool) {
        self.text = text
        self.isReady = isReady
    }
}

/// The person, as the way into the page about them.
public enum HomeAccount: Sendable, Equatable {
    /// Somebody is signed in; `initials` is one or two letters, never three, and `name` is the first name.
    case signedIn(initials: String, name: String, open: MainAction)

    /// Nobody is signed in, so the corner offers the way in rather than a monogram.
    case signedOut(open: MainAction)

    /// Nobody needs to sign in: this person chose this Mac, so the monogram is drawn unfilled.
    case onThisMac(initials: String, name: String, open: MainAction)

    /// Where the chip goes, whichever state it is in.
    public var open: MainAction {
        switch self {
        case .signedIn(_, _, let open), .onThisMac(_, _, let open), .signedOut(let open): open
        }
    }
}

/// A feature shown working rather than described; the words are here and the motion is the view's.
public struct HomeDemonstration: Sendable, Equatable {
    /// The heading over the demonstration.
    public let title: String
    /// The sentence under the heading.
    public let explanation: String
    /// The shortcut as separate caps — "⇧", "⌘", "V" — so they can be drawn as keys.
    public let keys: [String]
    /// What the panel shows while it is being demonstrated.
    public let rows: [HomeDemonstrationRow]
    /// Which row the demonstration picks, as an index into ``rows``; never the masked one.
    public let chosen: Int
    /// What the chosen row is typed into, so the demonstration ends somewhere: "a message".
    public let insertedInto: String
    /// The words already in that document, so the pasted text arrives after something.
    public let existingText: String
    /// The one line under it, saying where the real thing lives.
    public let footnote: String

    /// Builds the demonstration from its parts.
    public init(
        title: String, explanation: String, keys: [String], rows: [HomeDemonstrationRow],
        chosen: Int, insertedInto: String, existingText: String, footnote: String
    ) {
        self.title = title
        self.explanation = explanation
        self.keys = keys
        self.rows = rows
        self.chosen = chosen
        self.insertedInto = insertedInto
        self.existingText = existingText
        self.footnote = footnote
    }

    /// The row that gets pasted, or `nil` if `chosen` does not name one.
    public var chosenRow: HomeDemonstrationRow? {
        rows.indices.contains(chosen) ? rows[chosen] : nil
    }
}

/// One row of the demonstrated panel.
public struct HomeDemonstrationRow: Sendable, Equatable, Identifiable {
    /// The row's position in the demonstrated panel.
    public let id: Int
    /// The SF Symbol drawn beside the text.
    public let symbolName: String
    /// What the clip says.
    public let text: String
    /// Kind and age, as the real panel writes them.
    public let detail: String
    /// Whether this row is drawn as hidden, the way a password is in the real panel.
    public let isMasked: Bool

    /// Builds a row; unmasked unless said otherwise.
    public init(id: Int, symbolName: String, text: String, detail: String, isMasked: Bool = false) {
        self.id = id
        self.symbolName = symbolName
        self.text = text
        self.detail = detail
        self.isMasked = isMasked
    }
}

/// One dictation as home lists it, smaller than the Dictation page's row.
public struct HomeRow: Sendable, Equatable, Identifiable {
    /// The history entry this row shows.
    public let id: UUID
    /// The time the dictation happened, as the page writes it.
    public let when: String
    /// What was said.
    public let text: String
    /// The app it went into, when known.
    public let application: HistoryApplication?
    /// What clicking the row does.
    public let open: MainAction

    /// Builds a row from its parts.
    public init(
        id: UUID, when: String, text: String, application: HistoryApplication?, open: MainAction
    ) {
        self.id = id
        self.when = when
        self.text = text
        self.application = application
        self.open = open
    }
}

/// Everything the home page is drawn from.
public struct HomeSnapshot: Sendable, Equatable {
    /// Every permission the page cares about, with its current answer.
    public let permissions: [PermissionKind: PermissionStatus]
    /// Newest first, before retention is applied.
    public let entries: [HistoryEntry]
    /// The session on this Mac; absent when nobody has signed in.
    public let account: Account?
    /// The choice to work without an Uttrflow account; read only when ``account`` is absent.
    public let local: LocalAccount?
    /// The name macOS knows this person by; passed in so a test controls it.
    public let systemName: String?
    /// The dictation shortcut, already written out.
    public let shortcut: String
    /// The user's settings.
    public let settings: Settings
    /// The clock the page is drawn against.
    public let now: Date

    /// Builds a snapshot; everything but the shortcut and the clock defaults to empty.
    public init(
        permissions: [PermissionKind: PermissionStatus] = [:],
        entries: [HistoryEntry] = [],
        account: Account? = nil,
        local: LocalAccount? = nil,
        systemName: String? = nil,
        shortcut: String,
        settings: Settings = .default,
        now: Date
    ) {
        self.permissions = permissions
        self.entries = entries
        self.account = account
        self.local = local
        self.systemName = systemName
        self.shortcut = shortcut
        self.settings = settings
        self.now = now
    }
}

/// Turns everything Uttrflow knows into a page somebody can arrive at.
public enum HomePresenter {
    /// How many dictations home shows before sending the reader to History.
    static let shown = 5

    /// Draws the home page from a snapshot.
    public static func page(
        for snapshot: HomeSnapshot,
        calendar: Calendar = .autoupdatingCurrent,
        locale: Locale = .autoupdatingCurrent
    ) -> HomePresentation {
        let kept = HistoryPresenter.retained(
            snapshot.entries, days: snapshot.settings.transcriptRetentionDays, now: snapshot.now)
        let (today, earlier) = HistoryPresenter.todayAndEarlier(
            in: kept, now: snapshot.now, calendar: calendar)
        let blocked = MainPresenter.obstruction(in: snapshot.permissions)
        let listed = Array(kept.prefix(shown))

        return HomePresentation(
            greeting: greeting(for: snapshot, calendar: calendar),
            subtitle: subtitle(today: today, kept: kept, blocked: blocked != nil, locale: locale),
            // No figures while a permission is missing; numbers above "cannot listen" argue with themselves.
            figures: blocked == nil
                ? DictationPresenter.figures(
                    today: today, earlier: earlier, calendar: calendar, locale: locale)
                : [],
            recent: blocked == nil ? listed.map { row(for: $0, locale: locale) } : [],
            recentTitle: title(for: listed, calendar: calendar, now: snapshot.now),
            seeAll: kept.count > listed.count
                ? MainAction(title: "See all", intent: .show(.history)) : nil,
            nextStep: blocked ?? firstStep(kept: kept, shortcut: snapshot.shortcut),
            hint: hint(shortcut: snapshot.shortcut, settings: snapshot.settings),
            demonstration: blocked == nil ? demonstration(for: snapshot.settings) : nil,
            status: status(blocked: blocked != nil),
            account: account(for: snapshot))
    }

    // MARK: - Showing the clipboard rather than mentioning it

    /// The clipboard panel as something to look at; the rows are invented so no real clip is shown.
    static func demonstration(for settings: Settings) -> HomeDemonstration? {
        guard let shortcut = settings.clipboardHotkey else { return nil }
        return HomeDemonstration(
            title: "Everything you have copied, one shortcut away",
            explanation: """
                Uttrflow remembers what you copy, so the thing you had two copies ago is \
                still there. Passwords and card numbers are hidden until you ask for them.
                """,
            keys: SettingsShortcut.keycaps(for: shortcut),
            rows: [
                HomeDemonstrationRow(
                    id: 0, symbolName: "link", text: "uttrflow.com/download",
                    detail: "Link · just now"),
                HomeDemonstrationRow(
                    id: 1, symbolName: "key", text: "••••••••••••••••",
                    detail: "Password · 2 minutes ago", isMasked: true),
                HomeDemonstrationRow(
                    id: 2, symbolName: "text.alignleft",
                    text: "Flat 402, Example Residences, Bengaluru",
                    detail: "Text · 11 minutes ago"),
            ],
            // The address, not the password: pasting the masked row would teach that the mask is decorative.
            chosen: 2,
            insertedInto: "a message",
            existingText: "Sure — posting it now. My address is ",
            footnote: "Press it anywhere. Type to search, Return to paste.")
    }

    /// "Today", or "Recent" the moment the list reaches back past midnight.
    static func title(for listed: [HistoryEntry], calendar: Calendar, now: Date) -> String {
        let allToday =
            !listed.isEmpty
            && listed.allSatisfy { calendar.isDate($0.when, inSameDayAs: now) }
        return allToday ? "Today" : "Recent"
    }

    // MARK: - What to hold

    /// "Say it once — hold ⌥ Space anywhere on your Mac."; the verb follows how the shortcut is set up.
    static func hint(shortcut: String, settings: Settings) -> HomeHint {
        HomeHint(
            lead: settings.hotkeyActivation == .holdToTalk
                ? "Say it once — hold" : "Say it once — press",
            keys: caps(in: shortcut),
            trail: "anywhere on your Mac.")
    }

    /// "⌥Space" as ["⌥", "Space"]; modifiers alone yield no empty cap after them.
    static func caps(in shortcut: String) -> [String] {
        let glyphs: Set<Character> = ["⌃", "⌥", "⇧", "⌘"]
        let modifiers = shortcut.prefix { glyphs.contains($0) }.map(String.init)
        let key = shortcut.drop { glyphs.contains($0) }
        return key.isEmpty ? modifiers : modifiers + [String(key)]
    }

    // MARK: - Whether it can hear you

    /// Two states only, listening and not, since anything finer belongs on Diagnostics.
    static func status(blocked: Bool) -> HomeStatus {
        blocked
            ? HomeStatus(text: "Not listening", isReady: false)
            : HomeStatus(text: "Listening · ready", isReady: true)
    }

    // MARK: - Who is here

    /// The initials in the corner, from the account's name, then the Mac's, never invented.
    static func account(for snapshot: HomeSnapshot) -> HomeAccount {
        guard let account = snapshot.account else {
            guard let local = snapshot.local else {
                // Straight to signing in, because that is what the chip says.
                return .signedOut(open: MainAction(title: "Sign in", intent: .signIn))
            }
            // The Mac's own name, which the person chose; opens the Account page.
            let shown = local.name ?? "This Mac"
            return .onThisMac(
                initials: monogram(of: shown), name: firstWord(of: shown),
                open: MainAction(title: "Account", intent: .show(.account)))
        }

        // The Account page's own name for them, so the corner never shows somebody the page does not.
        let shown = AccountPagePresenter.identity(for: account).name

        return .signedIn(
            initials: monogram(of: shown), name: firstWord(of: shown),
            open: MainAction(title: "Account", intent: .show(.account)))
    }

    /// First and last initials — "Naveen Kumar Bhatt" is NB — and "?" for a name with no letters.
    static func monogram(of name: String) -> String {
        let names = name.split(separator: " ")
        guard let first = names.first else { return "?" }
        let taken = names.count > 1 ? [first, names[names.count - 1]] : [first]
        let letters = taken.compactMap(\.first).map(String.init).joined().uppercased()
        return letters.isEmpty ? "?" : letters
    }

    /// The first word of the name, because the chip is a greeting and not a directory entry.
    static func firstWord(of name: String) -> String {
        name.split(separator: " ").first.map(String.init) ?? name
    }

    // MARK: - Saying hello

    /// "Good morning, Naveen"; the name is the account's, else the Mac's, and never invented.
    static func greeting(for snapshot: HomeSnapshot, calendar: Calendar) -> String {
        let name = (snapshot.account?.displayName ?? snapshot.systemName)?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let hour = calendar.component(.hour, from: snapshot.now)
        let timeOfDay =
            switch hour {
            case 5..<12: "Good morning"
            case 12..<18: "Good afternoon"
            default: "Good evening"
            }
        guard let name, !name.isEmpty else { return timeOfDay }
        // The first name only. "Good morning, Naveen Bhatt" is a form letter.
        return "\(timeOfDay), \(firstWord(of: name))"
    }

    /// One sentence saying where things stand today.
    static func subtitle(
        today: [HistoryEntry], kept: [HistoryEntry], blocked: Bool, locale: Locale
    ) -> String {
        if blocked { return "Uttrflow cannot listen yet." }
        if kept.isEmpty { return "Nothing dictated yet. Hold the shortcut anywhere and talk." }
        guard !today.isEmpty else {
            return "Nothing yet today. Your words from earlier are still here."
        }
        let words = today.totalWords
        // Both halves counted, so "1 dictation today, 1 words" cannot appear.
        return """
            \(MainFormatting.count(today.count, "dictation", "dictations")) today, \
            \(words == 1 ? "1 word" : "\(words.formatted(.number.locale(locale))) words").
            """
    }

    // MARK: - One dictation

    /// One dictation as a home row whose action copies its text.
    static func row(for entry: HistoryEntry, locale: Locale) -> HomeRow {
        HomeRow(
            id: entry.id,
            when: MainFormatting.time(entry.when, locale: locale),
            text: entry.text,
            application: HistoryPresenter.application(for: entry),
            // Copying is what people want from a glance; everything else is on the page this row leads to.
            open: MainAction(title: "Copy", symbolName: "doc.on.doc", intent: .copy(entry.text)))
    }

    // MARK: - What to do next

    /// The one thing worth doing, offered only to somebody who has never dictated.
    static func firstStep(kept: [HistoryEntry], shortcut: String) -> MainEmptyState? {
        guard kept.isEmpty else { return nil }
        return MainEmptyState(
            symbolName: "mic",
            title: "Try it now",
            message: """
                Hold \(shortcut) anywhere on your Mac and say something. Uttrflow types it \
                where your cursor is — this window does not need to be open.
                """,
            footnote: "Nothing is uploaded. The words never leave this Mac.")
    }
}
