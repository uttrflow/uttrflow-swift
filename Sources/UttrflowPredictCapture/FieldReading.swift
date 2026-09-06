public import UttrflowPredict

import Foundation

/// What a focused text field says about itself, before any of it is believed.
public struct FieldReading: Sendable, Equatable {
    /// The application the field belongs to.
    public let bundleIdentifier: String
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
    /// The title of the window holding the field, which names the conversation or note a composer belongs to.
    public let windowTitle: String?
    /// The application as the user knows it, which is how a window naming only the application is told from one naming a thread.
    public let applicationName: String?

    public init(
        bundleIdentifier: String, role: String, subrole: String? = nil, identifier: String? = nil,
        placeholder: String? = nil, accessibilityDescription: String? = nil, document: String? = nil,
        windowTitle: String? = nil, applicationName: String? = nil
    ) {
        self.bundleIdentifier = bundleIdentifier
        self.role = role
        self.subrole = subrole
        self.identifier = identifier
        self.placeholder = placeholder
        self.accessibilityDescription = accessibilityDescription
        self.document = document
        self.windowTitle = windowTitle
        self.applicationName = applicationName
    }
}

extension FieldReading {
    /// The role and subrole a password field is published under, by the two conventions in use.
    public static let secureRole = SecureField.secureRole

    /// Whether the field hides what is typed, from its role, its subrole, or a name that betrays a password.
    public var isSecure: Bool {
        SecureField.isDeclaredSecure(
            role: role, subrole: subrole, identifier: identifier, placeholder: placeholder,
            description: accessibilityDescription)
    }

    /// The field as the corpus knows it, or nothing when it does not say enough to be told apart.
    public var surface: Surface? {
        guard let bundleIdentifier = Self.named(bundleIdentifier), let role = Self.named(role) else {
            return nil
        }
        return Surface(bundleIdentifier: bundleIdentifier, role: role, locator: locator, scope: scope)
    }

    /// What tells this field from another of the same role, taking the first name it publishes.
    public var locator: String? {
        Self.named(identifier) ?? Self.named(placeholder) ?? Self.named(accessibilityDescription)
    }

    /// What the field belongs to: the page host for a web field, the directory for a file, and for a field that owns no document the window that holds it, since that is what tells one conversation or note from another. See `Docs/predict-precision.md`.
    public var scope: String? {
        guard let document = Self.named(document) else {
            return Self.conversation(windowTitle, of: applicationName)
        }
        if let host = Self.host(of: document) { return host }
        return Self.directory(of: document) ?? Self.conversation(windowTitle, of: applicationName)
    }

    /// How many characters of a window title name the thread; past this it is a document's first line rather than a name.
    static let conversationCap = 120

    /// The window's title as a name for what is being written to, with the counts and marks a window adds to it removed, or nothing when it names only the application.
    static func conversation(_ title: String?, of application: String? = nil) -> String? {
        guard var name = Self.named(title) else { return nil }
        // An edited window marks itself, an unread window counts itself, and neither is part of what the window names.
        while let last = name.last, last == "•" || last == "*" { name = String(name.dropLast()) }
        name = Self.withoutTrailingCount(name)
        while let first = name.first, first == "•" || first == "*" { name = String(name.dropFirst()) }
        guard let trimmed = Self.named(name), trimmed.count <= conversationCap else { return nil }
        // A window called after its own application names no thread inside it, so it is no identity at all.
        guard trimmed.caseInsensitiveCompare(application ?? "") != .orderedSame else { return nil }
        return trimmed
    }

    /// The name without a bracketed count at either end, as an unread conversation and a numbered draft carry.
    private static func withoutTrailingCount(_ name: String) -> String {
        let trimmed = name.trimmingCharacters(in: .whitespaces)
        for (open, close) in [("(", ")"), ("[", "]")] {
            guard trimmed.hasSuffix(close), let start = trimmed.lastIndex(of: Character(open)) else {
                continue
            }
            let inside = trimmed[trimmed.index(after: start)..<trimmed.index(before: trimmed.endIndex)]
            guard !inside.isEmpty, inside.allSatisfy({ $0.isNumber || $0.isWhitespace }) else { continue }
            return String(trimmed[..<start]).trimmingCharacters(in: .whitespaces)
        }
        return trimmed
    }

    /// The host, lowercased and without the subdomain every site answers on, for a web address.
    private static func host(of document: String) -> String? {
        guard let url = URL(string: document), let scheme = url.scheme?.lowercased(),
            scheme == "http" || scheme == "https", let host = url.host()?.lowercased(), !host.isEmpty
        else { return nil }
        return host.hasPrefix("www.") ? String(host.dropFirst(4)) : host
    }

    /// The directory a path names, so every document of one project shares one corpus.
    private static func directory(of document: String) -> String? {
        let path = document.hasPrefix("file://") ? URL(string: document)?.path() ?? "" : document
        let decoded = path.removingPercentEncoding ?? path
        guard decoded.hasPrefix("/") || decoded.hasPrefix("~") else { return nil }
        guard decoded.count > 1 else { return named(decoded) }
        guard !decoded.hasSuffix("/") else { return named(String(decoded.dropLast())) }
        guard !(decoded as NSString).pathExtension.isEmpty else { return named(decoded) }
        return named((decoded as NSString).deletingLastPathComponent)
    }

    /// The value with its surrounding space removed, or nothing when that leaves nothing.
    private static func named(_ value: String?) -> String? {
        guard let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines), !trimmed.isEmpty
        else { return nil }
        return trimmed
    }
}
