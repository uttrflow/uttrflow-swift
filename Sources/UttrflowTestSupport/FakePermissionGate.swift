public import UttrflowCore

/// A ``PermissionGate`` whose status can be changed, including in response to being
/// asked — which is how the real microphone prompt behaves.
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
