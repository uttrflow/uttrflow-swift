// Edit commands spoken while the command key is held. See `Docs/commands.md`.
public import UttrflowCore

/// Where a finished utterance goes, decided by which key was held, never by its words.
public enum UtteranceRoute: Sendable, Equatable {
    /// Typed at the caret.
    case dictation
    /// Run as an edit on the selection; nothing heard is typed.
    case command
}

/// One edit a command-key utterance can run against the selection.
public protocol EditCommand: Sendable {
    /// Whether these recognised words ask for this command.
    func accepts(_ heard: String) -> Bool

    /// Carries the command out on the app as it stood when the key was let go.
    func run(_ heard: String, on target: AppContext) async throws
}

/// What running a command-key utterance came to.
public enum EditCommandOutcome: Sendable, Equatable {
    /// A command accepted the words and finished.
    case ran
    /// No command accepted the words, so nothing was changed.
    case notUnderstood
}

/// Every edit command, asked in order; the first that accepts the words runs.
public struct EditCommandRegistry: Sendable {
    private let commands: [any EditCommand]

    /// A registry of these commands, which is empty until one plugs in.
    public init(_ commands: [any EditCommand] = []) {
        self.commands = commands
    }

    /// Runs the first command that accepts the words, rethrowing its failure.
    public func run(_ heard: String, on target: AppContext) async throws -> EditCommandOutcome {
        guard let command = commands.first(where: { $0.accepts(heard) }) else { return .notUnderstood }
        try await command.run(heard, on: target)
        return .ran
    }
}

extension DictationFailure {
    /// Said when the held command key heard words no command takes; the words stay on the notice.
    static func commandNotUnderstood(_ heard: String) -> DictationFailure {
        DictationFailure(
            message: "That isn't an edit command Uttrflow knows, so nothing was changed.",
            recovery: nil, severity: .recoverable, transcript: heard)
    }
}
