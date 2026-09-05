public import UttrflowCore
import AVFoundation

/// Reads and requests microphone access; the two system calls are injected so tests reach every branch.
public struct MicrophonePermissionGate: PermissionGate {
    /// Reads the current authorisation in the product's vocabulary.
    private let readStatus: @Sendable () -> PermissionStatus
    /// Shows the system prompt and answers whether the user allowed it.
    private let requestAccess: @Sendable () async -> Bool

    /// Names this gate as the microphone permission.
    public let kind: PermissionKind = .microphone

    /// Substitutes both system calls; the real wiring lives in `MicrophonePermissionGate+System.swift`.
    init(
        readStatus: @escaping @Sendable () -> PermissionStatus,
        requestAccess: @escaping @Sendable () async -> Bool
    ) {
        self.readStatus = readStatus
        self.requestAccess = requestAccess
    }

    /// The permission as it stands right now.
    public func status() async -> PermissionStatus {
        readStatus()
    }

    /// Prompts only while undecided; otherwise returns the decision the user already made.
    public func request() async -> PermissionStatus {
        // macOS prompts once only, so a user who has decided gets that decision back, not a prompt.
        let current = readStatus()
        guard current == .notDetermined else { return current }
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
