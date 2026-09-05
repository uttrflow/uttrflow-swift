// A PermissionGate whose answer a test controls.
public import UttrflowCore

/// A ``PermissionGate`` whose status can change, including in response to being asked, like the real prompt.
public actor FakePermissionGate: PermissionGate {
    public enum Event: Sendable, Equatable {
        case status
        case request
    }

    public let kind: PermissionKind
    public let calls = CallLog<Event>()

    private var currentStatus: PermissionStatus
    private var statusAfterRequest: PermissionStatus?

    public init(
        kind: PermissionKind = .microphone,
        status: PermissionStatus = .notDetermined,
        statusAfterRequest: PermissionStatus? = .granted
    ) {
        self.kind = kind
        self.currentStatus = status
        self.statusAfterRequest = statusAfterRequest
    }

    public func status() async -> PermissionStatus {
        await calls.append(.status)
        return currentStatus
    }

    public func request() async -> PermissionStatus {
        await calls.append(.request)
        if let statusAfterRequest {
            currentStatus = statusAfterRequest
        }
        return currentStatus
    }

    // MARK: Scripting

    public func setStatus(_ status: PermissionStatus) {
        currentStatus = status
    }
}
