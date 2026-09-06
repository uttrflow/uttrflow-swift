// Asks for microphone access before a command that needs it.
import ArgumentParser
private import UttrflowCore
private import UttrflowPermissions

/// Exits cleanly unless the microphone is granted, asking once when it never has been.
func requireMicrophoneAccess(announcing prompt: String? = nil) async throws {
    let gate = MicrophonePermissionGate()
    var status = await gate.status()
    if status == .notDetermined {
        if let prompt { print(prompt) }
        status = await gate.request()
    }
    guard status == .granted else {
        throw CleanExit.message(PermissionError.microphoneDenied.userMessage)
    }
}
