// The steps of onboarding, what each page is waiting on, and what the user ends up able to do.
public import UttrflowCore

/// One page of onboarding, in the order the designs number their dots; every page is always counted.
public enum OnboardingStep: Sendable, Equatable, CaseIterable {
    /// What Uttrflow is for, said before it asks for anything, including who you are.
    case welcome
    /// Who this is. Nothing is offered without it.
    case signIn
    /// Microphone access.
    case microphone
    /// Accessibility access.
    case accessibility
    /// The one-time speech model download.
    case setup
    /// What the user ended up able to do.
    case ready

    /// 1-based position in the row of dots, written out so reordering is a deliberate edit.
    public var position: Int {
        switch self {
        case .welcome: 1
        case .signIn: 2
        case .microphone: 3
        case .accessibility: 4
        case .setup: 5
        case .ready: 6
        }
    }

    /// What the rail beside the page calls this step: a noun, so the rail can be scanned.
    public var railTitle: String {
        switch self {
        case .welcome: "Welcome"
        case .signIn: "Sign in"
        case .microphone: "Microphone"
        case .accessibility: "Accessibility"
        case .setup: "Speech model"
        case .ready: "Ready"
        }
    }

    /// How many steps there are.
    public static var count: Int { allCases.count }

    /// The steps in drawing order, sorted by ``position`` rather than trusting the case order.
    public static var inOrder: [OnboardingStep] {
        allCases.sorted { $0.position < $1.position }
    }
}

/// What the page the user is looking at is waiting on.
public enum OnboardingDetail: Sendable, Equatable {
    /// Nothing outstanding: the page is being read, not answered.
    case reading

    /// The sign-in page and what it is waiting on, including the one thing a missing network stops.
    case signIn(OnboardingSignInState)

    /// A permission page with what macOS says now; each way of lacking one needs a different button.
    case permission(PermissionStatus)

    /// The user has been sent to System Settings, and the page says it is waiting.
    case awaitingSystemSettings

    /// The download, from `0` to `1`.
    case installing(Double)

    /// The download stopped, with the sentence to put in front of the user.
    case installFailed(String)

    /// The last page, holding what the user will actually be able to do.
    case finishing(OnboardingReadiness)
}

extension OnboardingDetail {
    /// What was promised, on the one page that promises anything.
    var readiness: OnboardingReadiness? {
        guard case .finishing(let readiness) = self else { return nil }
        return readiness
    }

    /// What the sign-in page is doing; falls back to offering the providers rather than `nil`.
    var signIn: OnboardingSignInState {
        guard case .signIn(let signIn) = self else { return .offering }
        return signIn
    }

}

/// What the user can do once onboarding closes, read from the system at the last moment.
public enum OnboardingReadiness: Sendable, Equatable, CaseIterable {
    /// Everything is in place.
    case ready
    /// Accessibility is missing, so finished text lands on the clipboard instead of at the cursor.
    case pastesManually
    /// The download did not finish, so nothing can be recognised yet.
    case needsSpeechModel
    /// Without a microphone nothing runs at all.
    case needsMicrophone
}

/// Where the user is, and what that page is waiting on.
public struct OnboardingState: Sendable, Equatable {
    /// Which page.
    public let step: OnboardingStep
    /// What it is waiting on.
    public let detail: OnboardingDetail
}
