public import UttrflowCore
import AVFoundation

/// Reads and requests microphone access.
///
/// The two system calls are injected, in the product's own vocabulary rather than
/// AVFoundation's, so every branch — including ones macOS will not let a test reach,
/// like a policy-restricted device — is exercised without touching real permissions.
public struct MicrophonePermissionGate: PermissionGate {
    private let readStatus: @Sendable () -> PermissionStatus
    private let requestAccess: @Sendable () async -> Bool

    public let kind: PermissionKind = .microphone

    /// Substitutes both system calls. The public `init()` that wires up the real ones
    /// lives alongside them, in `MicrophonePermissionGate+System.swift`.
    init(
        readStatus: @escaping @Sendable () -> PermissionStatus,
        requestAccess: @escaping @Sendable () async -> Bool
    ) {
        self.readStatus = readStatus
        self.requestAccess = requestAccess
    }

    public func status() async -> PermissionStatus {
        readStatus()
    }

    public func request() async -> PermissionStatus {
        // macOS prompts once and never again. Asking a user who has already decided
        // returns their decision immediately, so re-reading is the honest answer
        // rather than pretending a prompt appeared.
        guard readStatus() == .notDetermined else { return readStatus() }
        return await requestAccess() ? .granted : .denied
    }

    /// Maps the system's authorisation states onto the product's.
    static func permissionStatus(for status: AVAuthorizationStatus) -> PermissionStatus {
        switch status {
        case .notDetermined: .notDetermined
        case .authorized: .granted
        case .denied: .denied
        case .restricted: .restricted
        @unknown default: .denied
        }
    }
}
