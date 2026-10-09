public import CoreGraphics
public import UttrflowCore

public import struct Foundation.NSRange

public enum WritingDirection: Sendable, Equatable {
    case leftToRight
    case rightToLeft
    case unknown
}

/// The focused Accessibility element and its selected text range, without reading its contents.
public struct FocusedFieldSelection: Sendable, Equatable {
    /// The process that owns the focused element.
    public let processIdentifier: Int32
    /// The focused element's Accessibility identity within its process.
    public let elementHash: UInt
    /// The selection in UTF-16 units.
    public let range: NSRange

    /// The Accessibility element that owns this range.
    public var identity: FocusedFieldIdentity {
        FocusedFieldIdentity(processIdentifier: processIdentifier, elementHash: elementHash)
    }

    public init(processIdentifier: Int32, elementHash: UInt, range: NSRange) {
        self.processIdentifier = processIdentifier
        self.elementHash = elementHash
        self.range = range
    }
}

/// The Accessibility element that owns a focused field reading.
public struct FocusedFieldIdentity: Sendable, Equatable {
    /// The process that owns the focused element.
    public let processIdentifier: Int32
    /// The focused element's Accessibility identity within its process.
    public let elementHash: UInt

    public init(processIdentifier: Int32, elementHash: UInt) {
        self.processIdentifier = processIdentifier
        self.elementHash = elementHash
    }
}

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
    /// The field's visible title, preferred as its short label when available.
    package let title: String?
    /// The document the field sits in: a page address in a browser, a directory in a terminal.
    public let document: String?
    /// Everything the field holds, or nothing when it will not say.
    public let value: String?
    /// Where the caret sits and how much is selected, in UTF-16 units.
    public let selection: NSRange?
    /// The Accessibility element that owned the focused field when this snapshot was read.
    public let focusedFieldIdentity: FocusedFieldIdentity?
    /// The caret's rectangle, in AppKit screen coordinates, or nothing when it cannot be read.
    public let caret: CGRect?
    /// The direction at the caret, or nothing when the Accessibility bounds cannot establish one.
    public let writingDirection: WritingDirection
    /// The window's rectangle, in AppKit screen coordinates, which the strip stands on.
    public let window: CGRect?
    /// The field's own rectangle, in AppKit screen coordinates, which a long ghost must not run past.
    public let field: CGRect?
    /// The field's own type size, so the surface reads as part of the line it sits on.
    public let pointSize: CGFloat?
    /// The field's own font family, so the ghost is set in the face the line is.
    public let fontFamily: String?
    /// Whether the field's face is bold, so the ghost keeps the run's weight.
    public let isBold: Bool
    /// Whether the field's face is italic, so the ghost keeps the run's slant.
    public let isItalic: Bool
    /// The field's own text colour, so the ghost reads against the field and not against Uttrflow's appearance.
    public let textColor: TextColor?
    /// Whether the field hides what is typed into it.
    public let isSecure: Bool
    /// Whether the field reports that it accepts input, or nothing when Accessibility does not answer.
    public let isEnabled: Bool?
    /// Whether the field reports that its text is editable, or nothing when Accessibility does not answer.
    public let isEditable: Bool?
    /// Whether an input method is mid-composition, which owns both the screen and the Tab key.
    public let isComposing: Bool
    /// What the field itself says about an input method's marked text, before any guess from the input source.
    public let markedText: MarkedText
    /// Whether the field says its own list of choices is open, as an expanded combobox does, whose keys belong to that list.
    public let showsOwnList: Bool
    /// How long the whole reading took, in microseconds.
    public let readMicroseconds: Int
    /// The title of the window holding the field, which names the conversation, the note or the thread the field belongs to.
    public let windowTitle: String?
    /// The window number holding the field, when Accessibility publishes one.
    public let windowNumber: UInt32?
    /// The line the caret is on up to the caret, from a sentence start in prose too long to complete whole, less a terminal's shell prompt.
    public let currentLine: String
    /// Whether the caret's line ran past `lineReadLimit`, so `currentLine` is only its last stretch and too long to complete.
    public let isLineCut: Bool

    public init(
        bundleIdentifier: String,
        applicationName: String,
        role: String,
        subrole: String? = nil,
        identifier: String? = nil,
        placeholder: String? = nil,
        accessibilityDescription: String? = nil,
        title: String? = nil,
        document: String? = nil,
        value: String? = nil,
        selection: NSRange? = nil,
        focusedFieldIdentity: FocusedFieldIdentity? = nil,
        caret: CGRect? = nil,
        writingDirection: WritingDirection = .unknown,
        window: CGRect? = nil,
        field: CGRect? = nil,
        pointSize: CGFloat? = nil,
        fontFamily: String? = nil,
        isBold: Bool = false,
        isItalic: Bool = false,
        textColor: TextColor? = nil,
        isSecure: Bool = false,
        isEnabled: Bool? = nil,
        isEditable: Bool? = nil,
        isComposing: Bool = false,
        markedText: MarkedText = .unanswered,
        showsOwnList: Bool = false,
        readMicroseconds: Int = 0,
        windowTitle: String? = nil,
        windowNumber: UInt32? = nil
    ) {
        let prose = role == Self.proseRole && Self.isProseApplication(bundleIdentifier)
        let line = Self.caretLine(
            of: value, at: selection, in: bundleIdentifier, prose: prose, windowTitle: windowTitle)
        let isSecure =
            isSecure
            || SecureField.isDeclaredSecure(
                role: role, subrole: subrole, identifier: identifier, placeholder: placeholder,
                description: accessibilityDescription, title: title)
            || (TerminalApplications.contains(bundleIdentifier)
                && ShellPrompt.isCredentialPrompt(in: line.text))

        self.bundleIdentifier = bundleIdentifier
        self.applicationName = applicationName
        self.role = role
        self.subrole = subrole
        self.identifier = identifier
        self.placeholder = placeholder
        self.accessibilityDescription = accessibilityDescription
        self.title = title
        self.document = document
        self.value = isSecure ? nil : value
        self.selection = selection
        self.focusedFieldIdentity = focusedFieldIdentity
        self.caret = caret
        self.writingDirection = writingDirection
        self.window = window
        self.field = field
        self.pointSize = pointSize
        self.fontFamily = fontFamily
        self.isBold = isBold
        self.isItalic = isItalic
        self.textColor = textColor
        self.isSecure = isSecure
        self.isEnabled = isEnabled
        self.isEditable = isEditable
        self.isComposing = isComposing
        self.markedText = markedText
        self.showsOwnList = showsOwnList
        self.readMicroseconds = readMicroseconds
        self.windowTitle = windowTitle
        self.windowNumber = windowNumber
        self.currentLine = isSecure ? "" : line.text
        self.isLineCut = line.isCut
    }
}

extension FocusedFieldSnapshot {
    /// What tells this field from another of the same role, taking the first name it publishes.
    public var locator: String? {
        identifier ?? placeholder ?? accessibilityDescription
    }

    /// The field name for a prompt, selected in the same order as dictation context labels.
    package var fieldLabel: String? {
        guard !isSecure else { return nil }
        return [title, placeholder, accessibilityDescription]
            .lazy.compactMap { $0.flatMap(AppContext.fieldLabel) }.first
    }

    /// What was read, in the shape the placement ladder is decided from.
    public var capability: SurfaceCapability {
        SurfaceCapability(
            application: applicationName, role: role, locator: locator, reportsValue: value != nil,
            reportsCaretRect: caret != nil, reportsTextStyle: hasTypeStyle, isSecure: isSecure,
            readMicroseconds: readMicroseconds)
    }

    /// Whether any of the field's type can be matched, since the ghost defaults the rest.
    var hasTypeStyle: Bool { pointSize != nil || fontFamily != nil || isBold || isItalic || textColor != nil }

    /// Where a suggestion may be drawn for this field, or nothing where none may be.
    public var placement: SuggestionPlacement? {
        isEnabled == false || isEditable == false || isHeldByFullScreenProgram
            ? nil : capability.placement
    }

    /// Whether a terminal's screen belongs to a full-screen program, whose lines are a buffer or a query and not a command.
    public var isHeldByFullScreenProgram: Bool {
        TerminalApplications.contains(bundleIdentifier)
            && FullScreenProgram.isNamed(inWindowTitle: windowTitle)
    }

    /// The line capture may learn, which is nothing when the line was too long to read whole or text follows the caret on it.
    public var learnableLine: String { isLineCut || hasTextAfterCaret ? "" : currentLine }

    /// Whether non-padding text follows the caret on its line, so capture does not learn a cut value.
    public var hasTextAfterCaret: Bool {
        rowAhead?.contains(where: { $0 != " " && $0 != "\t" }) ?? false
    }

    /// How many characters back from the caret its line is read; a prompt and a line to complete both fit well inside it.
    public static let lineReadLimit = ShellPrompt.searchLimit + TypedLine.maximumLength + 1

    /// Counts the characters the line reading visits while bound, so a test can bound the work without a clock.
    @TaskLocal package static var tally: CharacterTally?

    /// The caret's line as `currentLine` holds it, and whether the read limit cut it.
    private static func caretLine(
        of value: String?, at selection: NSRange?, in bundleIdentifier: String, prose: Bool,
        windowTitle: String?
    ) -> (text: String, isCut: Bool) {
        guard let value else { return ("", false) }
        let caret = index(in: value, atUTF16Offset: selection?.location ?? value.utf16.count)
        let read: (text: String, isCut: Bool)
        if TerminalApplications.contains(bundleIdentifier) {
            guard let typed = shellInput(in: value, before: caret, windowTitle: windowTitle) else {
                return ("", false)
            }
            read = typed
        } else {
            let start = lineStart(in: value, before: caret, prose: prose)
            read = (String(value[start.index..<caret]), start.isCut)
        }
        // A cut line is kept whole, so its length alone refuses it.
        guard !read.isCut else { return read }
        // Leading indentation is dropped so an indented line matches what capture stored, which is trimmed.
        return (droppingLeadingWhitespace(read.text), false)
    }

    /// What is typed at a terminal's shell before the caret, prompt removed; nothing in a heredoc body or a full-screen program.
    static func shellInput(
        in screen: String, before caret: String.Index, windowTitle: String?
    ) -> (text: String, isCut: Bool)? {
        if FullScreenProgram.isNamed(inWindowTitle: windowTitle) { return nil }
        if ShellPrompt.isHereDocumentBody(in: screen, before: caret) { return nil }
        let start = lineStart(in: screen, before: caret)
        let line = String(screen[start.index..<caret])
        return start.isCut ? (line, true) : (ShellPrompt.input(in: line), false)
    }

    /// Where the line holding the caret begins, read back no further than `lineReadLimit`, and whether the limit stopped it first.
    static func lineStart(in value: String, before caret: String.Index) -> (index: String.Index, isCut: Bool)
    {
        let start = CaretStructure.lineStart(in: value, before: caret, limit: lineReadLimit)
        // The search visits the line and the break before it, or exactly the limit when it is cut.
        let atBreak = !start.isCut && start.index > value.startIndex
        let read = start.isCut ? lineReadLimit : value.distance(from: start.index, to: caret) + (atBreak ? 1 : 0)
        tally?.record(read)
        return start
    }

    /// Where the line a suggestion continues begins: in prose too long to complete whole, the earliest sentence within reach of the caret.
    static func lineStart(
        in value: String, before caret: String.Index, prose: Bool
    ) -> (index: String.Index, isCut: Bool) {
        let start = lineStart(in: value, before: caret)
        guard prose,
            start.isCut || value.distance(from: start.index, to: caret) > TypedLine.maximumLength
        else { return start }
        return sentenceStart(in: value, after: start.index, before: caret).map { ($0, false) } ?? start
    }

    /// The earliest sentence start no more than `TypedLine.maximumLength` characters before the caret, with something typed after it.
    static func sentenceStart(
        in value: String, after lineStart: String.Index, before caret: String.Index
    ) -> String.Index? {
        var index = caret
        var read = 0
        var found: String.Index?
        defer { tally?.record(read) }
        while index > lineStart, read < TypedLine.maximumLength {
            let before = value.index(before: index)
            read += 1
            if index < caret, value[before].isWhitespace, !value[index].isWhitespace,
                endsASentence(value, at: before, after: lineStart)
            {
                found = index
            }
            index = before
        }
        return found
    }

    /// The quotes and brackets that may close a sentence after its end mark.
    private static let sentenceClosers: Set<Character> = ["\"", "'", ")", "”", "’", "]"]

    /// Whether the whitespace at `space` follows a sentence's end mark, spaces, closing quotes and brackets stepped over.
    private static func endsASentence(
        _ value: String, at space: String.Index, after lineStart: String.Index
    ) -> Bool {
        var index = space
        while index > lineStart {
            index = value.index(before: index)
            let character = value[index]
            if sentenceClosers.contains(character) || character.isWhitespace { continue }
            // An ellipsis trails off inside a sentence rather than ending it.
            guard SentenceMarks.ends.contains(character) else { return false }
            return !(character == "." && index > lineStart && value[value.index(before: index)] == ".")
        }
        return false
    }

    /// The text before the caret's line, at most this long, which is what the line is a continuation of; nothing when the line is too long to read whole.
    public func preceding(maxLength: Int) -> String? {
        guard let value else { return nil }
        let caret = Self.index(in: value, atUTF16Offset: selection?.location ?? value.utf16.count)
        let start = Self.lineStart(in: value, before: caret, prose: isProse)
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

    /// Whether only padding and closing punctuation follow the caret, which completing presumes.
    public var caretAtLineEnd: Bool {
        guard let ahead = rowAhead else { return false }
        return ahead.allSatisfy { $0 == " " || $0 == "\t" || Self.closingPunctuation.contains($0) }
    }

    /// Closing punctuation immediately after the caret, with editor padding removed.
    public var closingPunctuationAfterCaret: String {
        guard let ahead = rowAhead else { return "" }
        return String(ahead.drop { $0 == " " || $0 == "\t" }.prefix { Self.closingPunctuation.contains($0) })
    }

    /// Characters an editor may keep after the caret while it completes inside a pair.
    private static let closingPunctuation: Set<Character> = [")", "]", "}", "'", "\"", "`"]

    /// The fewest padding spaces that separate the caret from a terminal's right-side display text.
    static let rightPromptPadding = 4

    /// How many padding spaces separate the caret from a terminal's right-side display text, or nothing when the row has none.
    public var rightPromptGap: Int? {
        guard TerminalApplications.contains(bundleIdentifier), let ahead = rowAhead else { return nil }
        let gap = ahead.prefix { $0 == " " }.count
        let prompt = ahead.dropFirst(gap)
        guard gap >= Self.rightPromptPadding, prompt.contains(where: { !$0.isWhitespace }) else { return nil }
        return gap
    }

    /// The field's rectangle, ended before a padded terminal tail so the ghost does not draw over it.
    public var ghostField: CGRect? {
        guard let gap = rightPromptGap, let caret, let pointSize, let field else { return field }
        let edge = caret.maxX + CGFloat(gap - 1) * pointSize * Self.monospacedAdvance
        guard edge > field.minX, edge < field.maxX else { return field }
        return CGRect(x: field.minX, y: field.minY, width: edge - field.minX, height: field.height)
    }

    /// A monospaced face's advance as a share of its point size, which is how wide a terminal cell is taken to be.
    static let monospacedAdvance: CGFloat = 0.6

    /// What follows the caret up to the end of its row, or nothing when the caret cannot be read.
    private var rowAhead: Substring? {
        guard
            let selection, let value,
            let end = AccessibilityRange.end(location: selection.location, length: selection.length)
        else { return nil }
        let start = Self.index(in: value, atUTF16Offset: end)
        let stop = value[start...].firstIndex(where: \.isNewline) ?? value.endIndex
        return value[start..<stop]
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

    private static func isProseApplication(_ bundleIdentifier: String) -> Bool {
        guard !TerminalApplications.contains(bundleIdentifier) else { return false }
        guard let kind = AppKind(bundleIdentifier: bundleIdentifier) else { return true }
        return kind != .sqlEditor && kind != .codeEditor
    }

    /// Whether the field holds prose rather than a command or an address.
    public var isProse: Bool {
        role == Self.proseRole && Self.isProseApplication(bundleIdentifier)
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

    /// Whether a role is one text is entered into; a static text, a group or a cell under the caret is not the field.
    public static func isTextEntry(_ role: String?) -> Bool {
        FocusedElementPreference.isTextEntry(role)
    }
}
