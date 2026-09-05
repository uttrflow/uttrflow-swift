// The formatter protocol and the allowlist of formatters that may be run.

public import struct Foundation.TimeInterval

/// A formatter for one language; a protocol, because the real one runs another program.
public protocol CodeFormatting: Sendable {
    /// Whether a formatter for this language can be found on this machine; the action is offered only then.
    func isAvailable(for language: CodeLanguage) async -> Bool

    /// The formatted code, or `nil` for a fragment that is invalid on its own, which is the common case.
    func format(_ text: String, as language: CodeLanguage) async -> String?
}

/// What may be run, and nothing else; an allowlist, because a poisoned `prettier` would see every clip.
public enum KnownFormatter: String, Sendable, CaseIterable {
    case swiftFormat = "swift-format"
    case prettier
    case black
    case rustfmt
    case gofmt

    /// The languages this formatter is trusted with.
    public var languages: [CodeLanguage] {
        switch self {
        case .swiftFormat: [.swift]
        case .prettier: [.javascript, .typescript, .json, .css, .html]
        case .black: [.python]
        case .rustfmt: [.rust]
        case .gofmt: [.go]
        }
    }

    /// The arguments that read standard input and write standard output; the clip is never an argument.
    public var arguments: [String] {
        switch self {
        case .swiftFormat: ["format"]
        case .prettier: ["--stdin-filepath", "clip.ts"]
        case .black: ["-q", "-"]
        case .rustfmt: ["--emit", "stdout"]
        case .gofmt: []
        }
    }

    /// The first formatter trusted with this language.
    public init?(for language: CodeLanguage) {
        guard let trusted = Self.allCases.first(where: { $0.languages.contains(language) }) else {
            return nil
        }
        self = trusted
    }

    /// How long a formatter may take before it is given up on; a hung program must not take the panel.
    public static let timeout: TimeInterval = 3
}
