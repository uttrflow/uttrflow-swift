import UttrflowCore

/// Decides whether a clip needs a confirmation before it is pasted, because a newline runs a command in a shell.
public enum MultilinePasteCheck {
    /// How many lines the clip holds, with a trailing line break ending the last line rather than starting another.
    public static func lineCount(of text: String) -> Int {
        let lines = text.split(omittingEmptySubsequences: false, whereSeparator: \.isNewline)
        return text.last?.isNewline == true ? lines.count - 1 : lines.count
    }

    /// Whether the clip has a line break in its middle or at its end.
    public static func hasLineBreak(_ text: String) -> Bool {
        text.contains(where: \.isNewline)
    }

    /// The question to ask, or `nil` when the clip can go straight in.
    public static func question(
        for text: String, into bundleIdentifier: String?, isOn: Bool = true
    ) -> String? {
        guard isOn, hasLineBreak(text), let bundleIdentifier,
            TerminalApplications.contains(bundleIdentifier)
        else { return nil }
        let lines = lineCount(of: text)
        guard lines > 1 else { return "This clip ends with a new line. Paste anyway?" }
        return "This clip has \(lines) lines. Paste anyway?"
    }
}
