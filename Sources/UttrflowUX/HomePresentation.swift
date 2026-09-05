public import Foundation
public import UttrflowAccount
public import UttrflowCore
public import UttrflowHistory
public import UttrflowSettings

/// What the home page shows.
///
/// The one page that is about the person using Uttrflow rather than about a feature. It
/// invents nothing: every figure and every row on it is drawn from the same values the
/// pages behind it use, and anything without a source is left off rather than filled in.
public struct HomePresentation: Sendable, Equatable {
    /// "Good morning, Naveen" — or just "Good morning" when there is no name to use.
    public let greeting: String
    /// One sentence under the greeting saying where things stand.
    public let subtitle: String
    /// The big figures, across the top.
    public let figures: [MainStatistic]
    /// The last few dictations, newest first. Empty on a quiet day.
    public let recent: [HomeRow]
    /// What to call that list: "Today" when everything in it is from today, and "Recent"
    /// when it has reached back into yesterday.
    ///
    /// The heading has to follow the rows rather than the page: this list shows the last
    /// few dictations whenever they were, so on a morning with nothing said yet a
    /// heading reading "Today" would be sitting over yesterday's sentences.
    public let recentTitle: String
    /// Where the whole list lives, offered only when there is more than is shown.
    public let seeAll: MainAction?
    /// The one thing worth doing next, when there is one — a permission to grant, a
    /// first dictation to make. Absent when nothing is outstanding.
    public let nextStep: MainEmptyState?
    /// The line under the greeting, in parts, so the shortcut can be drawn as keys.
    public let hint: HomeHint
    /// The clipboard, shown working. Absent when the user has turned its shortcut off,
    /// because demonstrating a shortcut somebody has switched off is worse than silence.
    public let demonstration: HomeDemonstration?
    /// Whether Uttrflow can hear you, said in words above the greeting.
    public let status: HomeStatus
    /// Who is signed in, and the way to the page about them.
    ///
    /// Always present, because there is always something true to put in the corner: a
    /// monogram when somebody is signed in, and the way to sign in when nobody is. It was
    /// optional while "no name" was the only state the corner could describe, and an
    /// empty corner is what a signed-out window used to deserve — but a signed-out window
    /// that offers no way in is a worse answer than an honest one.
    public let account: HomeAccount

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

/// The line under the greeting, kept in three parts.
///
/// One sentence would have been simpler and would have drawn the shortcut as words in
/// the middle of a sentence — "hold ⌥Space anywhere" — where it reads as punctuation
/// rather than as the keys somebody has to find. Splitting it here rather than in the
/// view keeps the wording testable and stops the page inventing sentences of its own.
public struct HomeHint: Sendable, Equatable {
    public let lead: String
    /// The shortcut as separate caps — "⌥", "Space" — so they can be drawn as keys.
    public let keys: [String]
    public let trail: String

    public init(lead: String, keys: [String], trail: String) {
        self.lead = lead
        self.keys = keys
        self.trail = trail
    }

    /// The whole line as one sentence, for anything that cannot draw a key: a screen
    /// reader, and the menu bar.
    public var sentence: String {
        "\(lead) \(keys.joined()) \(trail)"
    }
}

/// Whether Uttrflow is able to listen, in the words shown above the greeting.
///
/// The home page draws a microphone at the middle of a ring, which is a promise. This is
/// what keeps the promise honest: on a Mac where the microphone was never allowed, the
/// ring must not sit there claiming to be listening. It is one sentence rather than a
/// colour, because a lit ring means nothing to somebody who cannot see the difference.
public struct HomeStatus: Sendable, Equatable {
    public let text: String
    /// Whether the ring is drawn lit. False while anything at all stops a dictation
    /// starting, which is the same condition that empties the figures.
    public let isReady: Bool

    public init(text: String, isReady: Bool) {
        self.text = text
        self.isReady = isReady
    }
}

/// The person, as the way into the page about them.
///
/// Account is the page somebody visits twice a year — once to sign in and once to check
/// what they are paying for — which makes hunting for it in the sidebar a small tax on
/// every visit. Their own initials in the corner is where every other Mac app has taught
/// them to look.
public enum HomeAccount: Sendable, Equatable {
    /// Somebody is signed in.
    ///
    /// `initials` is one letter, or two when there are two names to take them from. Never
    /// three: a monogram is a recognition aid, not an abbreviation of the whole name.
    /// `name` is the first name, shown beside them.
    case signedIn(initials: String, name: String, open: MainAction)

    /// Nobody is signed in, so the corner offers the way in rather than a monogram.
    ///
    /// It used to fall back to the name macOS knows this Mac's owner by, which drew a
    /// filled avatar and "Naveen" in the corner of a window whose Account page said "Not
    /// signed in". The name was real; the claim the chip made with it was not. A monogram
    /// beside a chevron is how every Mac app says *you are signed in as this person*, and
    /// it has to mean that here or it means nothing anywhere.
    case signedOut(open: MainAction)

    /// Nobody is signed in, and nobody needs to be: this person chose to work on this
    /// Mac — see ``LocalAccount``.
    ///
    /// Its own case rather than ``signedIn`` with the Mac's name in it, which is the
    /// exact bug this enumeration was split up to stop. The monogram is honest here
    /// because there really is an account behind it; it is drawn unfilled because the
    /// account is this Mac and not an Uttrflow one, and the corner should not make those
    /// look like the same thing.
    case onThisMac(initials: String, name: String, open: MainAction)

    /// Where the chip goes, whichever state it is in.
    public var open: MainAction {
        switch self {
        case .signedIn(_, _, let open), .onThisMac(_, _, let open), .signedOut(let open): open
        }
    }
}

/// A feature shown working, rather than described.
///
/// The clipboard is the thing in Uttrflow nobody discovers on their own: it has no window
/// of its own, no menu item that opens it, and it lives entirely behind a shortcut. A
/// sentence saying "press ⇧⌘V" is a sentence people read and forget. A picture of the
/// panel appearing when those keys are pressed is a thing they recognise the next time
/// they want it.
///
/// The text is here and the movement is the view's, so what it *says* stays testable.
public struct HomeDemonstration: Sendable, Equatable {
    public let title: String
    public let explanation: String
    /// The shortcut as separate caps — "⇧", "⌘", "V" — so they can be drawn as keys.
    public let keys: [String]
    /// What the panel shows while it is being demonstrated.
    public let rows: [HomeDemonstrationRow]
    /// Which row the demonstration picks, as an index into ``rows``.
    ///
    /// Never the masked one. Showing a password being pasted would teach the wrong lesson
    /// twice over — that Uttrflow hands secrets out casually, and that the mask is
    /// decorative.
    public let chosen: Int
    /// What the chosen row is typed into, so the demonstration ends somewhere rather than
    /// with a panel vanishing: "a message", "your email".
    public let insertedInto: String
    /// The words already in that document, so the pasted text arrives after something
    /// rather than into a void.
    public let existingText: String
    /// The one line under it, saying where the real thing lives.
    public let footnote: String

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
    public let id: Int
    public let symbolName: String
    public let text: String
    public let detail: String
    /// Whether this row is drawn as hidden, the way a password is in the real panel.
    public let isMasked: Bool

    public init(id: Int, symbolName: String, text: String, detail: String, isMasked: Bool = false) {
        self.id = id
        self.symbolName = symbolName
        self.text = text
        self.detail = detail
        self.isMasked = isMasked
    }
}

/// One dictation, as home lists it. Deliberately smaller than the Dictation page's row:
/// this is a glance, and the page that does the work is one click away.
public struct HomeRow: Sendable, Equatable, Identifiable {
    public let id: UUID
    public let when: String
    public let text: String
    public let application: HistoryApplication?
    public let open: MainAction

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
    public let permissions: [PermissionKind: PermissionStatus]
    /// Newest first, before retention is applied.
    public let entries: [HistoryEntry]
    /// The session on this Mac. Absent when nobody has signed in.
    ///
    /// The account itself rather than a name off it, and the same value
    /// ``AccountPageSnapshot/entitlement`` is drawn from. The corner used to be handed a
    /// name, which cannot tell "nobody is signed in" apart from "somebody is, whose
    /// provider never told us what to call them" — so it answered both with the Mac
    /// owner's name and contradicted the Account page.
    public let account: Account?
    /// The choice to work without an Uttrflow account, when somebody made it. Read only
    /// when ``account`` is absent, for the reason ``AccountPageSnapshot/local`` is.
    public let local: LocalAccount?
    /// The name macOS knows this person by, used when there is no account. Passed in
    /// rather than read here, because a presenter that reached for `NSFullUserName()`
    /// would be a presenter that behaves differently in a test than in the product.
    public let systemName: String?
    public let shortcut: String
    public let settings: Settings
    public let now: Date

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
    ///
    /// Five. Enough to recognise the morning's work, few enough that the figures above
    /// them stay the point of the page.
    static let shown = 5

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
            // No figures while a permission is missing: numbers about dictating, above a
            // notice saying dictation cannot happen, read as a product arguing with
            // itself.
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

    /// The clipboard panel, as something to look at.
    ///
    /// The rows are made up, deliberately. Drawing the *user's* own clips here would put
    /// whatever they last copied — a password, a customer's address — on the first screen
    /// of the app, animating, where anyone walking past can read it. The panel masks
    /// secrets for exactly that reason and a demonstration must not undo it. These three
    /// are chosen to show the three things the panel does that a plain clipboard does
    /// not: it keeps more than one, it knows what kind of thing each is, and it hides
    /// what should be hidden.
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
            // The address, not the password. A demonstration that pasted the masked row
            // would teach that the mask is decorative.
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

    /// "Say it once — hold ⌥ Space anywhere on your Mac."
    ///
    /// The promise first and the mechanism second, because the promise is the reason
    /// anybody would learn the mechanism. The verb follows how the shortcut is set up:
    /// telling somebody to hold a key they have set to toggle is an instruction that
    /// does not work.
    static func hint(shortcut: String, settings: Settings) -> HomeHint {
        HomeHint(
            lead: settings.hotkeyActivation == .holdToTalk
                ? "Say it once — hold" : "Say it once — press",
            keys: caps(in: shortcut),
            trail: "anywhere on your Mac.")
    }

    /// "⌥Space" as ["⌥", "Space"].
    ///
    /// The snapshot carries the shortcut already written out, so this reads the caps back
    /// off it rather than asking for the binding a second time: the leading glyphs are
    /// the modifiers, one cap each, and whatever follows is the key. A shortcut of
    /// modifiers alone — which the recorder refuses, but which a stored setting could
    /// still hold — yields the modifiers and no empty cap after them.
    static func caps(in shortcut: String) -> [String] {
        let glyphs: Set<Character> = ["⌃", "⌥", "⇧", "⌘"]
        let modifiers = shortcut.prefix { glyphs.contains($0) }.map(String.init)
        let key = shortcut.drop { glyphs.contains($0) }
        return key.isEmpty ? modifiers : modifiers + [String(key)]
    }

    // MARK: - Whether it can hear you

    /// Two states, not three. "Listening" and "not listening" are the only distinctions a
    /// person can act on from this page; anything finer belongs on Diagnostics, which is
    /// where the notice under the greeting already sends them.
    static func status(blocked: Bool) -> HomeStatus {
        blocked
            ? HomeStatus(text: "Not listening", isReady: false)
            : HomeStatus(text: "Listening · ready", isReady: true)
    }

    // MARK: - Who is here

    /// The initials in the corner, from whatever name Uttrflow already has.
    ///
    /// The account's name first, the Mac's second, and nothing at all if there is neither
    /// — the same order and the same refusal to invent as the greeting. A monogram made
    /// up for somebody who never told us their name would be a stranger's initials in
    /// their own window.
    static func account(for snapshot: HomeSnapshot) -> HomeAccount {
        guard let account = snapshot.account else {
            guard let local = snapshot.local else {
                // Straight to signing in, because that is what the chip now says. Sending
                // it to the Account page instead would be a control whose words and
                // behaviour disagree, which is the class of bug this whole change is
                // about.
                return .signedOut(open: MainAction(title: "Sign in", intent: .signIn))
            }
            // The Mac's own name, and this time the chip may say so: the person told us
            // this is who they are. It opens the Account page, because unlike the
            // signed-out chip there is now a page there with something on it.
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

    /// The letters in the circle: first and last, so "Naveen Kumar Bhatt" is NB rather
    /// than NK — the middle name is the one nobody uses.
    ///
    /// A question mark for a name with no letters in it at all. Two chip states derive
    /// this now, and deriving it twice is how they would come to differ.
    static func monogram(of name: String) -> String {
        let names = name.split(separator: " ")
        guard let first = names.first else { return "?" }
        let taken = names.count > 1 ? [first, names[names.count - 1]] : [first]
        let letters = taken.compactMap(\.first).map(String.init).joined().uppercased()
        return letters.isEmpty ? "?" : letters
    }

    /// The name beside the circle. The first word of it, because the chip is a greeting
    /// and not a directory entry.
    static func firstWord(of name: String) -> String {
        name.split(separator: " ").first.map(String.init) ?? name
    }

    // MARK: - Saying hello

    /// "Good morning, Naveen".
    ///
    /// The name is the account's if there is one and the Mac's otherwise, and neither is
    /// invented: both are this person's own name for themselves. With no name at all the
    /// greeting simply ends, rather than falling back to something like "friend".
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

    static func subtitle(
        today: [HistoryEntry], kept: [HistoryEntry], blocked: Bool, locale: Locale
    ) -> String {
        if blocked { return "Uttrflow cannot listen yet." }
        if kept.isEmpty { return "Nothing dictated yet. Hold the shortcut anywhere and talk." }
        guard !today.isEmpty else {
            return "Nothing yet today. Your words from earlier are still here."
        }
        let words = today.totalWords
        // Both halves counted rather than one: "1 dictation today, 1 words" is the sort
        // of sentence that makes a person distrust the numbers around it.
        return """
            \(MainFormatting.count(today.count, "dictation", "dictations")) today, \
            \(words == 1 ? "1 word" : "\(words.formatted(.number.locale(locale))) words").
            """
    }

    // MARK: - One dictation

    static func row(for entry: HistoryEntry, locale: Locale) -> HomeRow {
        HomeRow(
            id: entry.id,
            when: MainFormatting.time(entry.when, locale: locale),
            text: entry.text,
            application: HistoryPresenter.application(for: entry),
            // Copying is the thing people want from a glance; everything else is on the
            // page this row leads to.
            open: MainAction(title: "Copy", symbolName: "doc.on.doc", intent: .copy(entry.text)))
    }

    // MARK: - What to do next

    /// The one thing worth doing, when there is one.
    ///
    /// Only ever offered to somebody who has never dictated. A page that keeps suggesting
    /// next steps to a user three months in is a page they stop reading.
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
