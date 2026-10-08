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
    /// What was said about this application, `.unknown` when the destination was not identified.
    func state(of bundleIdentifier: String?) async -> ConsentState
}

extension LearningConsent {
    /// Whether dictation may learn from words that landed in this application.
    public func mayLearn(from bundleIdentifier: String?) async -> Bool {
        await state(of: bundleIdentifier).dictationMayLearn
    }
}

/// Consent where nothing has been asked about any application, for callers without a store.
public struct NothingAskedYet: LearningConsent {
    /// Consent with no answers.
    public init() {}

    /// Unknown, for every application.
    public func state(of bundleIdentifier: String?) async -> ConsentState { .unknown }
}
