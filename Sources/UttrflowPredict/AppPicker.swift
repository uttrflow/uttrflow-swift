import UttrflowCore

/// The characters that open an application's own completion picker, whose Tab and Escape belong to it.
public enum AppPicker {
    private static let pickerApplications =
        DestinationRules.bundlePrefixes(of: [.chat]) + ["notion.id"]

    /// A word starting with one of these opens a picker: `@` a mention, `:` an emoji shortcode, `#` a channel.
    public static let wordTriggers: Set<Character> = ["@", ":", "#"]

    /// A line starting with one of these opens a command picker, such as `/` for a slash command.
    public static let lineTriggers: Set<Character> = ["/"]

    /// Whether this application has a picker that takes over the suggestion keys.
    static func supportsPickers(in bundleIdentifier: String) -> Bool {
        let identifier = ApplicationKey.of(bundleIdentifier)
        return pickerApplications.contains(where: identifier.hasPrefix)
    }

    /// Whether the word at the end of `typed` is still being picked, so the picker is open over the line.
    public static func isOpen(after typed: String) -> Bool {
        guard let last = typed.last, !last.isWhitespace else { return false }
        let word = typed.split(whereSeparator: \.isWhitespace).last ?? ""
        guard let first = word.first else { return false }
        if first == ":" { return word.dropFirst().allSatisfy(isShortcodeCharacter) }
        if wordTriggers.contains(first) { return true }
        let line = typed.drop(while: \.isWhitespace)
        return line.first.map(lineTriggers.contains) == true && !line.contains(where: \.isWhitespace)
    }

    /// Whether a character can sit in an emoji shortcode, so `:)` or `12:30` is not taken for one.
    private static func isShortcodeCharacter(_ character: Character) -> Bool {
        character.isLetter || character == "_" || character == "+" || character == "-"
    }
}
