import Foundation
import UttrflowAccount
import UttrflowCore
import UttrflowHistory
import UttrflowSettings
import Testing

@testable import UttrflowUX

extension HistoryFixture {
    static func home(
        permissions: [PermissionKind: PermissionStatus] = [
            .microphone: .granted, .accessibility: .granted,
        ],
        entries: [HistoryEntry] = [],
        account: Account? = nil,
        local: LocalAccount? = nil,
        systemName: String? = nil,
        shortcut: String = "⌥Space",
        settings: Settings = .default,
        at moment: Date = HistoryFixture.now
    ) -> HomePresentation {
        HomePresenter.page(
            for: HomeSnapshot(
                permissions: permissions, entries: entries, account: account, local: local,
                systemName: systemName, shortcut: shortcut, settings: settings, now: moment),
            calendar: calendar, locale: locale)
    }

    /// The same day as `now`, at a chosen hour, so a greeting can be pinned.
    static func atHour(_ hour: Int) -> Date {
        calendar.date(bySettingHour: hour, minute: 30, second: 0, of: now) ?? now
    }
}

@Suite("Arriving at Uttrflow")
struct HomeGreetingTests {
    @Test("greets by the account's name when there is an account")
    func accountName() {
        let page = HistoryFixture.home(
            account: HistoryFixture.account(name: "Naveen Bhatt"),
            systemName: "Somebody Else",
            at: HistoryFixture.atHour(9))
        #expect(page.greeting == "Good morning, Naveen")
    }

    /// The Mac's own name for this person, used when there is no account. Not invented —
    /// it is their name for themselves, and it never leaves the machine.
    @Test("falls back to the name macOS knows")
    func systemName() {
        let page = HistoryFixture.home(systemName: "Naveen Bhatt", at: HistoryFixture.atHour(15))
        #expect(page.greeting == "Good afternoon, Naveen")
    }

    /// With no name at all the greeting simply ends. "Good evening, friend" is the kind of
    /// warmth that makes a product feel like it is performing at you.
    @Test("says hello without a name rather than inventing one")
    func noName() {
        #expect(HistoryFixture.home(at: HistoryFixture.atHour(21)).greeting == "Good evening")
        #expect(
            HistoryFixture.home(systemName: "  ", at: HistoryFixture.atHour(21)).greeting
                == "Good evening")
    }

    /// "Good morning, Naveen Bhatt" is a form letter.
    @Test("uses the first name only")
    func firstNameOnly() {
        let page = HistoryFixture.home(
            account: HistoryFixture.account(name: "Naveen Kumar Bhatt"),
            at: HistoryFixture.atHour(7))
        #expect(page.greeting == "Good morning, Naveen")
    }

    @Test(
        "the time of day is the one it actually is",
        arguments: [(6, "Good morning"), (13, "Good afternoon"), (19, "Good evening"), (2, "Good evening")]
    )
    func timeOfDay(hour: Int, expected: String) {
        #expect(HistoryFixture.home(at: HistoryFixture.atHour(hour)).greeting == expected)
    }
}

@Suite("What home says is going on")
struct HomeSubtitleTests {
    @Test("counts today's dictations and words")
    func today() {
        let page = HistoryFixture.home(entries: [
            HistoryFixture.entry("one two three"), HistoryFixture.entry("four five"),
        ])
        #expect(page.subtitle == "2 dictations today, 5 words.")
    }

    @Test("a quiet day says so without pretending the history is empty")
    func quietDay() {
        let page = HistoryFixture.home(entries: [HistoryFixture.entry("earlier", daysAgo: 2)])
        #expect(page.subtitle == "Nothing yet today. Your words from earlier are still here.")
    }

    @Test("a brand new install is told what to do")
    func nothingEver() {
        let page = HistoryFixture.home()
        #expect(page.subtitle == "Nothing dictated yet. Hold the shortcut anywhere and talk.")
        #expect(page.nextStep?.title == "Try it now")
        #expect(page.nextStep?.message.contains("⌥Space") == true)
    }

    /// A page that keeps suggesting first steps to somebody three months in is a page they
    /// stop reading.
    @Test("somebody who has dictated is not told how to start")
    func noStepOnceStarted() {
        #expect(HistoryFixture.home(entries: [HistoryFixture.entry("said something")]).nextStep == nil)
    }
}

@Suite("Home when Uttrflow cannot listen")
struct HomeBlockedTests {
    /// Figures about dictating, above a notice saying dictation cannot happen, read as a
    /// product arguing with itself.
    @Test("a missing permission replaces the figures rather than sitting under them")
    func blocked() {
        let page = HistoryFixture.home(
            permissions: [.microphone: .denied, .accessibility: .granted],
            entries: [HistoryFixture.entry("said something")])
        #expect(page.figures.isEmpty)
        #expect(page.recent.isEmpty)
        #expect(page.nextStep != nil)
        #expect(page.subtitle == "Uttrflow cannot listen yet.")
    }
}

@Suite("The few dictations home shows")
struct HomeRecentTests {
    @Test("shows the newest few and offers the rest")
    func showsAFew() {
        let entries = (0..<8).map { HistoryFixture.entry("dictation \($0)", minutesAgo: $0 * 5) }
        let page = HistoryFixture.home(entries: entries)
        #expect(page.recent.count == 5)
        #expect(page.recent.first?.text == "dictation 0")
        #expect(page.seeAll?.intent == .show(.history))
    }

    /// Nothing to send them to, so nothing offered. A "See all" that shows the same five
    /// is a button that teaches the user not to trust buttons.
    @Test("no see-all when everything is already on screen")
    func nothingMoreToSee() {
        let page = HistoryFixture.home(entries: [HistoryFixture.entry("only one")])
        #expect(page.recent.count == 1)
        #expect(page.seeAll == nil)
    }

    @Test("a row can be copied without leaving the page")
    func copying() throws {
        let page = HistoryFixture.home(entries: [HistoryFixture.entry("the words")])
        let row = try #require(page.recent.first)
        #expect(row.open.intent == .copy("the words"))
    }

    /// The retention promise is kept here as everywhere: home must not show a dictation
    /// the History page has already promised is deleted.
    @Test("anything past its retention is gone from home too")
    func retention() {
        let page = HistoryFixture.home(entries: [HistoryFixture.entry("ancient", daysAgo: 400)])
        #expect(page.recent.isEmpty)
        #expect(page.subtitle == "Nothing dictated yet. Hold the shortcut anywhere and talk.")
    }
}

@Suite("Showing the clipboard rather than mentioning it")
struct HomeDemonstrationTests {
    /// The clipboard has no window, no menu item and no button. It lives entirely behind
    /// a shortcut, so it is the one feature nobody finds without being shown.
    @Test("home demonstrates the clipboard, with the shortcut that opens it")
    func demonstrates() throws {
        let shown = try #require(HistoryFixture.home().demonstration)
        #expect(shown.keys == ["⇧", "⌘", "V"])
        #expect(shown.rows.count == 3)
        #expect(shown.footnote.contains("Type to search"))
    }

    /// Whatever the user last copied — a password, a customer's address — must not be put
    /// on the first screen of the app, animating, where anyone walking past can read it.
    /// The panel masks secrets for that reason and the demonstration must not undo it.
    @Test("the rows are illustrations, never the user's own clips")
    func neverTheirOwnClips() throws {
        let shown = try #require(HistoryFixture.home().demonstration)
        // Fixed, so no snapshot of a real clipboard can reach this page by any route.
        #expect(
            shown.rows.map(\.text) == [
                "uttrflow.com/download", "••••••••••••••••",
                "Flat 402, Example Residences, Bengaluru",
            ])
        #expect(shown.rows.contains { $0.isMasked })
    }

    /// A demonstration that stops when the panel closes teaches that a panel exists, not
    /// what it is for. The only part anybody cares about is the words arriving in what
    /// they were already writing.
    @Test("it ends with the words landing somewhere, not with a panel vanishing")
    func showsThePayoff() throws {
        let shown = try #require(HistoryFixture.home().demonstration)
        #expect(!shown.insertedInto.isEmpty)
        #expect(shown.existingText.hasSuffix(" "), "the paste should land after a space")
        #expect(shown.chosenRow != nil)
    }

    /// Showing a password being pasted would teach the wrong lesson twice over — that
    /// Uttrflow hands secrets out casually, and that the mask is decorative.
    @Test("the row it pastes is never the masked one")
    func neverPastesASecret() throws {
        let shown = try #require(HistoryFixture.home().demonstration)
        #expect(shown.chosenRow?.isMasked == false)
    }

    /// It reads the shortcut rather than naming one, so somebody who has changed theirs
    /// is not taught the wrong keys.
    @Test("it shows the shortcut that is actually set")
    func readsTheRealShortcut() throws {
        let changed = Settings(clipboardHotkey: HotkeyBinding(keyCode: 9, modifiers: [.control]))
        let shown = try #require(HomePresenter.demonstration(for: changed))
        #expect(shown.keys == ["⌃", "V"])
    }

    /// Demonstrating a shortcut somebody has switched off is worse than silence.
    @Test("nothing is demonstrated when the shortcut is off")
    func offMeansOff() {
        #expect(HomePresenter.demonstration(for: Settings(clipboardHotkey: nil)) == nil)
    }

    /// A page telling somebody how to reach the clipboard, above a notice saying Uttrflow
    /// cannot hear them, is a page answering a question they have not got to yet.
    @Test("nothing is demonstrated while a permission is missing")
    func notWhileBlocked() {
        let page = HistoryFixture.home(permissions: [.microphone: .denied, .accessibility: .granted])
        #expect(page.demonstration == nil)
    }
}

@Suite("Whether it can hear you")
struct HomeStatusTests {
    /// The stage draws a microphone inside a lit ring. That picture is a claim, and this
    /// is the sentence that has to agree with it.
    @Test("says it is listening when nothing is in the way")
    func ready() {
        let page = HistoryFixture.home()

        #expect(page.status.isReady)
        #expect(page.status.text == "Listening · ready")
    }

    /// The same condition that empties the figures: numbers about dictating, over a ring
    /// claiming to listen, on a Mac that cannot, is a product arguing with itself.
    @Test("says it is not listening while the microphone is refused")
    func blocked() {
        let page = HistoryFixture.home(permissions: [
            .microphone: .denied, .accessibility: .granted,
        ])

        #expect(!page.status.isReady)
        #expect(page.status.text == "Not listening")
        #expect(page.figures.isEmpty, "the figures already go when dictation cannot happen")
    }
}

@Suite("Who is in the corner")
struct HomeAccountTests {
    @Test("takes the initials from the account's name")
    func fromAccount() {
        let corner = HistoryFixture.home(
            account: HistoryFixture.account(name: "Naveen Bhatt"),
            systemName: "Somebody Else"
        ).account

        #expect(corner == .signedIn(initials: "NB", name: "Naveen", open: .account))
    }

    /// The middle name is the one nobody uses, so it is the one the monogram drops.
    @Test("uses the first and last name, not the first two")
    func firstAndLast() {
        let corner = HistoryFixture.home(
            account: HistoryFixture.account(name: "Naveen Kumar Bhatt")
        ).account

        #expect(corner == .signedIn(initials: "NB", name: "Naveen", open: .account))
    }

    /// A monogram is a recognition aid. One letter recognises a person with one name
    /// perfectly well; inventing a second would be inventing part of their name.
    @Test("makes do with one letter when there is one name")
    func singleName() {
        let corner = HistoryFixture.home(
            account: HistoryFixture.account(name: "naveen")
        ).account

        #expect(corner == .signedIn(initials: "N", name: "naveen", open: .account))
    }

    /// The defect this suite exists for.
    ///
    /// The corner used to read the Mac owner's name when no account was there, so a
    /// signed-out window showed a filled teal "NB · Naveen" beside an Account page saying
    /// "Not signed in". The Mac's name is still right for the greeting — a hello is not a
    /// claim — and wrong for a control that means *signed in as*.
    @Test("offers the way in when nobody is signed in, whatever this Mac is called")
    func signedOut() {
        #expect(HistoryFixture.home().account == .signedOut(open: .signIn))
        #expect(
            HistoryFixture.home(systemName: "Naveen Bhatt").account == .signedOut(open: .signIn),
            "the Mac's owner is not evidence that anybody signed in")
    }

    /// The state the old signature could not even express: the account is present, so the
    /// person *is* signed in, but the provider sent no name. Falling back to the Mac's
    /// name here would be the same lie in a rarer costume.
    @Test("recognises a signed-in person the provider never named")
    func signedInWithoutAName() {
        let corner = HistoryFixture.home(
            account: HistoryFixture.account(name: nil, email: "naveen@example.com"),
            systemName: "Somebody Else"
        ).account

        #expect(corner == .signedIn(initials: "N", name: "naveen@example.com", open: .account))
    }

    /// An opaque identifier belongs to the right account, where a placeholder belongs to
    /// none — the choice the Account page already makes.
    @Test("falls back to the identifier rather than to a placeholder")
    func nothingButAnIdentifier() {
        let corner = HistoryFixture.home(
            account: HistoryFixture.account(name: nil, email: nil), systemName: "Naveen"
        ).account

        #expect(corner == .signedIn(initials: "A", name: "account-1", open: .account))
    }

    /// The Mac's name is a claim the corner may make once the person has made it: they
    /// chose to work as themselves on this Mac, so a monogram is the truth. It is drawn
    /// unfilled by the view, which is the part that says *not an Uttrflow account*.
    @Test("shows the Mac's owner once they have chosen to be one")
    func onThisMac() {
        let corner = HistoryFixture.home(
            local: LocalAccount(name: "Naveen Bhatt", since: HistoryFixture.now),
            systemName: "Naveen Bhatt"
        ).account

        #expect(corner == .onThisMac(initials: "NB", name: "Naveen", open: .account))
        #expect(corner.open.intent == .show(.account), "there is a page there to open now")
    }

    /// The Mac's own name is still not evidence of anything on its own. Only the recorded
    /// choice is, which is why the chip reads the local account and not `systemName`.
    @Test("the Mac's name alone is still not an account")
    func systemNameIsNotAChoice() {
        #expect(HistoryFixture.home(systemName: "Naveen Bhatt").account == .signedOut(open: .signIn))
    }

    @Test("a Mac account with no name still draws something honest")
    func onThisMacWithNoName() {
        let corner = HistoryFixture.home(
            local: LocalAccount(name: nil, since: HistoryFixture.now)
        ).account

        #expect(corner == .onThisMac(initials: "TM", name: "This", open: .account))
    }

    /// The signed value wins here too, and for the same reason the Account page's does.
    @Test("a real account beats a Mac account in the corner")
    func accountBeatsLocal() {
        let corner = HistoryFixture.home(
            account: HistoryFixture.account(name: "Naveen Bhatt"),
            local: LocalAccount(name: "Somebody Else", since: HistoryFixture.now)
        ).account

        #expect(corner == .signedIn(initials: "NB", name: "Naveen", open: .account))
    }

    @Test("the chip leads to the Account page")
    func destination() {
        let corner = HistoryFixture.home(
            account: HistoryFixture.account(name: "Naveen Bhatt")
        ).account

        #expect(corner.open.intent == .show(.account))
    }

    /// Says "Sign in" and signs in. A control whose words and behaviour disagree is the
    /// same class of defect as a corner that claims a session there isn't.
    @Test("the signed-out chip does what it says")
    func signedOutDestination() {
        #expect(HistoryFixture.home().account.open.intent == .signIn)
        #expect(HistoryFixture.home().account.open.title == "Sign in")
    }
}

extension MainAction {
    fileprivate static let account = MainAction(title: "Account", intent: .show(.account))
    fileprivate static let signIn = MainAction(title: "Sign in", intent: .signIn)
}

@Suite("What to hold")
struct HomeHintTests {
    /// Drawn as keys rather than as two more words in the middle of a sentence, which is
    /// why the parts are separate at all.
    @Test("takes the shortcut apart into caps")
    func caps() {
        let hint = HistoryFixture.home(shortcut: "⌥Space").hint

        #expect(hint.lead == "Say it once — hold")
        #expect(hint.keys == ["⌥", "Space"])
        #expect(hint.trail == "anywhere on your Mac.")
        #expect(hint.sentence == "Say it once — hold ⌥Space anywhere on your Mac.")
    }

    @Test("gives every modifier a cap of its own")
    func modifiers() {
        #expect(HistoryFixture.home(shortcut: "⇧⌘V").hint.keys == ["⇧", "⌘", "V"])
        #expect(HistoryFixture.home(shortcut: "⌃⌥⇧⌘K").hint.keys == ["⌃", "⌥", "⇧", "⌘", "K"])
    }

    /// A stored setting could hold one even though the recorder refuses it, and an empty
    /// cap on the end of the row would look like a missing key rather than none.
    @Test("does not draw an empty cap for a shortcut of modifiers alone")
    func modifiersAlone() {
        #expect(HistoryFixture.home(shortcut: "⌥").hint.keys == ["⌥"])
    }

    /// Telling somebody to hold a key they have set to toggle is an instruction that
    /// does not work.
    @Test("the verb follows how the shortcut is set up")
    func verbFollowsActivation() {
        var settings = Settings.default
        settings.hotkeyActivation = .pressToToggle

        #expect(HistoryFixture.home(settings: settings).hint.lead == "Say it once — press")
    }
}

@Suite("What the list under the figures is called")
struct HomeRecentTitleTests {
    /// The design draws "Today", and on the day it was drawn every row was from today.
    @Test("says Today when every row is")
    func allFromToday() {
        let page = HistoryFixture.home(entries: [
            HistoryFixture.entry("Morning", minutesAgo: 30),
            HistoryFixture.entry("Earlier", minutesAgo: 90),
        ])

        #expect(page.recentTitle == "Today")
    }

    /// A morning with nothing said yet still lists yesterday's sentences, and a heading
    /// reading "Today" would be sitting over words from before midnight.
    @Test("says Recent once the list reaches back past midnight")
    func reachingBack() {
        let page = HistoryFixture.home(entries: [
            HistoryFixture.entry("Yesterday evening", daysAgo: 1)
        ])

        #expect(page.recentTitle == "Recent")
    }

    @Test("says Recent when there is nothing in the list at all")
    func empty() {
        #expect(HistoryFixture.home().recentTitle == "Recent")
    }
}

@Suite("The line under the greeting counts properly")
struct HomeSubtitleCountTests {
    /// "1 dictation today, 1 words" is the sort of sentence that makes somebody distrust
    /// every number around it.
    @Test("says one word rather than one words")
    func singleWord() {
        let page = HistoryFixture.home(entries: [HistoryFixture.entry("Gracias", minutesAgo: 5)])

        #expect(page.subtitle == "1 dictation today, 1 word.")
    }

    @Test("counts both halves in the plural when there are more")
    func several() {
        let page = HistoryFixture.home(entries: [
            HistoryFixture.entry("one two three", minutesAgo: 5),
            HistoryFixture.entry("four five", minutesAgo: 8),
        ])

        #expect(page.subtitle == "2 dictations today, 5 words.")
    }
}
