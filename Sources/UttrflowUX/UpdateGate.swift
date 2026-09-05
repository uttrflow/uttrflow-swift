public import struct Foundation.Date
public import typealias Foundation.TimeInterval

/// What the app is in the middle of, as far as installing an update is concerned.
///
/// Four facts and nothing else. Deliberately not "is the app busy": the question an
/// updater asks is narrower than that, and each of these is something a relaunch would
/// visibly destroy — a sentence half spoken, a panel someone is reading, an edit not yet
/// saved, a first run not yet finished.
public struct UpdateActivity: Sendable, Equatable {
    /// A dictation is running, or the key is held.
    public let isDictating: Bool
    /// The quick panel is on screen.
    public let isPanelOpen: Bool
    /// Something is being typed into the main window that has not been saved.
    public let isEditing: Bool
    /// First-run onboarding is on screen.
    public let isOnboarding: Bool

    public init(
        isDictating: Bool = false,
        isPanelOpen: Bool = false,
        isEditing: Bool = false,
        isOnboarding: Bool = false
    ) {
        self.isDictating = isDictating
        self.isPanelOpen = isPanelOpen
        self.isEditing = isEditing
        self.isOnboarding = isOnboarding
    }

    /// Nothing an update would interrupt.
    public var isQuiet: Bool {
        !isDictating && !isPanelOpen && !isEditing && !isOnboarding
    }
}

/// When a downloaded update may replace the running app.
///
/// The whole of the product's opinion about updating, in one testable value. Sparkle's
/// own answer is "on quit", which for a menu-bar app that is opened once and never quit
/// means never; its other answer is to ask, which interrupts the person mid-sentence in
/// somebody else's window — the exact moment this product exists to keep smooth.
///
/// So the rule is neither: install when the app has been quiet for a while. If the Mac is
/// busy all day the update waits until tomorrow, and that is the correct outcome rather
/// than a failure. An update is worth nothing next to a dictation it swallowed.
///
/// A value with a clock passed in, not a timer: "has it been quiet for a minute" is a
/// question about two instants, and answering it in a type that owns a `Timer` is what
/// makes a rule like this untestable and therefore wrong in ways nobody notices.
public struct UpdateGate: Sendable, Equatable {
    /// How long the app must have been quiet. A minute: long enough that putting the
    /// panel away and reaching for the keyboard again does not count as quiet, short
    /// enough that a coffee is an opportunity.
    public static let settleSeconds: TimeInterval = 60

    private let settle: TimeInterval
    /// When the app last became quiet, or `nil` while it is not.
    private var quietSince: Date?

    public init(settle: TimeInterval = UpdateGate.settleSeconds) {
        self.settle = settle
        self.quietSince = nil
    }

    /// Records what the app is doing. Call it whenever any of the four facts changes.
    ///
    /// Anything but quiet clears the clock rather than pausing it: an update that
    /// installed because somebody was quiet for fifty seconds, spoke, and went quiet for
    /// ten more has interrupted them at the fifty-ninth second of a minute they never had.
    public mutating func note(_ activity: UpdateActivity, at now: Date) {
        guard activity.isQuiet else {
            quietSince = nil
            return
        }
        // Already quiet: the clock started when it started, not on every redraw. Without
        // this the gate never opens on an app that reports its state on a timer.
        if quietSince == nil { quietSince = now }
    }

    /// Whether a staged update may install now.
    public func mayInstall(at now: Date) -> Bool {
        guard let quietSince else { return false }
        return now.timeIntervalSince(quietSince) >= settle
    }

    /// How long the app has been quiet, for a status line that says why nothing has
    /// happened yet. `nil` when it is not quiet at all.
    public func quietDuration(at now: Date) -> TimeInterval? {
        quietSince.map { now.timeIntervalSince($0) }
    }
}
