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

    /// Whether the caret sits at the end of what the field holds, which completing presumes.
    public var caretAtEnd: Bool {
        guard let selection, let value else { return false }
        return selection.location + selection.length == value.utf16.count
    }

    /// Whether any text is selected, which the next keystroke would replace.
    public var hasSelection: Bool { (selection?.length ?? 0) > 0 }

    /// The role a multi-line field publishes, which is the only signal that it holds prose.
    public static let proseRole = "AXTextArea"

    /// Whether the field holds prose rather than a command or an address.
    public var isProse: Bool { role == Self.proseRole }
}
