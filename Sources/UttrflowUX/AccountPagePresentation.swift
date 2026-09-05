public import Foundation
public import UttrflowAccount

/// Who is signed in, as the page draws them.
public struct AccountIdentity: Sendable, Equatable {
    /// One or two letters for the circle. Derived from the name, or the email when
    /// there is no name — never a stock silhouette, which tells the user nothing about
    /// which of their accounts this is.
    ///
    /// Still derived when there is a picture, and not as a placeholder: the picture is
    /// fetched over a network that may be off, from a provider that may be slow, and the
    /// circle has to say whose account this is in the meantime.
    public let initials: String

    /// The picture the provider has, once it has been fetched. `nil` for an account with
    /// none, for a fetch that has not finished, and for one that failed — three
    /// situations the page deliberately draws identically, because the answer to all
    /// three is the initials it already has.
    public let picture: Data?
    public let name: String
    /// Absent when the provider gave none, which is allowed.
    public let emailAddress: String?
    /// "Google", "GitHub", "Apple" — or "This Mac", for somebody working without an
    /// Uttrflow account.
    public let provider: String
    /// Which provider signed this person in, or `nil` when nobody did — a
    /// ``LocalAccount`` has no provider, because there was no third party involved in
    /// somebody deciding to use their own Mac.
    public let providerID: SignInProvider?

    public init(
        initials: String, name: String, emailAddress: String?, provider: String,
        providerID: SignInProvider?, picture: Data? = nil
    ) {
        self.initials = initials
        self.picture = picture
        self.name = name
        self.emailAddress = emailAddress
        self.provider = provider
        self.providerID = providerID
    }
}

/// One line in the account card.
public struct AccountDetail: Sendable, Equatable, Identifiable {
    public let label: String
    /// What the row says. Absent on a row whose whole content is its action.
    public let value: String?
    public let explanation: String?
    public let action: MainAction?

    public var id: String { label }

    public init(
        label: String, value: String? = nil, explanation: String? = nil, action: MainAction? = nil
    ) {
        self.label = label
        self.value = value
        self.explanation = explanation
        self.action = action
    }
}

/// Everything the account page is drawn from.
public struct AccountPageSnapshot: Sendable, Equatable {
    /// The session on this Mac. Absent when nobody has signed in.
    public let entitlement: Entitlement?
    /// The choice to work without an account, when somebody made it. Only ever consulted
    /// when ``entitlement`` is absent: a real session is the better answer to every
    /// question this page asks, and one that could be overruled by an unsigned value
    /// would be no session at all.
    public let local: LocalAccount?
    /// The signed-in person's picture, when the app has it. Bytes rather than an address,
    /// because the one place allowed to reach the network is `UttrflowAccount` and this
    /// module draws pages.
    public let picture: Data?
    /// What Uttrflow may currently do, which is not the same question as who is signed
    /// in: an entitlement can be present and aged out, and the difference is the whole
    /// reason ``DictationAccess`` has four cases rather than two.
    public let access: DictationAccess
    public let now: Date

    public init(
        entitlement: Entitlement?, access: DictationAccess, now: Date, picture: Data? = nil,
        local: LocalAccount? = nil
    ) {
        self.entitlement = entitlement
        self.local = local
        self.picture = picture
        self.access = access
        self.now = now
    }
}

/// What the account page shows.
public struct AccountPagePresentation: Sendable, Equatable {
    public let chrome: MainPageChrome
    /// Absent exactly when ``emptyState`` is set.
    public let identity: AccountIdentity?
    public let details: [AccountDetail]
    /// A quiet note when the subscription could not be re-checked. Never a door.
    public let notice: MainCallout?
    public let callout: MainCallout
    public let emptyState: MainEmptyState?
    public let footnote: String?

    public init(
        chrome: MainPageChrome,
        identity: AccountIdentity?,
        details: [AccountDetail],
        notice: MainCallout?,
        callout: MainCallout,
        emptyState: MainEmptyState?,
        footnote: String?
    ) {
        self.chrome = chrome
        self.identity = identity
        self.details = details
        self.notice = notice
        self.callout = callout
        self.emptyState = emptyState
        self.footnote = footnote
    }
}

/// Turns the session into the page that explains what having one does, and — more
/// usefully — what it does not.
///
/// The reassurance is the page. An account on a product whose promise is that nothing
/// leaves your Mac invites exactly one question, and the answer has to be on the screen
/// rather than in a support article.
public enum AccountPagePresenter {
    /// The heading, the same over every form of the page.
    static let chrome = MainPageChrome(
        title: "Account", caption: "Who you are signed in as, and what you are paying for.")

    /// The promise, in the words the privacy screen uses.
    /// Deliberately does not say "recordings".
    ///
    /// It used to, and that contradicted the onboarding screen — "Audio is processed on
    /// this Mac and discarded the moment it becomes text" — and the product's own
    /// architecture. There is no recording to leave anywhere: naming one here told the
    /// user this app keeps their audio, on the single screen whose job is to reassure
    /// them about what it keeps.
    public static let localDataPromise = """
        The account is an identity and nothing more. Your transcripts, Dictionary, \
        Corrections and Snippets are files on this Mac — signing out leaves every one of them \
        exactly where it is. Audio is never one of them: it is discarded as it becomes text.
        """

    public static func page(
        for snapshot: AccountPageSnapshot, locale: Locale = .autoupdatingCurrent
    ) -> AccountPagePresentation {
        let callout = MainCallout(symbolName: "lock", tone: .good, message: localDataPromise)
        guard let entitlement = snapshot.entitlement else {
            // Somebody who chose this Mac over an account gets a page about the account
            // they have, not the empty state for the one they do not. The empty state is
            // an invitation, and repeating an invitation somebody has already answered is
            // how a product tells a user it was not listening.
            if let local = snapshot.local {
                return page(for: local, callout: callout, locale: locale)
            }
            return AccountPagePresentation(
                chrome: chrome,
                identity: nil,
                details: [],
                notice: nil,
                callout: callout,
                emptyState: MainEmptyState(
                    symbolName: "person.crop.circle",
                    title: "Not signed in",
                    message: """
                        Uttrflow needs the network once, to know who you are. After that it never \
                        needs it again — dictation runs on this Mac whether you are online or not.
                        """,
                    action: MainAction(title: "Sign In", intent: .signIn)),
                footnote: nil)
        }

        return AccountPagePresentation(
            chrome: chrome,
            identity: identity(for: entitlement.account, picture: snapshot.picture),
            details: details(for: entitlement),
            notice: notice(for: snapshot.access),
            callout: callout,
            emptyState: nil,
            footnote: """
                Uttrflow reaches the network to sign you in, and for nothing else. Turn Wi-Fi off \
                afterwards and dictation carries on working.
                """)
    }

    // MARK: - Working without an account

    /// The page for somebody using this Mac rather than an Uttrflow account.
    ///
    /// Drawn as an account rather than as a warning, because it is one: the person made a
    /// choice and the page's job is to say what that choice means and how to change it,
    /// not to nag them about it. The one thing it must not do is imply a subscription —
    /// there is no plan row here, because there is no plan.
    static func page(
        for local: LocalAccount, callout: MainCallout, locale: Locale
    ) -> AccountPagePresentation {
        let name = local.name ?? "This Mac"
        return AccountPagePresentation(
            chrome: chrome,
            identity: AccountIdentity(
                initials: initials(of: local.name),
                name: name,
                emailAddress: nil,
                provider: "This Mac",
                providerID: nil),
            details: details(for: local, locale: locale),
            notice: nil,
            callout: callout,
            emptyState: nil,
            footnote: """
                Dictation, the Dictionary, Corrections and Snippets all work exactly like \
                this. An account adds the two things that need one: carrying your words' \
                settings to another Mac, and a subscription.
                """)
    }

    /// What working without an account gets you, and the way out of it.
    static func details(for local: LocalAccount, locale: Locale) -> [AccountDetail] {
        [
            AccountDetail(
                label: "Account",
                value: "None — this Mac only",
                explanation: """
                    Uttrflow is running as \(local.name ?? "the owner of this Mac"), the name \
                    macOS knows you by. Nothing is sent anywhere and nothing is being counted.
                    """),
            AccountDetail(
                label: "Since",
                value: since(local.since, locale: locale),
                explanation: "When you chose to carry on without signing in."),
            AccountDetail(
                label: "Sign in",
                explanation: """
                    Needs the network once. It replaces this Mac account with a real one and \
                    leaves everything on this Mac exactly where it is.
                    """,
                action: MainAction(title: "Sign In", intent: .signIn)),
        ]
    }

    /// The day somebody chose this Mac, in their own locale.
    static func since(_ moment: Date, locale: Locale) -> String {
        var format = Date.FormatStyle.dateTime.day().month(.wide).year()
        format.locale = locale
        return moment.formatted(format)
    }

    // MARK: - Who

    /// Public because two windows draw the same person: the Account page, and the foot of
    /// the Settings rail. Deriving the initials twice is how they would come to differ.
    public static func identity(for account: Account, picture: Data? = nil) -> AccountIdentity {
        let name = account.displayName?.trimmingCharacters(in: .whitespacesAndNewlines)
        let email = account.emailAddress?.trimmingCharacters(in: .whitespacesAndNewlines)
        let shown = [name, email].compactMap(\.self).first { !$0.isEmpty }
        return AccountIdentity(
            initials: initials(of: shown),
            // The identifier is the last resort rather than "Unknown": an opaque string
            // at least belongs to the right account, where a placeholder belongs to none.
            name: shown ?? account.identifier,
            emailAddress: name == nil || (email?.isEmpty ?? true) ? nil : email,
            provider: title(for: account.provider),
            providerID: account.provider,
            picture: picture)
    }

    /// The first letter of each of the first two words.
    ///
    /// One word gives one letter rather than two of its characters: "PR" for Prince
    /// looks like a company, where "P" plainly reads as a person's initial. An email
    /// address is one word by this definition, which is what we want — "n.d" is not
    /// initials and "@" is not a letter.
    static func initials(of name: String?) -> String {
        guard let name, !name.isEmpty else { return "?" }
        let words = name.split(whereSeparator: \.isWhitespace).filter { $0.first?.isLetter == true }
        let letters = words.prefix(2).compactMap(\.first)
        guard !letters.isEmpty else { return "?" }
        return String(letters).uppercased()
    }

    /// The providers' own names for themselves, capitalisation included — "GitHub" is
    /// not "Github", and getting a company's name wrong on the screen that names it is
    /// the sort of detail that costs trust for free.
    public static func title(for provider: SignInProvider) -> String {
        switch provider {
        case .google: "Google"
        case .gitHub: "GitHub"
        case .apple: "Apple"
        }
    }

    // MARK: - What that allows

    /// Plan and sign-out, and deliberately nothing else.
    ///
    /// The artboard also shows "Signed in since". ``Entitlement`` records only when it
    /// expires, not when it was issued, so the date would have to be invented or
    /// back-computed from an expiry whose length is the backend's business. It is left
    /// out until something records it, by the same rule that keeps "time saved" off
    /// Insights.
    static func details(for entitlement: Entitlement) -> [AccountDetail] {
        [
            AccountDetail(
                label: "Plan",
                value: title(for: entitlement.plan),
                explanation: explanation(for: entitlement.plan)),
            AccountDetail(
                label: "Sign out",
                explanation: """
                    Uttrflow stops until you sign in again. It needs the network for that one step.
                    """,
                action: MainAction(title: "Sign Out", intent: .signOut, isDestructive: true)),
        ]
    }

    public static func title(for plan: Plan) -> String {
        switch plan {
        case .free: "Free"
        case .pro: "Pro"
        }
    }

    static func explanation(for plan: Plan) -> String {
        switch plan {
        case .free: "Unlimited dictation on this Mac. Nothing to pay, nothing metered."
        case .pro: "Everything in Free, and the clean-up models that need a subscription."
        }
    }

    // MARK: - When the subscription could not be checked

    /// A note, never a door. Both aged-out states permit a dictation, so neither may be
    /// drawn as something the user has to resolve before carrying on.
    static func notice(for access: DictationAccess) -> MainCallout? {
        switch access {
        // Nothing to say in either: one is a current subscription, and the other is a
        // page that already explains itself from top to bottom.
        case .allowed, .allowedOnThisMac, .refused:
            nil
        case .allowedAwaitingNetwork:
            MainCallout(
                symbolName: "wifi.slash",
                tone: .neutral,
                message: """
                    Uttrflow could not re-check your subscription, and has carried on without it. \
                    It will try again when there is a connection.
                    """)
        case .allowedPendingSignIn:
            MainCallout(
                symbolName: "arrow.clockwise",
                tone: .warning,
                message: """
                    Your subscription needs re-checking. Dictation carries on either way — sign \
                    in again when it suits you.
                    """)
        }
    }
}
