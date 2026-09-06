// The Account page: who is signed in, what the plan allows, and the page for working without an account.
public import Foundation
public import UttrflowAccount

/// Who is signed in, as the page draws them.
public struct AccountIdentity: Sendable, Equatable {
    /// One or two letters for the circle, from the name or the email; drawn even while a picture loads.
    public let initials: String

    /// The provider's picture once fetched; `nil` for none, not yet, and failed, which all draw the initials.
    public let picture: Data?
    /// The name shown beside the circle.
    public let name: String
    /// Absent when the provider gave none, which is allowed.
    public let emailAddress: String?
    /// "Google", "GitHub", "Apple" — or "This Mac" for somebody working without an Uttrflow account.
    public let provider: String
    /// Which provider signed this person in, or `nil` for a ``LocalAccount``, which has no third party.
    public let providerID: SignInProvider?

    /// Builds an identity; the picture is optional.
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
    /// The row's heading.
    public let label: String
    /// What the row says. Absent on a row whose whole content is its action.
    public let value: String?
    /// The sentence under the value.
    public let explanation: String?
    /// The button on the row, when it has one.
    public let action: MainAction?

    /// The label, which is unique within the card.
    public var id: String { label }

    /// Builds a row; everything but the label is optional.
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
    /// The choice to work without an account; consulted only when ``entitlement`` is absent.
    public let local: LocalAccount?
    /// The signed-in person's picture as bytes, since only `UttrflowAccount` may reach the network.
    public let picture: Data?
    /// What Uttrflow may currently do, which differs from who is signed in once an entitlement ages out.
    public let access: DictationAccess
    /// The clock the page is drawn against.
    public let now: Date

    /// Builds a snapshot; the picture and the local account are optional.
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
    /// The title and caption across the top.
    public let chrome: MainPageChrome
    /// Absent exactly when ``emptyState`` is set.
    public let identity: AccountIdentity?
    /// The rows of the account card.
    public let details: [AccountDetail]
    /// A quiet note when the subscription could not be re-checked. Never a door.
    public let notice: MainCallout?
    /// The promise about what stays on this Mac.
    public let callout: MainCallout
    /// The invitation to sign in, when nobody has.
    public let emptyState: MainEmptyState?
    /// The line under the page.
    public let footnote: String?

    /// Builds the page from its parts.
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

/// Turns the session into the page that says what having an account does, and what it does not.
public enum AccountPagePresenter {
    /// The heading, the same over every form of the page.
    static let chrome = MainPageChrome(
        title: "Account", caption: "Who you are signed in as, and what you are paying for.")

    /// The promise in the privacy screen's words; it never says "recordings", since none is kept.
    public static let localDataPromise = """
        The account is an identity and nothing more. Your transcripts, Dictionary, \
        Corrections and Snippets are files on this Mac — signing out leaves every one of them \
        exactly where it is. Audio is never one of them: it is discarded as it becomes text.
        """

    /// Draws the Account page from a snapshot.
    public static func page(
        for snapshot: AccountPageSnapshot, locale: Locale = .autoupdatingCurrent
    ) -> AccountPagePresentation {
        let callout = MainCallout(symbolName: "lock", tone: .good, message: localDataPromise)
        guard let entitlement = snapshot.entitlement else {
            // Somebody who chose this Mac gets a page about that account, not an invitation to another.
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

    /// The page for somebody using this Mac, drawn as an account rather than a warning, with no plan row.
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

    /// Public because the Account page and the Settings rail draw the same person from one derivation.
    public static func identity(for account: Account, picture: Data? = nil) -> AccountIdentity {
        let name = account.displayName?.trimmingCharacters(in: .whitespacesAndNewlines)
        let email = account.emailAddress?.trimmingCharacters(in: .whitespacesAndNewlines)
        let shown = [name, email].compactMap(\.self).first { !$0.isEmpty }
        return AccountIdentity(
            initials: initials(of: shown),
            // The identifier rather than "Unknown": an opaque string at least belongs to the right account.
            name: shown ?? account.identifier,
            emailAddress: name == nil || (email?.isEmpty ?? true) ? nil : email,
            provider: title(for: account.provider),
            providerID: account.provider,
            picture: picture)
    }

    /// The first letter of the first two words; one word gives one letter, and an email is one word.
    static func initials(of name: String?) -> String {
        guard let name, !name.isEmpty else { return "?" }
        let words = name.split(whereSeparator: \.isWhitespace).filter { $0.first?.isLetter == true }
        let letters = words.prefix(2).compactMap(\.first)
        guard !letters.isEmpty else { return "?" }
        return String(letters).uppercased()
    }

    /// The providers' own names for themselves, capitalisation included: "GitHub", not "Github".
    public static func title(for provider: SignInProvider) -> String {
        switch provider {
        case .google: "Google"
        case .gitHub: "GitHub"
        case .apple: "Apple"
        }
    }

    // MARK: - What that allows

    /// Plan and sign-out only; "signed in since" waits until something records an issue date.
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

    /// The plan's name.
    public static func title(for plan: Plan) -> String {
        switch plan {
        case .free: "Free"
        case .pro: "Pro"
        }
    }

    /// What the plan allows, in a sentence.
    static func explanation(for plan: Plan) -> String {
        switch plan {
        case .free: "Unlimited dictation on this Mac. Nothing to pay, nothing metered."
        case .pro: "Everything in Free, and the clean-up models that need a subscription."
        }
    }

    // MARK: - When the subscription could not be checked

    /// A note, never a door: both aged-out states permit dictation, so neither blocks the user.
    static func notice(for access: DictationAccess) -> MainCallout? {
        switch access {
        // Nothing to say: one is a current subscription, the other a page that explains itself.
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
