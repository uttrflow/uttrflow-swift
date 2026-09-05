/// A result a fake produces when called, so every fake scripts success and failure the same way.
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

/// An append-only, concurrency-safe record of what a fake was asked to do, shared by every fake.
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
