public import UttrflowCore

/// Types text as key events, the one route into a hidden field that never borrows the clipboard.
public protocol KeystrokeTyping: Sendable {
    /// Types `text` into whatever has focus.
    func type(_ text: String) throws(TextInsertionError)

    /// Presses Delete `count` times, which is the only way this route takes typed characters back.
    func deleteBackwards(_ count: Int) throws(TextInsertionError)
}

/// Puts text in by typing it, for the fields Accessibility cannot write into.
public struct TypedTextInsertionEngine: TextInsertionEngine {
    public let method: TextInsertionMethod = .typed

    private let focus: any AccessibilityFocus
    private let typist: any KeystrokeTyping

    public init(focus: any AccessibilityFocus, typist: any KeystrokeTyping) {
        self.focus = focus
        self.typist = typist
    }

    /// Anything but ourselves; Electron apps expose no focused element and still take typing.
    public func canInsert() async -> Bool { !focus.isSelfFrontmost() }

    public func insert(_ text: String) async throws(TextInsertionError) {
        try typist.type(text)
    }
}

extension TypedTextInsertionEngine: CompletionWriting {
    public func canWrite() async -> Bool { await canInsert() }

    /// Backspaces then types, which the target's undo sees as several edits. See `Docs/predict-accept.md`.
    public func write(_ text: String, replacing replaced: String) async throws(TextInsertionError) {
        let count = replaced.count
        if count > 0 {
            // A blind backspace could eat a shell prompt, so what is there is checked when the field will say.
            if let preceding = focus.precedingText(count), preceding != replaced {
                throw .insertionRejected(
                    description: "the text before the caret is not what would be replaced")
            }
            try typist.deleteBackwards(count)
        }
        try typist.type(text)
    }
}
