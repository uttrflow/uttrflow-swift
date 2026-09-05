// When a downloaded update may replace the running app: only after a minute of quiet.
public import struct Foundation.Date
public import typealias Foundation.TimeInterval

/// What the app is in the middle of, as far as an update is concerned: four things a relaunch would spoil.
public struct UpdateActivity: Sendable, Equatable {
    /// A dictation is running, or the key is held.
    public let isDictating: Bool
    /// The quick panel is on screen.
    public let isPanelOpen: Bool
    /// Something is being typed into the main window that has not been saved.
    public let isEditing: Bool
    /// First-run onboarding is on screen.
    public let isOnboarding: Bool

    /// Everything off unless said otherwise.
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

/// When a downloaded update may replace the app: after a spell of quiet, never mid-sentence or on quit.
public struct UpdateGate: Sendable, Equatable {
    /// How long the app must have been quiet: a minute, so putting the panel away does not count as quiet.
    public static let settleSeconds: TimeInterval = 60

    /// How long quiet must last.
    private let settle: TimeInterval
    /// When the app last became quiet, or `nil` while it is not.
    private var quietSince: Date?

    /// Starts not quiet, with the given settling time.
    public init(settle: TimeInterval = UpdateGate.settleSeconds) {
        self.settle = settle
        self.quietSince = nil
    }

    /// Records what the app is doing; anything but quiet clears the clock rather than pausing it.
    public mutating func note(_ activity: UpdateActivity, at now: Date) {
        guard activity.isQuiet else {
            quietSince = nil
            return
        }
        // Already quiet: the clock keeps its start, or a state reported on a timer would never open the gate.
        if quietSince == nil { quietSince = now }
    }

    /// Whether a staged update may install now.
    public func mayInstall(at now: Date) -> Bool {
        guard let quietSince else { return false }
        return now.timeIntervalSince(quietSince) >= settle
    }

    /// How long the app has been quiet, for a status line; `nil` when it is not quiet at all.
    public func quietDuration(at now: Date) -> TimeInterval? {
        quietSince.map { now.timeIntervalSince($0) }
    }
}
