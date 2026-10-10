// Tests for the Account page: the Mac account, identity, facts, notices, and the signed-out page.
import Foundation
import UttrflowAccount
import Testing

@testable import UttrflowUX

extension HistoryFixture {
    /// An account with a fixed identifier; the name and address default to invented ones.
    static func account(
        name: String? = "Avery Stone",
        email: String? = "nadia.d@example.com",
        provider: SignInProvider = .google
    ) -> Account {
        Account(
            identifier: "account-1", displayName: name, emailAddress: email, provider: provider)
    }

    /// The Account page over these inputs.
    static func accountPage(
        account: Account? = HistoryFixture.account(),
        plan: Plan = .free,
        access: DictationAccess = .allowed,
        picture: Data? = nil,
        memberSince: Date? = nil,
        macName: String? = nil
    ) -> AccountPagePresentation {
        AccountPagePresenter.page(
            for: AccountPageSnapshot(
                entitlement: account.map {
                    Entitlement(
                        account: $0, plan: plan,
                        expiresAt: now.addingTimeInterval(86_400), signature: "signed")
                },
                access: access, now: now, picture: picture,
                memberSince: memberSince, macName: macName),
            locale: locale)
    }
}

@Suite("Account: who is signed in")
struct AccountIdentityTests {
    @Test("the name, the address and the provider are shown")
    func identity() {
        let identity = HistoryFixture.accountPage().identity
        #expect(identity?.name == "Avery Stone")
        #expect(identity?.emailAddress == "nadia.d@example.com")
        #expect(identity?.provider == "Google")
        #expect(identity?.providerID == .google)
    }

    /// A stock silhouette tells the user nothing about which of their accounts this is.
    @Test("the circle carries the initials of the name")
    func initials() {
        #expect(HistoryFixture.accountPage().identity?.initials == "A")
        #expect(AccountPagePresenter.initials(of: "Ada Byron Lovelace") == "A")
        // "PR" would read as a company; one name gives one initial.
        #expect(AccountPagePresenter.initials(of: "Prince") == "P")
    }

    /// "a.d" is not initials and "@" is not a letter, so an address contributes one letter.
    @Test("an address contributes only its first letter")
    func initialsFromAnAddress() {
        #expect(AccountPagePresenter.initials(of: "nadia.d@example.com") == "N")
        #expect(AccountPagePresenter.initials(of: "") == "?")
        #expect(AccountPagePresenter.initials(of: nil) == "?")
        #expect(AccountPagePresenter.initials(of: "123 456") == "?")
    }

    @Test("a provider that gave no name falls back to the address")
    func noName() {
        let identity = HistoryFixture.accountPage(
            account: HistoryFixture.account(name: nil)
        ).identity
        #expect(identity?.name == "nadia.d@example.com")
        // Not repeated underneath the name it has just become.
        #expect(identity?.emailAddress == nil)
    }

    /// An opaque identifier belongs to the right account, where a placeholder belongs to none.
    @Test("an account with neither name nor address is named by its identifier")
    func neither() {
        let identity = HistoryFixture.accountPage(
            account: HistoryFixture.account(name: nil, email: nil)
        ).identity
        #expect(identity?.name == "account-1")
        #expect(identity?.initials == "?")
    }

    /// A provider may hand over a name and no address, and the card must not draw an empty line.
    @Test("a name with no address shows the name alone")
    func nameWithoutAnAddress() {
        let identity = HistoryFixture.accountPage(
            account: HistoryFixture.account(email: nil)
        ).identity
        #expect(identity?.name == "Avery Stone")
        #expect(identity?.emailAddress == nil)
    }

    @Test("a blank name is no name at all")
    func blankName() {
        let identity = HistoryFixture.accountPage(
            account: HistoryFixture.account(name: "   ")
        ).identity
        #expect(identity?.name == "nadia.d@example.com")
    }

    /// Getting a company's name wrong on the screen that names it costs trust for free.
    @Test("each provider is named the way it names itself")
    func providers() {
        #expect(AccountPagePresenter.title(for: .google) == "Google")
        #expect(AccountPagePresenter.title(for: .gitHub) == "GitHub")
        #expect(AccountPagePresenter.title(for: .apple) == "Apple")
        for provider in SignInProvider.allCases {
            #expect(!AccountPagePresenter.title(for: provider).isEmpty)
        }
    }
}

@Suite("Account: the facts under the banner")
struct AccountFactsTests {
    /// The same person the other suites draw, with every fact known.
    static let everything = HistoryFixture.accountPage(
        account: HistoryFixture.account(name: "Ada Byron", email: "ada@example.com"),
        memberSince: Date(timeIntervalSince1970: 1_785_571_200), macName: "Ada's MacBook Pro")

    @Test("email, provider, member since and this Mac, in that order")
    func allFour() {
        let facts = Self.everything.facts
        #expect(facts.map(\.label) == ["Email", "Signed in with", "Member since", "This Mac"])
        #expect(facts.map(\.value) == ["ada@example.com", "Google", "1 Aug 2026", "Ada's MacBook Pro"])
        #expect(facts.map(\.id) == [.email, .signIn, .since, .thisMac])
    }

    /// Only the profile records a creation date, so without one the row is left out rather than invented.
    @Test("no creation date means no member-since row")
    func noInventedDate() {
        let page = HistoryFixture.accountPage()
        #expect(!page.facts.contains { $0.kind == .since })
        #expect(page.facts.first { $0.kind == .signIn }?.value == "Google")
    }

    @Test("a missing or blank address and a blank Mac name leave their rows out")
    func unknownsAreLeftOut() {
        let page = HistoryFixture.accountPage(
            account: HistoryFixture.account(email: "  "), macName: " ")
        #expect(page.facts.map(\.kind) == [.signIn])
        #expect(
            HistoryFixture.accountPage(account: HistoryFixture.account(email: nil)).facts.map(\.kind)
                == [.signIn])
    }

    @Test("each provider names itself on the sign-in row")
    func providerRow() {
        let page = HistoryFixture.accountPage(account: HistoryFixture.account(provider: .gitHub))
        #expect(page.facts.first { $0.kind == .signIn }?.value == "GitHub")
    }

    /// The plan is not shown, so the page cannot disagree with the signed entitlement about it.
    @Test("claims no plan")
    func noPlan() {
        let wording = HistoryFixture.accountPage(plan: .pro).facts.map(\.value)
        #expect(!wording.contains("Pro"))
    }

    @Test("the one button signs out, in red, and says what it keeps")
    func signOut() {
        let page = Self.everything
        #expect(page.action?.intent == .signOut)
        #expect(page.action?.title == "Sign out")
        #expect(page.action?.isDestructive == true)
        #expect(page.action?.symbolName != nil)
        #expect(page.actionHelp == AccountPagePresenter.signOutHelp)
        #expect(page.actionHelp?.contains("stay on this Mac") == true)
    }

    @Test("deleting the account sits beside signing out, in red, and asks first")
    func deletion() {
        let page = Self.everything
        #expect(page.deletion?.intent == .deleteAccount)
        #expect(page.deletion?.isDestructive == true)
        #expect(page.deletion?.confirmation == .deleteAccount)
        #expect(AccountPagePresenter.deletionHelp.contains("stay on this Mac"))
        #expect(HistoryFixture.accountPage(account: nil).deletion == nil)
    }

    /// The question an account on this product invites, answered beside the invitation to sign in.
    @Test("the promise about local data is kept for the invitation")
    func promise() {
        let page = HistoryFixture.accountPage()
        #expect(page.callout.message == AccountPagePresenter.localDataPromise)
        #expect(page.callout.message.contains("signing out leaves every one of them"))
        #expect(page.callout.tone == .good)
    }

    @Test("a day is written the reader's way")
    func since() {
        let day = Date(timeIntervalSince1970: 1_785_571_200)
        #expect(AccountPagePresenter.since(day, locale: Locale(identifier: "en_GB")) == "1 Aug 2026")
    }
}

@Suite("Account when the subscription could not be checked")
struct AccountNoticeTests {
    @Test("a current subscription has nothing to say")
    func quiet() {
        #expect(HistoryFixture.accountPage(access: .allowed).notice == nil)
    }

    /// There is nothing to ask of somebody on a train, so it is a note and not a door.
    @Test("no network says it will try again, and nothing more")
    func offline() {
        let notice = HistoryFixture.accountPage(access: .allowedAwaitingNetwork).notice
        #expect(notice?.symbolName == "wifi.slash")
        #expect(notice?.tone == .neutral)
        #expect(notice?.message.contains("carried on without it") == true)
    }

    @Test("a renewal worth attempting is offered as a suggestion, not a requirement")
    func pendingSignIn() {
        let notice = HistoryFixture.accountPage(access: .allowedPendingSignIn).notice
        #expect(notice?.tone == .warning)
        #expect(notice?.message.contains("Dictation carries on either way") == true)
    }

    /// Nobody signed in draws the empty state, where the invitation already is; a notice would repeat it.
    @Test("refused draws no notice, because the empty state is the whole page")
    func refused() {
        #expect(HistoryFixture.accountPage(account: nil, access: .refused).notice == nil)
    }
}

@Suite("Account before anybody has signed in")
struct AccountEmptyTests {
    @Test("nobody signed in gets the invitation and nothing else")
    func signedOut() {
        let page = HistoryFixture.accountPage(account: nil, access: .refused)
        #expect(page.identity == nil)
        #expect(page.facts.isEmpty)
        #expect(page.action == nil)
        #expect(page.actionHelp == nil)
        #expect(page.emptyState?.title == "Not signed in")
        #expect(page.emptyState?.action?.intent == .signIn)
        #expect(page.emptyState?.message.contains("dictation runs on this Mac") == true)
        #expect(page.emptyState?.message.contains("never needs it again") == false)
    }

    /// The promise about local data is most worth reading by somebody deciding whether to sign in.
    @Test("the promise is made to somebody who has not signed in yet")
    func promiseIsAlwaysThere() {
        let page = HistoryFixture.accountPage(account: nil, access: .refused)
        #expect(page.callout.message == AccountPagePresenter.localDataPromise)
        #expect(page.chrome.title == "Account")
    }

    @Test("a signed-in page has no empty state")
    func signedIn() {
        #expect(HistoryFixture.accountPage().emptyState == nil)
    }

    /// The letters are always worked out, because the picture arrives late, or never.
    @Test("keeps the initials whether or not there is a picture to draw over them")
    func theInitialsSurviveThePicture() {
        let bytes = Data([0x89, 0x50, 0x4E, 0x47])
        let withPicture = HistoryFixture.accountPage(picture: bytes)
        #expect(withPicture.identity?.picture == bytes)
        #expect(!(withPicture.identity?.initials.isEmpty ?? true))

        let without = HistoryFixture.accountPage()
        #expect(without.identity?.picture == nil)
        #expect(without.identity?.initials == withPicture.identity?.initials)
    }
}
