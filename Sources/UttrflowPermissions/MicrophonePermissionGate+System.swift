import AVFoundation
import UttrflowCore

/// Wires the gate to the real macOS permission system.
///
/// Everything here is untestable by construction: one of these calls puts a dialog on
/// the user's screen, so no test may run it. Excluded from the coverage gate for the
/// same reason as the microphone driver, and kept short enough that reading it is a
/// sufficient review. All the behaviour worth testing lives in the gate itself.
extension MicrophonePermissionGate {
    /// The gate as the app uses it.
    public init() {
        self.init(
            readStatus: {
                MicrophonePermissionGate.permissionStatus(
                    for: AVCaptureDevice.authorizationStatus(for: .audio)
                )
            },
            requestAccess: { await AVCaptureDevice.requestAccess(for: .audio) }
        )
    }
}
