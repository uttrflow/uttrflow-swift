import Foundation
import Testing
import UttrflowContext
import UttrflowPredict
import UttrflowPredictCapture

@testable import Uttrflow

@Suite("Credential prompts in terminals")
struct TerminalCredentialPromptTests {
    @Test("sudo, ssh and gpg prompts refuse suggestions and learning")
    func credentialPromptsAreSecure() {
        let prompts = [
            "[sudo] password for dev: hidden-reply",
            "dev@example.test's password: hidden-reply",
            "Enter passphrase for key '/Users/example/.ssh/id_ed25519': hidden-reply",
            "Enter passphrase: hidden-reply",
            "PIN: hidden-reply",
            "Security token: hidden-reply",
            "Password for admin: hidden-reply",
            "Password for dev@buildhost: hidden-reply",
            "Password for 'https://dev@example.com': hidden-reply",
            "Token:",
            "Access token: hidden-reply",
            "API token: hidden-reply",
            "Personal access token: hidden-reply",
            "Password (again): hidden-reply",
            "Enter password: hidden-reply",
            "Enter passphrase (empty for no passphrase): hidden-reply",
            "Enter passphrase for /Users/example/.ssh/id_ed25519: hidden-reply",
            "Verification code: hidden-reply",
            "One-time code: hidden-reply",
            "OTP: hidden-reply",
            "Enter PIN: hidden-reply",
            "Passwort: hidden-reply",
            "Enter password： hidden-reply",
            "Passwort： hidden-reply",
            "पासवर्ड: hidden-reply",
            "Enter same passphrase again: hidden-reply",
            "Retype new password: hidden-reply",
            "Old password: hidden-reply",
            "Enter new UNIX password: hidden-reply",
            "Authentication code: hidden-reply",
            "Two-factor code: hidden-reply",
            "Enter MFA code: hidden-reply",
            "Mot de passe : hidden-reply",
            "Contraseña: hidden-reply",
            "Password",
        ]
        var preferences = CapturePreferences()
        preferences.record(.allowed, for: "com.apple.Terminal")

        for value in prompts {
            let snapshot = FocusedFieldSnapshot(
                bundleIdentifier: "com.apple.Terminal", applicationName: "Terminal", role: "AXTextArea",
                value: value, selection: NSRange(location: value.utf16.count, length: 0))
            let reading = SuggestionMoment.reading(of: snapshot)
            let context = SuggestionMoment.context(of: snapshot, millisecondsSinceKeystroke: 1_000)

            #expect(snapshot.isSecure, "prompt: \(value)")
            #expect(snapshot.value == nil, "prompt: \(value)")
            #expect(snapshot.currentLine.isEmpty, "prompt: \(value)")
            #expect(reading.isSecure, "prompt: \(value)")
            #expect(Quieting.reason(context) == .secureField, "prompt: \(value)")
            #expect(
                CaptureGate.refusal(toRecord: "hidden-reply", from: reading, given: preferences)
                    == .secureField,
                "prompt: \(value)")
        }
    }

    @Test("A shell command mentioning a password remains readable")
    func commandRemainsOrdinary() {
        let commands = [
            "echo 'Password: example'", "printf 'Verification code: %s' value", "sudo password:",
            "echo 'Mot de passe : example'", "echo 'Contraseña: example'",
            "code src/App.swift:42", "password for src/App.swift:42", "password for 'https://example.com/a':",
            "token: abc",
        ]

        for command in commands {
            let value = "dev@host:~/dir$ \(command)"
            let snapshot = FocusedFieldSnapshot(
                bundleIdentifier: "com.apple.Terminal", applicationName: "Terminal", role: "AXTextArea",
                value: value, selection: NSRange(location: value.utf16.count, length: 0))

            #expect(!snapshot.isSecure)
            #expect(snapshot.currentLine == command)
        }
    }
}
