import Foundation

/// What the user is looking at when they dictate; every field is optional, macOS grants each conditionally.
public struct AppContext: Sendable, Equatable {
    /// Localised name of the frontmost application, e.g. `"Slack"`.
    public let applicationName: String?
    /// Bundle identifier of the frontmost application, e.g. `"com.tinyspeck.slackmacgap"`.
    public let bundleIdentifier: String?
    /// The running process, which every application has even when it carries no bundle identifier.
    public let processIdentifier: Int32?
    /// Title of the focused window or document, where the app exposes it.
    public let documentName: String?
    /// Host of the focused page's address, lowercased; the path and query are dropped on read and never kept.
    public let pageHost: String?
    /// Text the user had selected, where readable. Never modified by the pipeline.
    public let selectedText: String?
    /// Up to ``InsertionPoint/precedingLimit`` characters before the caret; `nil` when the field will not say.
    public let precedingText: String?
    /// Up to ``InsertionPoint/followingLimit`` characters after the selection; `nil` when the field will not say.
    public let followingText: String?
    /// Whether the focused field hides what is typed, so none of its text is carried and nothing is kept.
    public let isSecure: Bool
    /// The focused field's Accessibility role, when the system reports one.
    public let accessibilityRole: String?
    /// Whether the focused field can hold multiple lines, when reported by Accessibility.
    public let isMultiline: Bool?
    /// What the focused field calls itself, one line without control characters; never read from a secure field nor kept in history.
    public let fieldLabel: String?
    /// The focused field itself, so a write can refuse a field the user moved away from; `nil` when unreadable.
    public let field: FieldIdentity?

    /// A context; anything not supplied is unknown.
    public init(
        applicationName: String? = nil,
        bundleIdentifier: String? = nil,
        processIdentifier: Int32? = nil,
        documentName: String? = nil,
        pageAddress: String? = nil,
        selectedText: String? = nil,
        precedingText: String? = nil,
        followingText: String? = nil,
        isSecure: Bool = false,
        accessibilityRole: String? = nil,
        isMultiline: Bool? = nil,
        fieldLabel: String? = nil,
        field: FieldIdentity? = nil
    ) {
        self.applicationName = applicationName
        self.bundleIdentifier = bundleIdentifier
        self.processIdentifier = processIdentifier
        self.documentName = documentName
        self.pageHost = pageAddress.flatMap(Self.host)
        self.selectedText = selectedText
        self.precedingText = precedingText
        self.followingText = followingText
        self.isSecure = isSecure
        self.accessibilityRole = accessibilityRole
        self.isMultiline = isMultiline
        self.fieldLabel = isSecure ? nil : fieldLabel.flatMap(Self.fieldLabel)
        self.field = field
    }

    /// A web address reduced to its lowercased host, or nil for one without a web host.
    public static func host(_ address: String) -> String? {
        guard let components = URLComponents(string: address.trimmingCharacters(in: .whitespaces)),
            let scheme = components.scheme?.lowercased(), scheme == "https" || scheme == "http",
            let host = components.host?.lowercased(), !host.isEmpty
        else { return nil }
        return host.hasSuffix(".") ? String(host.dropLast()) : host
    }

    /// The most label characters carried; a longer one is a sentence of help text, not a name.
    public static let fieldLabelLimit = 80

    /// A field's name as one line: control characters out, whitespace collapsed, capped; `nil` when blank.
    public static func fieldLabel(_ raw: String) -> String? {
        let words = raw.unicodeScalars
            .map { CharacterSet.controlCharacters.contains($0) ? " " : String($0) }
            .joined()
            .split(whereSeparator: \.isWhitespace)
        guard !words.isEmpty else { return nil }
        return String(words.joined(separator: " ").prefix(fieldLabelLimit))
    }

    /// What the focused field is for, from its role, its line count and its label.
    public var fieldRole: FieldRole {
        FieldRole(accessibilityRole: accessibilityRole, isMultiline: isMultiline, label: fieldLabel)
    }

    /// The context available when macOS tells us nothing.
    public static let unknown = AppContext()

    /// `true` when no field carries information, so a prompt can leave the context section out.
    public var isEmpty: Bool {
        applicationName == nil
            && bundleIdentifier == nil
            && documentName == nil
            && selectedText == nil
            && precedingText == nil
            && followingText == nil
    }
}

extension AppContext: CustomStringConvertible, CustomDebugStringConvertible, CustomReflectable {
    /// The application only, so a log line or interpolation never carries what the field holds.
    public var description: String {
        "AppContext(\(applicationName ?? "unknown app"), \(bundleIdentifier ?? "no bundle"), field text redacted)"
    }

    /// The same redacted line as ``description``.
    public var debugDescription: String { description }

    /// A mirror with the application only, so `dump` and debugger views cannot print field text.
    public var customMirror: Mirror {
        Mirror(self, children: ["identity": identity], displayStyle: .struct)
    }
}
