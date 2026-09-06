import AVFoundation
import UttrflowCore

/// Wires the gate to AVFoundation; untestable because one call shows a dialog, so kept short enough to read.
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
