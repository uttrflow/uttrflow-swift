public import UttrflowCore

/// Whether the last sentence is given a full stop when it has no ending.
public enum TerminalStopPolicy: Sendable, Equatable {
    case always
    case never
}

/// Adds the final full stop, unless the text holds a line break or already ends.
public struct TerminalStopPass: CleaningPass {
    public static let id: PassID = "terminalStop"

    public let policy: TerminalStopPolicy

    public init(policy: TerminalStopPolicy = .always) {
        self.policy = policy
    }

    public func apply(_ draft: Draft) -> Draft {
        guard policy == .always, let last = draft.presentIndices.last else { return draft }
        let text = draft.text
        guard TextTidy.ensureTerminalPunctuation(text) != text else { return draft }
        var draft = draft
        draft.replace(at: last, with: draft.words[last].text + ".", by: Self.id)
        return draft
    }
}
