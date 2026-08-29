public import UttrflowAccount

/// Whether a request could even be attempted right now.
///
/// Read rather than monitored, and answered synchronously, because the only two moments
/// that need it are entering the sign-in page and pressing Try Again. A real
/// implementation keeps the last path `NWPathMonitor` reported and hands it over; there
/// is nothing here for it to subscribe to.
///
/// It exists at all because ``OnboardingSignInState/unreachable`` has to be shown
/// *before* the user presses anything. Learning about the missing connection from a
/// failed exchange would mean three live buttons that all lead to the same apology,
/// which is the spinner the approved design was drawn to avoid.
public protocol NetworkReachability: Sendable {
    var isReachable: Bool { get }
}

/// What the sign-in page is doing.
///
/// The one page in the whole product that cannot work offline, so the one page with a
/// state for it. Every other page reads a permission or a file and works on a plane.
public enum OnboardingSignInState: Sendable, Equatable {
    /// The three providers, live, waiting to be chosen.
    case offering

    /// There is no connection. The providers stay on screen and inert, because a person
    /// who can see what they will be able to press understands the situation better than
    /// one looking at an empty panel.
    case unreachable

    /// The browser has the user, or the code is being exchanged.
    ///
    /// Both halves look the same from here and both are waiting on somewhere else, so
    /// they are one state rather than two the interface would draw identically.
    case signingIn(SignInProvider)

    /// This Mac could not be redirected back to, so the person types a code instead.
    ///
    /// A separate state rather than a variant of ``signingIn`` because the page is
    /// genuinely different: it has something to read off the screen, and somebody who is
    /// told "finish in your browser" while a code sits unmentioned will not type it.
    case enterCode(SignInProvider, code: String)

    /// Somebody answered and said no. The providers come back live: another attempt, or
    /// another provider, is a real choice and the only remedy there is.
    case refused(String)
}

extension OnboardingSignInState {
    /// Whether the three provider buttons can be pressed.
    var acceptsAProvider: Bool {
        switch self {
        case .offering, .refused: true
        case .unreachable, .signingIn, .enterCode: false
        }
    }
}
