public import CoreGraphics

public import struct Foundation.NSRange

/// One reading of the focused field: what identifies it, what it holds, and where its caret is.
public struct FocusedFieldSnapshot: Sendable, Equatable {
    /// The application the field belongs to.
    public let bundleIdentifier: String
    /// The application as the user knows it, which is what a capability table is read by.
    public let applicationName: String
    /// The field's Accessibility role, which separates a search box from a document.
    public let role: String
    /// The role's refinement, which is where AppKit says a field is a password field.
    public let subrole: String?
    /// The name the field publishes for itself, which is the strongest locator there is.
    public let identifier: String?
    /// The grey text in an empty field, which names it when it publishes no identifier.
    public let placeholder: String?
    /// What a screen reader would call the field, which is the last resort for a name.
    public let accessibilityDescription: String?
    /// The document the field sits in: a page address in a browser, a directory in a terminal.
    public let document: String?
    /// Everything the field holds, or nothing when it will not say.
    public let value: String?
    /// Where the caret sits and how much is selected, in UTF-16 units.
    public let selection: NSRange?
    /// The caret's rectangle, in AppKit screen coordinates, or nothing when it cannot be read.
    public let caret: CGRect?
    /// The window's rectangle, in AppKit screen coordinates, which the strip stands on.
    public let window: CGRect?
    /// The field's own type size, so the surface reads as part of the line it sits on.
    public let pointSize: CGFloat?
    /// The field's own font family, so the ghost is set in the face the line is.
    public let fontFamily: String?
    /// Whether the field hides what is typed into it.
    public let isSecure: Bool
    /// Whether an input method is mid-composition, which owns both the screen and the Tab key.
    public let isComposing: Bool
    /// How long the whole reading took, in microseconds.
    public let readMicroseconds: Int

    public init(
        bundleIdentifier: String,
        applicationName: String,
        role: String,
        subrole: String? = nil,
        identifier: String? = nil,
        placeholder: String? = nil,
        accessibilityDescription: String? = nil,
        document: String? = nil,
        value: String? = nil,
        selection: NSRange? = nil,
        caret: CGRect? = nil,
        window: CGRect? = nil,
        pointSize: CGFloat? = nil,
        fontFamily: String? = nil,
        isSecure: Bool = false,
        isComposing: Bool = false,
        readMicroseconds: Int = 0
    ) {
        self.bundleIdentifier = bundleIdentifier
        self.applicationName = applicationName
        self.role = role
        self.subrole = subrole
        self.identifier = identifier
        self.placeholder = placeholder
        self.accessibilityDescription = accessibilityDescription
        self.document = document
        self.value = value
        self.selection = selection
        self.caret = caret
        self.window = window
        self.pointSize = pointSize
        self.fontFamily = fontFamily
        self.isSecure = isSecure
        self.isComposing = isComposing
        self.readMicroseconds = readMicroseconds
    }
}

extension FocusedFieldSnapshot {
    /// What tells this field from another of the same role, taking the first name it publishes.
    public var locator: String? {
        identifier ?? placeholder ?? accessibilityDescription
    }

    /// What was read, in the shape the placement ladder is decided from.
    public var capability: SurfaceCapability {
        SurfaceCapability(
            application: applicationName, role: role, locator: locator, reportsValue: value != nil,
            reportsCaretRect: caret != nil, reportsTextStyle: pointSize != nil, isSecure: isSecure,
            readMicroseconds: readMicroseconds)
    }

    /// Where a suggestion may be drawn for this field, or nothing where none may be.
    public var placement: SuggestionPlacement? { capability.placement }

    /// The line the caret is on, up to the caret, less the shell prompt a terminal reports in front of it.
    public var currentLine: String {
        guard let value else { return "" }
        let line = Self.line(of: value, endingAt: selection?.location ?? value.utf16.count)
        let input = TerminalApplications.contains(bundleIdentifier) ? ShellPrompt.input(in: line) : line
        // Leading indentation is dropped so an indented line matches what capture stored, which is trimmed.
        return Self.droppingLeadingWhitespace(input)
    }

    /// The text before the caret's line, at most this long, which is what the line is a continuation of.
    public func preceding(maxLength: Int) -> String? {
        guard let value else { return nil }
        let caret = Self.index(in: value, atUTF16Offset: selection?.location ?? value.utf16.count)
        let head = value[..<caret]
        guard let newline = head.lastIndex(where: \.isNewline) else { return nil }
        var earlier = head[..<newline].suffix(maxLength)
        while let last = earlier.last, last.isWhitespace { earlier.removeLast() }
        while let first = earlier.first, first.isWhitespace { earlier.removeFirst() }
        return earlier.isEmpty ? nil : String(earlier)
    }

    /// The text with leading spaces and tabs removed, which is what makes the query match a trimmed entry.
    static func droppingLeadingWhitespace(_ text: String) -> String {
        String(text.drop { $0 == " " || $0 == "\t" })
    }

    /// Whether the caret sits at the end of the line it is on, which completing presumes.
    public var caretAtLineEnd: Bool {
        guard let selection, let value else { return false }
        var index = Self.index(in: value, atUTF16Offset: selection.location + selection.length)
        // Only whitespace ahead still counts as the line's end, since a terminal pads the line with spaces.
        while index < value.endIndex {
            if value[index].isNewline { return true }
            guard value[index] == " " || value[index] == "\t" else { return false }
            index = value.index(after: index)
        }
        return true
    }

    /// The text between the newline before the given caret and the caret itself.
    static func line(of value: String, endingAt utf16Offset: Int) -> String {
        let head = value[..<index(in: value, atUTF16Offset: utf16Offset)]
        guard let newline = head.lastIndex(where: \.isNewline) else { return String(head) }
        return String(head[head.index(after: newline)...])
    }

    /// The offset as a character index, clamped into the string and moved back off any split character.
    static func index(in value: String, atUTF16Offset utf16Offset: Int) -> String.Index {
        let units = value.utf16
        let clamped = min(max(utf16Offset, 0), units.count)
        var index = units.index(units.startIndex, offsetBy: clamped)
        while index > value.startIndex, String.Index(index, within: value) == nil {
            index = units.index(before: index)
        }
        return index
    }

    /// Whether any text is selected, which the next keystroke would replace.
    public var hasSelection: Bool { (selection?.length ?? 0) > 0 }

    /// The role a multi-line field publishes, which a document and a shell both use.
    public static let proseRole = "AXTextArea"

    /// Whether the field holds prose rather than a command or an address.
    public var isProse: Bool {
        role == Self.proseRole && !TerminalApplications.contains(bundleIdentifier)
    }
}

extension FocusedFieldSnapshot {
    /// The widest a field may be and still be the caret itself: editors that draw their own text park a one-pixel input field there.
    public static let caretFieldWidth: CGFloat = 3

    /// The heights a text caret can have, so a hidden one-pixel field is told from a collapsed or a page-tall one.
    public static let caretHeights: ClosedRange<CGFloat> = 8...80

    /// Whether a field's frame is the shape of a caret rather than of a field, which is how an editor that renders its own text places its input field.
    public static func isCaretShaped(_ frame: CGRect) -> Bool {
        frame.width <= caretFieldWidth && caretHeights.contains(frame.height)
    }

    /// The roles a person types into, which is what a focused element must be before it is taken for the field.
    public static let textEntryRoles: Set<String> = [
        "AXTextArea", "AXTextField", "AXComboBox", "AXSearchField", "AXWebArea",
    ]

    /// Whether a role is one text is entered into; a static text, a group or a cell under the caret is not the field.
    public static func isTextEntry(_ role: String?) -> Bool {
        role.map(textEntryRoles.contains) ?? false
    }
}
