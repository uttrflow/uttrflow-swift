// Plans and posts a key press said under the command key: "press enter", "go to the end". See `Docs/commands.md`.
import CoreGraphics
public import UttrflowCore
public import UttrflowPredict

extension KeyStroke {
    /// The stroke a `key` row's `text` names; nil for a name no stroke has.
    public init?(named name: String) {
        switch name {
        case "return": self.init(.return)
        case "tab": self.init(.tab)
        case "escape": self.init(.escape)
        case "documentEnd": self.init(.downArrow, modifiers: .command)
        case "documentStart": self.init(.upArrow, modifiers: .command)
        default: return nil
        }
    }
}

/// What a key command comes to where someone says it.
public enum KeyCommandPlan: Sendable, Equatable {
    /// The stroke to post.
    case post(KeyStroke)
    /// Nothing is posted, with the plain sentence the notice says.
    case refused(reason: String)
}

/// Reads the `key` rows of the spoken-command registry and decides where each may post.
public enum KeyCommand {
    /// The row the whole utterance names, ignoring the recogniser's case and closing mark; nil for anything else.
    public static func row(heard: String) -> SpokenCommand? {
        let keys = heard.split(whereSeparator: \.isWhitespace).map { WordShape(String($0)).key }
        return SpokenCommands.keys.first { $0.words == keys }
    }

    /// What `row` does in `destination`: a secure field refuses every key, and each row lists where it posts.
    public static func plan(
        _ row: SpokenCommand, in destination: Destination, isSecure: Bool
    ) -> KeyCommandPlan {
        guard !isSecure else { return .refused(reason: "Key commands never reach a password field.") }
        guard row.isEnabled(in: destination) else {
            return .refused(reason: "That key command is off here, so no key was pressed.")
        }
        guard let stroke = KeyStroke(named: row.text) else {
            return .refused(reason: "That key command has no key, so no key was pressed.")
        }
        return .post(stroke)
    }
}

/// Posts a key stroke to the app in front.
public protocol KeyStrokePosting: Sendable {
    func post(_ stroke: KeyStroke) throws(TextInsertionError)
}

/// Posts through the HID event tap, tagged as this app's own so its taps never act on it.
public struct SystemKeyStrokePoster: KeyStrokePosting {
    public init() {}

    public func post(_ stroke: KeyStroke) throws(TextInsertionError) {
        guard let keyCode = stroke.key.keyCode, let source = CGEventSource(stateID: .hidSystemState) else {
            throw .insertionRejected(description: "could not create the keystroke")
        }
        let flags = stroke.modifiers.eventFlags
        let pair = try makeTaggedKeyPair(from: source, keyCode: CGKeyCode(keyCode)) { $0.flags = flags }
        postTaggedKeyPairs([pair])
    }
}
