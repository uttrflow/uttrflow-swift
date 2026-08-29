import Foundation
import UttrflowAccount
import Testing

@testable import UttrflowUX

extension HistoryFixture {
    static func account(
        name: String? = "Naveen Bhatt",
        email: String? = "nadia.d@example.com",
        provider: SignInProvider = .google
    ) -> Account {
        Account(
            identifier: "account-1", displayName: name, emailAddress: email, provider: provider)
    }

    static func accountPage(
        account: Account? = HistoryFixture.account(),
        plan: Plan = .free,
        access: DictationAccess = .allowed,
        picture: Data? = nil,
        local: LocalAccount? = nil
    ) -> AccountPagePresentation {
        AccountPagePresenter.page(
            for: AccountPageSnapshot(
                entitlement: account.map {
                    Entitlement(
                        account: $0, plan: plan,
                        expiresAt: now.addingTimeInterval(86_400), signature: "signed")
                },
                access: access, now: now, picture: picture, local: local),
            locale: locale)
    }

    /// Somebody who chose this Mac over an account, with no entitlement anywhere.
    static func macAccountPage(name: String? = "Naveen Bhatt") -> AccountPagePresentation {
        accountPage(
            account: nil, access: .allowedOnThisMac,
            local: LocalAccount(name: name, since: now))
    }
}

@Suite("Account: working on this Mac")
struct MacAccountPageTests {
    /// The empty state is an invitation. Repeating it to somebody who has already
    /// answered it is the app telling them it was not listening.
    @Test("draws an account rather than the invitation to make one")
    func drawnAsAnAccount() {
        let page = HistoryFixture.macAccountPage()
        #expect(page.emptyState == nil)
        #expect(page.identity?.name == "Naveen Bhatt")
        #expect(page.identity?.initials == "NB")
        #expect(page.identity?.provider == "This Mac")
        #expect(page.identity?.providerID == nil, "nobody signed this person in")
        #expect(page.identity?.emailAddress == nil, "no provider means no address to show")
    }

    /// The one thing this page must never imply. There is no subscription behind it, so
    /// there is no plan row and nothing that could be read as one.
    @Test("claims no plan, because there is none")
    func noPlanIsClaimed() {
        let page = HistoryFixture.macAccountPage()
        #expect(!page.details.contains { $0.label == "Plan" })
        let wording = page.details.flatMap { [$0.label, $0.value ?? "", $0.explanation ?? ""] }
            .joined(separator: " ")
        for claim in ["Pro", "Free", "subscribed", "trial"] {
            #expect(!wording.contains(claim), "the Mac account page hints at \(claim)")
        }
    }

    /// The way out has to be on the page, or the choice is one-way.
    @Test("offers signing in, and says what it would change")
    func signingInIsOffered() {
        let page = HistoryFixture.macAccountPage()
        let signIn = page.details.first { $0.action?.intent == .signIn }
        #expect(signIn?.action?.title == "Sign In")
        #expect(signIn?.explanation?.contains("leaves everything on this Mac") == true)
        #expect(!page.details.contains { $0.action?.intent == .signOut }, "there is no session")
    }

    @Test("says when this arrangement started, in the reader's own calendar")
    func saysSince() {
        #expect(
            HistoryFixture.macAccountPage().details.first { $0.label == "Since" }?.value
                == AccountPagePresenter.since(HistoryFixture.now, locale: HistoryFixture.locale))
    }

    /// A Mac that will not say whose it is still gets a page, with a monogram that does
    /// not pretend to be anybody's initials.
    @Test("draws a Mac with no owner's name on it")
    func noName() {
        let page = HistoryFixture.macAccountPage(name: nil)
        #expect(page.identity?.name == "This Mac")
        #expect(page.identity?.initials == "?")
    }

    /// The signed value wins, every time. A page that could be talked out of a session by
    /// an unsigned one would be no session at all.
    @Test("a real account is drawn even when a Mac account is also present")
    func realAccountWins() {
        let page = HistoryFixture.accountPage(
            local: LocalAccount(name: "Somebody Else", since: HistoryFixture.now))
        #expect(page.identity?.name == "Naveen Bhatt")
        #expect(page.identity?.providerID == .google)
        #expect(page.details.contains { $0.label == "Plan" })
    }

    /// Every other state that permits a dictation carries a note explaining itself. This
    /// one is a page that explains itself from top to bottom, so a banner would be the
    /// same sentence twice.
    @Test("carries no notice, because the page is the explanation")
    func noNotice() {
        #expect(HistoryFixture.macAccountPage().notice == nil)
    }
}

@Suite("Account: who is signed in")
struct AccountIdentityTests {
    @Test("the name, the address and the provider are shown")
    func identity() {
        let identity = HistoryFixture.accountPage().identity
        #expect(identity?.name == "Naveen Bhatt")
        #expect(identity?.emailAddress == "nadia.d@example.com")
        #expect(identity?.provider == "Google")
        #expect(identity?.providerID == .google)
    }

    /// A stock silhouette tells the user nothing about which of their accounts this is.
    @Test("the circle carries the initials of the name")
    func initials() {
        #expect(HistoryFixture.accountPage().identity?.initials == "NB")
        #expect(AccountPagePresenter.initials(of: "Ada Byron Lovelace") == "AB")
        // "PR" would read as a company; one name gives one initial.
        #expect(AccountPagePresenter.initials(of: "Prince") == "P")
    }

    /// "a.d" is not initials and "@" is not a letter, so an address contributes one
    /// letter rather than two pieces of punctuation.
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

    /// An opaque identifier at least belongs to the right account, where a placeholder
    /// belongs to none.
    @Test("an account with neither name nor address is named by its identifier")
    func neither() {
        let identity = HistoryFixture.accountPage(
            account: HistoryFixture.account(name: nil, email: nil)
        ).identity
        #expect(identity?.name == "account-1")
        #expect(identity?.initials == "?")
    }

    /// A provider may hand over a name and no address at all, and the card must not
    /// then draw an empty second line under the name.
    @Test("a name with no address shows the name alone")
    func nameWithoutAnAddress() {
        let identity = HistoryFixture.accountPage(
            account: HistoryFixture.account(email: nil)
        ).identity
        #expect(identity?.name == "Naveen Bhatt")
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

@Suite("Account: what having one allows")
struct AccountDetailsTests {
    @Test("the plan and the way out are the only two rows")
    func rows() {
        let page = HistoryFixture.accountPage()
        #expect(page.details.map(\.label) == ["Plan", "Sign out"])
        #expect(page.details[0].value == "Free")
        #expect(page.details[1].action?.intent == .signOut)
        #expect(page.details[1].action?.isDestructive == true)
        #expect(page.details[0].id == "Plan")
    }

    /// The artboard also shows "Signed in since". ``Entitlement`` records only when it
    /// expires, so the date would have to be invented — the same rule that keeps "time
    /// saved" off Insights keeps it off here.
    @Test("nothing is shown that the entitlement does not record")
    func noInventedDate() {
        #expect(!HistoryFixture.accountPage().details.contains { $0.label == "Signed in since" })
    }

    @Test("each plan is named and explained")
    func plans() {
        #expect(AccountPagePresenter.title(for: .free) == "Free")
        #expect(AccountPagePresenter.title(for: .pro) == "Pro")
        #expect(HistoryFixture.accountPage(plan: .pro).details[0].value == "Pro")
        for plan in Plan.allCases {
            #expect(!AccountPagePresenter.explanation(for: plan).isEmpty)
        }
    }

    /// The question an account on this product invites, answered on the screen rather
    /// than in a support article.
    @Test("the page says what signing out does not do")
    func promise() {
        let page = HistoryFixture.accountPage()
        #expect(page.callout.message == AccountPagePresenter.localDataPromise)
        #expect(page.callout.message.contains("signing out leaves every one of them"))
        #expect(page.callout.tone == .good)
        #expect(page.footnote?.contains("for nothing else") == true)
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

    /// Nobody signed in draws the empty state, where the invitation already is; a
    /// second one above it would be two ways to do one thing.
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
        #expect(page.details.isEmpty)
        #expect(page.footnote == nil)
        #expect(page.emptyState?.title == "Not signed in")
        #expect(page.emptyState?.action?.intent == .signIn)
    }

    /// The promise about local data is on the page whether or not anybody is signed in:
    /// it is most worth reading by somebody deciding whether to sign in at all.
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

    /// The picture and the letters are not alternatives the page chooses between: the
    /// letters are always worked out, because the picture arrives late, or never.
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
