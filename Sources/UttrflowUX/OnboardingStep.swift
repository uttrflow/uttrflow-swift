public import UttrflowCore

/// One page of first-run onboarding, in the order the designs number their dots.
///
/// Every page is always in the list, even on a run that has nothing to ask on it. The
/// dots tell the user how long the whole thing is, and a count that shrank as they went
/// would make a short setup feel like a long one.
public enum OnboardingStep: Sendable, Equatable, CaseIterable {
    /// What Uttrflow is for, said before it asks for anything — including before it asks
    /// who you are. Signing in is required to dictate, and a product that demanded an
    /// account on the very first screen would be asking for the price before naming the
    /// thing. One page of pitch first is not burying it; the sign-in page immediately
    /// after says plainly that there is no way past it.
    case welcome
    /// Who this is. Nothing is offered without it.
    case signIn
    case microphone
    case accessibility
    /// The one-time speech model download.
    case setup
    /// What the user ended up able to do.
    case ready

    /// 1-based position in the row of dots.
    ///
    /// Written out rather than derived from ``allCases`` so that reordering the pages
    /// is a deliberate edit in two places rather than a silent renumbering in one.
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

    /// What the rail beside the page calls this step.
    ///
    /// Not the page's own title. "Let Uttrflow hear you" is a sentence addressed to the
    /// reader, and seven of those stacked in a list is not a list — these are nouns, so
    /// the rail can be scanned in the time it takes to glance at it.
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

    /// The steps in the order they are drawn, which is ``position`` and not the order
    /// the cases happen to be written in.
    ///
    /// Sorted rather than trusted: ``position`` is written out by hand precisely so that
    /// reordering the flow is a deliberate edit, and a rail that read `allCases` would
    /// silently disagree with the numbering the rest of the flow uses.
    public static var inOrder: [OnboardingStep] {
        allCases.sorted { $0.position < $1.position }
    }
}

/// What the page the user is looking at is waiting on.
public enum OnboardingDetail: Sendable, Equatable {
    /// Nothing outstanding: the page is being read, not answered.
    case reading

    /// The sign-in page, and what it is waiting on — including the one thing in the
    /// whole product that a missing network stops.
    case signIn(OnboardingSignInState)

    /// A permission page, showing what macOS says about it right now.
    ///
    /// Carries the status rather than a yes/no because the three ways of not having a
    /// permission each need a different button: one can still be asked for, one can
    /// only be changed in System Settings, and one cannot be changed at all.
    case permission(PermissionStatus)

    /// The user has been sent to System Settings. The answer arrives by them coming
    /// back, so the page has to say it is waiting rather than guess.
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

    /// What the sign-in page is doing.
    ///
    /// Falls back to the three providers rather than answering `nil`, because the only
    /// way to reach a sign-in step carrying some other detail is to ask for a page
    /// nobody navigated to, and a page with three live buttons is a better answer to
    /// that than a page with none.
    var signIn: OnboardingSignInState {
        guard case .signIn(let signIn) = self else { return .offering }
        return signIn
    }

}

/// What the user can actually do once onboarding closes.
///
/// Read from the system at the last moment rather than accumulated as the user clicked
/// through: a permission granted on page two can be taken away again on page four, and
/// the last page is the one that makes a promise.
public enum OnboardingReadiness: Sendable, Equatable, CaseIterable {
    /// Everything is in place.
    case ready
    /// Accessibility was passed over, so finished text lands on the clipboard instead
    /// of at the cursor. Dictation itself still works.
    case pastesManually
    /// The download did not finish, so nothing can be recognised yet.
    case needsSpeechModel
    /// Without a microphone nothing runs at all.
    case needsMicrophone
}

/// Where the user is, and what that page is waiting on.
public struct OnboardingState: Sendable, Equatable {
    public let step: OnboardingStep
    public let detail: OnboardingDetail
}
