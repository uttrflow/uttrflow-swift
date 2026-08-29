/// A result a fake should produce when called.
///
/// Every fake in this module resolves its behaviour through this one type, so
/// "succeed with X" and "fail with Y" are expressed identically everywhere and no
/// fake grows its own ad-hoc `shouldThrow` flags.
public enum ScriptedOutcome<Success: Sendable, Failure: Error>: Sendable {
    case success(Success)
    case failure(Failure)

    public func resolve() throws(Failure) -> Success {
        switch self {
        case .success(let value): value
        case .failure(let error): throw error
        }
    }
}

extension ScriptedOutcome where Success == Void {
    /// Shorthand for a fake that simply does nothing successfully.
    public static var ok: Self { .success(()) }
}

/// An append-only, concurrency-safe record of what a fake was asked to do.
///
/// Shared by every fake so that assertions read the same way regardless of which
/// collaborator is under test.
public actor CallLog<Event: Sendable> {
    public private(set) var events: [Event] = []

    public init() {}

    public func append(_ event: Event) {
        events.append(event)
    }

    public var count: Int { events.count }
    public var isEmpty: Bool { events.isEmpty }
    public var last: Event? { events.last }
}

extension CallLog where Event: Equatable {
    public func contains(_ event: Event) -> Bool {
        events.contains(event)
    }
}
