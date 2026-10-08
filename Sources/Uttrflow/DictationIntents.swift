import AppIntents
import UttrflowPipeline

@MainActor
enum DictationIntentBridge {
    static var run: @MainActor (DictationCommand) async -> DictationCommandOutcome = { _ in .nothingRecording
    }

    /// Runs a command and words its outcome for VoiceOver and the Shortcuts app to speak.
    static func respond(to command: DictationCommand) async -> some IntentResult & ProvidesDialog {
        let outcome = await run(command)
        return .result(dialog: IntentDialog(stringLiteral: spoken(outcome)))
    }

    static func spoken(_ outcome: DictationCommandOutcome) -> String {
        switch outcome {
        case .started: "Listening"
        case .finished: "Stopped, inserting your words"
        case .cancelled: "Cancelled, nothing was inserted"
        case .alreadyRecording: "Already listening"
        case .nothingRecording: "Nothing was recording"
        case .didNotStart: "Dictation could not start"
        }
    }
}

struct ToggleDictationIntent: AppIntent {
    static let title: LocalizedStringResource = "Toggle Dictation"
    static let description = IntentDescription("Start or stop dictation in Uttrflow.")
    static let openAppWhenRun = false

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        await DictationIntentBridge.respond(to: .toggle)
    }
}

struct StartDictationIntent: AppIntent {
    static let title: LocalizedStringResource = "Start Dictation"
    static let description = IntentDescription(
        "Start dictation in Uttrflow; does nothing if it is already listening.")
    static let openAppWhenRun = false

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        await DictationIntentBridge.respond(to: .start)
    }
}

struct StopDictationIntent: AppIntent {
    static let title: LocalizedStringResource = "Stop Dictation"
    static let description = IntentDescription(
        "Stop dictation in Uttrflow and insert the words; does nothing if it is not listening.")
    static let openAppWhenRun = false

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        await DictationIntentBridge.respond(to: .stop)
    }
}

struct CancelDictationIntent: AppIntent {
    static let title: LocalizedStringResource = "Cancel Dictation"
    static let description = IntentDescription(
        "Discard the dictation in Uttrflow without inserting anything, as Escape does.")
    static let openAppWhenRun = false

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        await DictationIntentBridge.respond(to: .cancel)
    }
}

struct UttrflowAppShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: StartDictationIntent(),
            phrases: ["Start dictation in \(.applicationName)"],
            shortTitle: "Start Dictation",
            systemImageName: "mic")
        AppShortcut(
            intent: StopDictationIntent(),
            phrases: ["Stop dictation in \(.applicationName)"],
            shortTitle: "Stop Dictation",
            systemImageName: "stop.circle")
        AppShortcut(
            intent: CancelDictationIntent(),
            phrases: ["Cancel dictation in \(.applicationName)"],
            shortTitle: "Cancel Dictation",
            systemImageName: "xmark.circle")
        AppShortcut(
            intent: ToggleDictationIntent(),
            phrases: ["Toggle dictation in \(.applicationName)"],
            shortTitle: "Toggle Dictation",
            systemImageName: "mic.badge.plus")
    }
}
