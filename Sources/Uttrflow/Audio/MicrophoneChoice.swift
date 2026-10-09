// The input device the user chose, shared with capture, which reads it off the main actor at every open.
import Synchronization
import UttrflowSettings

/// Holds the chosen input UID; settings write it and every capture open reads it.
final class MicrophoneChoice: Sendable {
    private let uid = Mutex<String?>(nil)

    /// The UID the next open asks for; nil follows the system default.
    var current: String? { uid.withLock { $0 } }

    /// Follows the saved setting from the next open on.
    func apply(_ settings: Settings) {
        uid.withLock { $0 = settings.microphoneUID }
    }
}
