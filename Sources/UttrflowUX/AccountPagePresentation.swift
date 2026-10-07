// The Account page: who is signed in and the four facts about them.
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
    /// "Google", "GitHub" or "Apple".
    public let provider: String
    /// Which provider signed this person in, or `nil` when it is not known.
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

/// One fact in the list under the banner.
public struct AccountFact: Sendable, Equatable, Identifiable {
    /// Which fact this is, which decides its glyph.
    public enum Kind: Sendable, Equatable, Hashable {
        case email
        case signIn
        case since
        case thisMac
    }

    /// Which fact this is.
    public let kind: Kind
    /// The row's heading: "Email", "Signed in with".
    public let label: String
    /// What the row says.
    public let value: String

    /// The kind, which appears once in the list.
    public var id: Kind { kind }

    /// Builds a fact.
    public init(kind: Kind, label: String, value: String) {
        self.kind = kind
        self.label = label
        self.value = value
    }
}

/// Everything the account page is drawn from.
public struct AccountPageSnapshot: Sendable, Equatable {
    /// The session on this Mac. Absent when nobody has signed in.
    public let entitlement: Entitlement?
    /// The signed-in person's picture as bytes, since only `UttrflowAccount` may reach the network.
    public let picture: Data?
    /// What Uttrflow may currently do, which differs from who is signed in once an entitlement ages out.
    public let access: DictationAccess
    /// The clock the page is drawn against.
    public let now: Date
    /// When the account was created, from the unsigned profile; `nil` hides the row rather than guessing.
    public let memberSince: Date?
    /// What this Mac is called in System Settings; `nil` hides the row.
    public let macName: String?

    /// Builds a snapshot; everything after the clock is optional.
    public init(
        entitlement: Entitlement?, access: DictationAccess, now: Date, picture: Data? = nil,
        memberSince: Date? = nil, macName: String? = nil
    ) {
        self.entitlement = entitlement
        self.picture = picture
        self.access = access
        self.now = now
        self.memberSince = memberSince
        self.macName = macName
    }
}

/// What the account page shows.
public struct AccountPagePresentation: Sendable, Equatable {
    /// The title and caption across the top.
    public let chrome: MainPageChrome
    /// Absent exactly when ``emptyState`` is set.
    public let identity: AccountIdentity?
    /// The facts under the banner, in order; a fact nobody knows is left out rather than guessed.
    public let facts: [AccountFact]
    /// The one button at the foot: Sign out for a session.
    public let action: MainAction?
    /// What pressing ``action`` does, for its tooltip.
    public let actionHelp: String?
    /// Deleting the account on the server, beside ``action``; absent when nobody is signed in.
    public let deletion: MainAction?
    /// A quiet note when the subscription could not be re-checked. Never a door.
    public let notice: MainCallout?
    /// The promise about what stays on this Mac, drawn beside the invitation to sign in.
    public let callout: MainCallout
    /// The invitation to sign in, when nobody has.
    public let emptyState: MainEmptyState?

    /// Builds the page from its parts.
    public init(
        chrome: MainPageChrome,
        identity: AccountIdentity?,
        facts: [AccountFact],
        action: MainAction?,
        actionHelp: String?,
        deletion: MainAction? = nil,
        notice: MainCallout?,
        callout: MainCallout,
        emptyState: MainEmptyState?
    ) {
        self.chrome = chrome
        self.identity = identity
        self.facts = facts
        self.action = action
        self.actionHelp = actionHelp
        self.deletion = deletion
        self.notice = notice
        self.callout = callout
        self.emptyState = emptyState
    }
}

/// Turns the session into the page that says who is signed in, and nothing it does not know.
public enum AccountPagePresenter {
    /// The heading, the same over every form of the page.
    static let chrome = MainPageChrome(
        title: "Account", caption: "Who you are signed in as, and on which Mac.")

    /// The promise in the privacy screen's words; it never says "recordings", since none is kept.
    public static let localDataPromise = """
        The account is an identity and nothing more. Your transcripts, Dictionary \
        and Snippets are files on this Mac — signing out leaves every one of them \
        exactly where it is. Audio is never one of them: it is discarded as it becomes text.
        """

    /// What Sign out does, as its tooltip.
    public static let signOutHelp = """
        Uttrflow stops until you sign in again, which needs the network. Your transcripts, \
        Dictionary and Snippets stay on this Mac.
        """

    /// What Delete account does, as its tooltip; the full list is in `Docs/account-server-data.md`.
    public static let deletionHelp = """
        Deletes your account on the server: name, email address, sign-in and the list of your Macs. \
        Your transcripts, Dictionary and Snippets stay on this Mac.
        """

    /// Draws the Account page from a snapshot.
    public static func page(
        for snapshot: AccountPageSnapshot, locale: Locale = .autoupdatingCurrent
    ) -> AccountPagePresentation {
        let callout = MainCallout(symbolName: "lock", tone: .good, message: localDataPromise)
        guard let entitlement = snapshot.entitlement else {
            return AccountPagePresentation(
                chrome: chrome,
                identity: nil,
                facts: [],
                action: nil,
                actionHelp: nil,
                notice: nil,
                callout: callout,
                emptyState: MainEmptyState(
                    symbolName: "person.crop.circle",
                    title: "Not signed in",
                    message: """
                        Signing in needs the network, but dictation runs on this Mac once setup is \
                        complete. You can keep speaking when Wi-Fi is gone.
                        """,
                    action: MainAction(title: "Sign In", intent: .signIn)))
        }

        return AccountPagePresentation(
            chrome: chrome,
            identity: identity(for: entitlement.account, picture: snapshot.picture),
            facts: facts(for: entitlement.account, snapshot: snapshot, locale: locale),
            action: MainAction(
                title: "Sign out", symbolName: "rectangle.portrait.and.arrow.right",
                intent: .signOut, isDestructive: true),
            actionHelp: signOutHelp,
            deletion: MainAction(
                title: "Delete account", symbolName: "person.crop.circle.badge.xmark",
                intent: .deleteAccount, isDestructive: true),
            notice: notice(for: snapshot.access),
            callout: callout,
            emptyState: nil)
    }

    /// Email, provider, member since and this Mac, each only when it is known.
    static func facts(
        for account: Account, snapshot: AccountPageSnapshot, locale: Locale
    ) -> [AccountFact] {
        let email = account.emailAddress?.trimmingCharacters(in: .whitespacesAndNewlines)
        return [
            email.flatMap { $0.isEmpty ? nil : AccountFact(kind: .email, label: "Email", value: $0) },
            AccountFact(kind: .signIn, label: "Signed in with", value: title(for: account.provider)),
            snapshot.memberSince.map {
                AccountFact(kind: .since, label: "Member since", value: since($0, locale: locale))
            },
            thisMac(snapshot.macName),
        ].compactMap(\.self)
    }

    /// The Mac's own name as a fact, or nothing when it would not say.
    static func thisMac(_ name: String?) -> AccountFact? {
        guard let name = name?.trimmingCharacters(in: .whitespacesAndNewlines), !name.isEmpty
        else { return nil }
        return AccountFact(kind: .thisMac, label: "This Mac", value: name)
    }

    /// A day in the reader's own locale, as "12 Sep 2026" reads in English.
    static func since(_ moment: Date, locale: Locale) -> String {
        var format = Date.FormatStyle.dateTime.day().month(.abbreviated).year()
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

    /// The first letter of the first word that starts with one, or "?" when no word does.
    static func initials(of name: String?) -> String {
        guard let name, !name.isEmpty else { return "?" }
        let words = name.split(whereSeparator: \.isWhitespace).filter { $0.first?.isLetter == true }
        guard let letter = words.first?.first else { return "?" }
        return String(letter).uppercased()
    }

    /// The providers' own names for themselves, capitalisation included: "GitHub", not "Github".
    public static func title(for provider: SignInProvider) -> String {
        switch provider {
        case .google: "Google"
        case .gitHub: "GitHub"
        case .apple: "Apple"
        }
    }

    // MARK: - When the subscription could not be checked

    /// A note, never a door: both aged-out states permit dictation, so neither blocks the user.
    static func notice(for access: DictationAccess) -> MainCallout? {
        switch access {
        // Nothing to say: one is a current subscription, the other a page that explains itself.
        case .allowed, .refused:
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
