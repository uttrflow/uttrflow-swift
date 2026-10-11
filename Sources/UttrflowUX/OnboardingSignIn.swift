// The sign-in page's states, and the reachability check that decides whether it can be attempted.
internal import Foundation
public import UttrflowAccount

/// Whether a request could be attempted right now, read synchronously from the last path reported.
public protocol NetworkReachability: Sendable {
    /// Whether the network is up.
    var isReachable: Bool { get }
}

/// What the sign-in page is doing; the one page in the product that cannot work offline.
public enum OnboardingSignInState: Sendable, Equatable {
    /// The three providers, live, waiting to be chosen.
    case offering

    /// There is no connection; the providers stay on screen and inert, which says more than an empty panel.
    case unreachable

    /// The browser has the user, or the code is being exchanged; both wait on somewhere else.
    case signingIn(SignInProvider)

    /// This Mac cannot be redirected back to, so the person types a code; its own page, not a variant.
    case enterCode(SignInProvider, code: String)

    /// Somebody answered and said no; the providers come back live, since another attempt is the remedy.
    case refused(String)

    /// Signed in: the welcome shows for a moment, then onboarding moves on by itself.
    case welcomed(OnboardingWelcome)
}

/// Who just signed in, and the page the welcome leads to.
public struct OnboardingWelcome: Sendable, Equatable {
    /// The first name to greet, or `nil` when the provider gave none.
    public let firstName: String?
    /// The address shown in the account chip, or `nil` when the provider gave none.
    public let emailAddress: String?
    /// One letter for the circle.
    public let initials: String
    /// Which provider signed them in.
    public let provider: SignInProvider
    /// The page Continue leads to.
    public let next: OnboardingStep

    /// Builds the welcome from the account the server returned.
    public init(account: Account, next: OnboardingStep) {
        let name = account.displayName?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let email = account.emailAddress?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        self.firstName = HomePresenter.firstName(of: name)
        self.emailAddress = email.isEmpty ? nil : email
        self.initials = AccountPagePresenter.initials(of: name.isEmpty ? email : name)
        self.provider = account.provider
        self.next = next
    }
}

extension OnboardingSignInState {
    /// Whether the three provider buttons can be pressed.
    var acceptsAProvider: Bool {
        switch self {
        case .offering, .refused: true
        case .unreachable, .signingIn, .enterCode, .welcomed: false
        }
    }
}
