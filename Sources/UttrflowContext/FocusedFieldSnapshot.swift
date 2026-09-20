public import CoreGraphics
public import UttrflowPredict

public import struct Foundation.NSRange
private import UttrflowPredict

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
    /// The field's own rectangle, in AppKit screen coordinates, which a long ghost must not run past.
    public let field: CGRect?
    /// The field's own type size, so the surface reads as part of the line it sits on.
    public let pointSize: CGFloat?
    /// The field's own font family, so the ghost is set in the face the line is.
    public let fontFamily: String?
    /// The field's own text colour, so the ghost reads against the field and not against Uttrflow's appearance.
    public let textColor: TextColor?
    /// Whether the field hides what is typed into it.
    public let isSecure: Bool
    /// Whether an input method is mid-composition, which owns both the screen and the Tab key.
    public let isComposing: Bool
    /// What the field itself says about an input method's marked text, before any guess from the input source.
    public let markedText: MarkedText
    /// How long the whole reading took, in microseconds.
    public let readMicroseconds: Int
    /// The title of the window holding the field, which names the conversation, the note or the thread the field belongs to.
    public let windowTitle: String?
    /// The line the caret is on, up to the caret, less the shell prompt a terminal reports in front of it; read once, when the snapshot is taken.
    public let currentLine: String
    /// Whether the caret's line ran past `lineReadLimit`, so `currentLine` is only its last stretch and too long to complete.
    public let isLineCut: Bool
    /// Whether the value holds more than one line.
    public let holdsNewline: Bool

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
        field: CGRect? = nil,
        pointSize: CGFloat? = nil,
        fontFamily: String? = nil,
        textColor: TextColor? = nil,
        isSecure: Bool = false,
        isComposing: Bool = false,
        markedText: MarkedText = .unanswered,
        readMicroseconds: Int = 0,
        windowTitle: String? = nil
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
        self.field = field
        self.pointSize = pointSize
        self.fontFamily = fontFamily
        self.textColor = textColor
        self.isSecure = isSecure
        self.isComposing = isComposing
        self.markedText = markedText
        self.readMicroseconds = readMicroseconds
        self.windowTitle = windowTitle
        let line = Self.caretLine(of: value, at: selection, in: bundleIdentifier)
        self.currentLine = line.text
        self.isLineCut = line.isCut
        self.holdsNewline = value.map(Self.holdsNewline) ?? false
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

    /// The line capture may learn, which is nothing when the line was too long to read whole.
    public var learnableLine: String { isLineCut ? "" : currentLine }

    /// How many characters back from the caret its line is read; a prompt and a line to complete both fit well inside it.
    public static let lineReadLimit = ShellPrompt.searchLimit + SuggestionSession.maximumTypedLength + 1

    /// Counts the characters the line reading visits while bound, so a test can bound the work without a clock.
    @TaskLocal package static var tally: CharacterTally?

    /// The caret's line as `currentLine` holds it, and whether the read limit cut it.
    private static func caretLine(
        of value: String?, at selection: NSRange?, in bundleIdentifier: String
    ) -> (text: String, isCut: Bool) {
        guard let value else { return ("", false) }
        let caret = index(in: value, atUTF16Offset: selection?.location ?? value.utf16.count)
        let start = lineStart(in: value, before: caret)
        let line = String(value[start.index..<caret])
        // A cut line is kept whole, so its length alone refuses it.
        guard !start.isCut else { return (line, true) }
        let input = TerminalApplications.contains(bundleIdentifier) ? ShellPrompt.input(in: line) : line
        // Leading indentation is dropped so an indented line matches what capture stored, which is trimmed.
        return (droppingLeadingWhitespace(input), false)
    }

    /// Where the line holding the caret begins, read back no further than `lineReadLimit`, and whether the limit stopped it first.
    static func lineStart(in value: String, before caret: String.Index) -> (index: String.Index, isCut: Bool)
    {
        var index = caret
        var read = 0
        defer { tally?.record(read) }
        while index > value.startIndex {
            guard read < lineReadLimit else { return (index, true) }
            let before = value.index(before: index)
            read += 1
            if value[before].isNewline { return (index, false) }
            index = before
        }
        return (index, false)
    }

    /// Every scalar `Character.isNewline` accepts, each of which is one UTF-16 unit.
    private static let newlineUnits: Set<UInt16> = [0x0A, 0x0B, 0x0C, 0x0D, 0x85, 0x2028, 0x2029]

    /// Whether a value holds a newline, asked of its UTF-16 units so no character is ever assembled.
    private static func holdsNewline(_ value: String) -> Bool {
        value.utf16.contains(where: newlineUnits.contains)
    }

    /// The text before the caret's line, at most this long, which is what the line is a continuation of; nothing when the line is too long to read whole.
    public func preceding(maxLength: Int) -> String? {
        guard let value else { return nil }
        let caret = Self.index(in: value, atUTF16Offset: selection?.location ?? value.utf16.count)
        let start = Self.lineStart(in: value, before: caret)
        guard !start.isCut, start.index > value.startIndex else { return nil }
        var earlier = value[..<value.index(before: start.index)].suffix(maxLength)
        while let last = earlier.last, last.isWhitespace { earlier.removeLast() }
        while let first = earlier.first, first.isWhitespace { earlier.removeFirst() }
        return earlier.isEmpty ? nil : String(earlier)
    }

    /// The text with leading spaces and tabs removed, which is what makes the query match a trimmed entry.
    private static func droppingLeadingWhitespace(_ text: String) -> String {
        String(text.drop { $0 == " " || $0 == "\t" })
    }

    /// Whether the caret sits at the end of the line it is on, which completing presumes.
    public var caretAtLineEnd: Bool {
        guard
            let selection, let value,
            let end = AccessibilityRange.end(location: selection.location, length: selection.length)
        else { return false }
        var index = Self.index(in: value, atUTF16Offset: end)
        // Only whitespace ahead still counts as the line's end, since a terminal pads the line with spaces.
        while index < value.endIndex {
            if value[index].isNewline { return true }
            guard value[index] == " " || value[index] == "\t" else { return false }
            index = value.index(after: index)
        }
        return true
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
    private static let caretFieldWidth: CGFloat = 3

    /// The heights a text caret can have, so a hidden one-pixel field is told from a collapsed or a page-tall one.
    private static let caretHeights: ClosedRange<CGFloat> = 8...80

    /// Whether a field's frame is the shape of a caret rather than of a field, which is how an editor that renders its own text places its input field.
    public static func isCaretShaped(_ frame: CGRect) -> Bool {
        frame.width <= caretFieldWidth && caretHeights.contains(frame.height)
    }

    /// The roles a person types into, which is what a focused element must be before it is taken for the field.
    private static let textEntryRoles: Set<String> = [
        "AXTextArea", "AXTextField", "AXComboBox", "AXSearchField", "AXWebArea",
    ]

    /// Whether a role is one text is entered into; a static text, a group or a cell under the caret is not the field.
    public static func isTextEntry(_ role: String?) -> Bool {
        role.map(textEntryRoles.contains) ?? false
    }
}
