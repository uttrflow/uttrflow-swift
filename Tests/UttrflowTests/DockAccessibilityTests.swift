// Tests what VoiceOver is told about the floating button: what it is doing, and what activating it does.

import UttrflowCore
import UttrflowPipeline
import Testing

@testable import Uttrflow

@MainActor
@Suite("What the floating button tells VoiceOver")
struct DockAccessibilityTests {
    /// One value of every recovery the button can offer, since an associated value keeps the enum uncountable.
    nonisolated private static let everyRecovery: [RecoveryAction] = [
        .openSystemSettings(.accessibility), .retry, .downloadSpeechModel, .pasteManually,
        .copyTranscript,
        .showHistory, .retryFromRecording,
    ]

    /// Every state the button draws, so a new one cannot be added without something to say about it.
    nonisolated private static let everyState: [DictationState] = [
        .idle,
        .recording,
        .transcribing,
        .tidying,
        .inserting(into: nil),
        .inserted(DictationOutcome(text: "see you at noon", method: .accessibility, cleanedBy: .rules)),
        .failed(DictationFailure(PermissionError.microphoneDenied)),
        .failed(.stillLoading),
    ]

    @Test("says it is listening while it records, and says nothing about state at rest")
    func listeningIsAValue() {
        #expect(DockView.spokenValue(for: DictationPresenter.dock(for: .recording)) == "Listening")
        #expect(DockView.spokenValue(for: DictationPresenter.dock(for: .tidying)) == "Working")
        #expect(DockView.spokenValue(for: DictationPresenter.dock(for: .idle)).isEmpty)
    }

    @Test("says what activating it does, in both directions")
    func hintSaysWhatActivatingDoes() {
        #expect(DockView.spokenHint(for: DictationPresenter.dock(for: .idle)) == "Starts a dictation.")
        #expect(DockView.spokenHint(for: DictationPresenter.dock(for: .recording)) == "Stops listening.")
    }

    @Test("names the recovery it offers, in the words its own button draws", arguments: everyRecovery)
    func hintNamesTheRecovery(_ action: RecoveryAction) {
        let failure = DictationFailure(
            message: "Something went wrong.", recovery: action, severity: .recoverable)
        let hint = DockView.spokenHint(for: DictationPresenter.dock(for: .failed(failure)))

        #expect(!DockView.title(for: action).isEmpty)
        #expect(hint.contains(DockView.title(for: action)), "\(action) is not named in \(hint)")
        #expect(hint.hasPrefix("Starts a dictation."), "\(action) hides the button's own action")
    }

    @Test("recovery buttons use the specific shared action titles")
    func recoveryTitlesNameTheirDestination() {
        #expect(DockView.title(for: .openSystemSettings(.microphone)) == "Open System Settings")
        #expect(DockView.title(for: .downloadSpeechModel) == "Finish Setup")
    }

    @Test("names a setup form's button in the words the form draws")
    func hintNamesTheSetupButton() {
        let failed = DictationPresenter.dock(for: .idle, speechModel: .failed)
        let missing = DictationPresenter.dock(for: .idle, speechModel: .missing)

        #expect(DockView.spokenHint(for: failed) == "Starts a dictation. Retry is available as an action.")
        #expect(
            DockView.spokenHint(for: missing) == "Starts a dictation. Download is available as an action.")
        #expect(DockView.title(for: .retry, in: DictationPresenter.dock(for: .idle)) == "Try Again")
    }

    @Test("has something to say in every state it can be drawn in", arguments: everyState)
    func everyStateIsSpoken(_ state: DictationState) {
        let presentation = DictationPresenter.dock(for: state)

        #expect(!presentation.accessibilityLabel.isEmpty, "\(state) has no label")
        #expect(!DockView.spokenHint(for: presentation).isEmpty, "\(state) has no hint")
    }
}
