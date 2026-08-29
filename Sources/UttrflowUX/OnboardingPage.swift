public import UttrflowAccount
public import UttrflowCore

/// What one onboarding page draws.
///
/// The view renders this and nothing else, so the four designs are four values rather
/// than four screens' worth of conditions, and a page cannot say one thing while its
/// buttons do another.
public struct OnboardingPage: Sendable, Equatable {
    /// SF Symbol for the glyph at the top, or `nil` on the page that shows the mark.
    public let symbolName: String?
    public let emphasis: OnboardingEmphasis
    public let title: String
    public let subtitle: String
    /// The paragraph under the subtitle. Absent where the design puts something else
    /// there, such as the download's progress bar.
    public let body: String?
    /// The quieter caveat under the body, if this page has one.
    public let note: OnboardingNote?
    /// A sign-in code to show, when this Mac could not be redirected back to.
    ///
    /// Its own field rather than borrowed from ``keys``: those are keycaps somebody
    /// presses, this is characters somebody types into another window, and a renderer that
    /// could not tell them apart would style one as the other.
    public let code: String?
    /// Keycaps to draw, for example `["⌥", "Space"]`. Empty on every page but the last.
    public let keys: [String]
    /// Download progress from `0` to `1`, or `nil` when nothing is downloading.
    public let progress: Double?
    /// The stacked provider buttons. Empty on every page but sign-in, which is the only
    /// page whose choices are three answers to one question rather than a row of verbs.
    public let providers: [OnboardingProviderButton]
    /// In reading order. The prominent one, where there is one, comes last.
    public let buttons: [OnboardingButton]
    /// The smallest line on the page — the terms a person is agreeing to. Only sign-in
    /// has one, and it is on the page rather than behind a link because agreeing to
    /// something invisible is not agreeing.
    public let fineprint: String?
    /// 1-based position in the row of dots, and how many dots there are.
    public let position: Int
    public let stepCount: Int
    /// Read aloud by VoiceOver. Never abbreviated, never an icon name.
    public let accessibilityLabel: String
}

extension OnboardingPage {
    /// Whether there is anything at all on this page the user can press.
    ///
    /// Counts the provider stack as well as the button row, because on the sign-in page
    /// the providers are the whole of what there is to do. The rule this answers — no
    /// page is ever a dead end — is about what a person can act on, not about which
    /// collection it arrived in.
    public var hasSomethingToPress: Bool {
        buttons.contains(where: \.isEnabled) || providers.contains(where: \.isEnabled)
    }
}

/// How the glyph at the top of a page is drawn.
public enum OnboardingEmphasis: Sendable, Equatable {
    /// The app's own mark on a lilac wash. The first page only.
    case brand
    /// A plain slab. What a page that is asking for something wears.
    case neutral
    /// Something did not work and the page is about that: a download that stopped, a
    /// check that found nothing, a microphone that is still off at the end.
    ///
    /// Its own case rather than ``neutral`` because those pages were drawn identically to
    /// the ones that are merely asking a question — the same tile, the same colour — and
    /// a page reporting a failure that looks like a page making a request is a page whose
    /// most important fact is carried by its wording alone.
    case caution
    /// Reserved for the pages that say a piece of the setting up is over.
    case success
}

/// A quieter line under the body, saying what the user is trading away or keeping.
public struct OnboardingNote: Sendable, Equatable {
    /// How loudly the note is drawn, and — because the approved screens differ on this
    /// — whether it sits above what it is about or below it.
    ///
    /// A warning that explains why the buttons underneath will not work has to be read
    /// before them; a reassurance about what happens afterwards does not.
    public enum Tone: Sendable, Equatable {
        /// Explaining or reassuring. Drawn under the thing it is about.
        case quiet
        /// Something is wrong and the page cannot proceed. Drawn above.
        case warning
    }

    public let symbolName: String
    public let text: String
    public let tone: Tone

    init(symbolName: String, text: String, tone: Tone = .quiet) {
        self.symbolName = symbolName
        self.text = text
        self.tone = tone
    }
}

/// One provider's button on the sign-in page.
///
/// Carries the provider rather than an icon name because each mark is drawn to its
/// owner's rules — Apple's on the opposite ground in each appearance, Google's in its
/// own four colours — and a string naming an SF Symbol could not express any of that.
public struct OnboardingProviderButton: Sendable, Equatable {
    public let provider: SignInProvider
    /// What the button says, which each provider dictates rather than we choose.
    public let title: String
    /// Offline, the three stay on screen and inert. Seeing what you will be able to
    /// press tells you more about the situation than an empty panel does.
    public let isEnabled: Bool

    init(provider: SignInProvider, isEnabled: Bool) {
        self.provider = provider
        self.title = provider.buttonTitle
        self.isEnabled = isEnabled
    }
}

/// One button on a page.
public struct OnboardingButton: Sendable, Equatable {
    public let title: String
    public let intent: OnboardingIntent
    /// The answer the page is steering towards. At most one per page.
    public let isProminent: Bool
    /// Drawn but not pressable. The download page keeps "Continue" in view while the
    /// download runs so the row of buttons does not change shape when it finishes.
    public let isEnabled: Bool
}

extension OnboardingButton {
    /// The answer the page is steering towards.
    static func prominent(_ title: String, _ intent: OnboardingIntent) -> OnboardingButton {
        OnboardingButton(title: title, intent: intent, isProminent: true, isEnabled: true)
    }

    /// The quieter answer beside it — usually the one that does without something.
    static func plain(_ title: String, _ intent: OnboardingIntent) -> OnboardingButton {
        OnboardingButton(title: title, intent: intent, isProminent: false, isEnabled: true)
    }

    /// Somewhere to look while waiting. Pressing it can do nothing, so it means
    /// nothing, and it carries the intent it will have once it comes alive.
    static func disabled(_ title: String) -> OnboardingButton {
        OnboardingButton(title: title, intent: .advance, isProminent: true, isEnabled: false)
    }
}

/// What pressing a button means.
public enum OnboardingIntent: Sendable, Equatable {
    /// Leave this page.
    ///
    /// One case rather than separate "continue" and "skip" ones, because they are the
    /// same instruction: go on from here. Whether that was progress or a decision to
    /// do without something is carried by the button's wording, and the consequence is
    /// read back off the system on the last page rather than remembered from a click.
    case advance

    /// Ask macOS for a permission it has not been asked about yet.
    case requestPermission(PermissionKind)

    /// One of the recoveries the rest of the app already speaks: open a settings pane,
    /// look again, or fetch the speech model. Shared with ``RecoveryAction`` so that
    /// onboarding and the error presentation offer the user the same verbs.
    case recover(RecoveryAction)

    /// Stop the download and go on without the model.
    case cancelInstall

    /// Sign in with this provider. The only intent that needs a network.
    case signIn(SignInProvider)

    /// Give up on a sign-in that is somewhere else — in a browser tab, or in an
    /// exchange that is taking too long — and go back to the three providers.
    case cancelSignIn

    /// Carry on with no account at all, as whoever macOS says owns this Mac.
    ///
    /// Its own intent rather than ``advance``, because it is not passing over a page: it
    /// records a decision, and the page after it is different because of one. See
    /// ``LocalAccount``.
    case continueOnThisMac

    /// Close onboarding. Only ever offered on the last page.
    case finish
}
