// What the user has said about learning from each application, read by every learner on this Mac.

/// Whether the user has been asked about an application, and what they said.
public enum ConsentState: String, Sendable, Codable, Equatable, CaseIterable {
    /// The user has not been asked about this application.
    case unknown
    /// The user has opted this application in.
    case allowed
    /// The user has said no to this application.
    case declined

    /// How careful this answer is, so folding two spellings of one application never loses a refusal.
    package var caution: Int {
        switch self {
        case .unknown: 0
        case .allowed: 1
        case .declined: 2
        }
    }

    /// Whether dictation may learn here: only a refusal stops it, since nothing it learns leaves this Mac.
    public var dictationMayLearn: Bool { self != .declined }
}

/// The one question a dictation learner asks before it writes anything about an application.
public protocol LearningConsent: Sendable {
    /// What was said about this application, `.unknown` when the destination was not identified; synchronous, so a writer reads it in the step that writes.
    func state(of bundleIdentifier: String?) -> ConsentState
}

extension LearningConsent {
    /// Whether dictation may learn from words that landed in this application.
    public func mayLearn(from bundleIdentifier: String?) -> Bool {
        state(of: bundleIdentifier).dictationMayLearn
    }
}

/// Per-application answers behind the one switch in Settings: while it is off, every application is declined.
public struct SwitchedLearningConsent: LearningConsent {
    /// Whether the person lets dictation learn at all, read at each dictation so a change counts at once.
    private let isOn: @Sendable () -> Bool
    /// What was said about each application, consulted only while the switch is on.
    private let answers: any LearningConsent

    /// Answers that hold only while `isOn` says so.
    public init(isOn: @escaping @Sendable () -> Bool, answers: any LearningConsent) {
        self.isOn = isOn
        self.answers = answers
    }

    /// Declined everywhere while the switch is off, otherwise what was said about this application.
    public func state(of bundleIdentifier: String?) -> ConsentState {
        guard isOn() else { return .declined }
        return answers.state(of: bundleIdentifier)
    }
}

/// Consent where nothing has been asked about any application, for callers without a store.
public struct NothingAskedYet: LearningConsent {
    /// Consent with no answers.
    public init() {}

    /// Unknown, for every application.
    public func state(of bundleIdentifier: String?) -> ConsentState { .unknown }
}
