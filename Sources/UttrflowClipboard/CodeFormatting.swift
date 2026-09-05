public import struct Foundation.TimeInterval

/// A formatter for one language, wherever it comes from.
///
/// A protocol rather than a concrete type because the real one runs another program, which
/// nothing above it should have to know or be able to do in a test.
public protocol CodeFormatting: Sendable {
    /// Whether a formatter for this language can be found on this machine.
    ///
    /// D5 — the action is offered only where the answer is yes. An offer that fails when
    /// pressed is worse than no offer.
    func isAvailable(for language: CodeLanguage) async -> Bool

    /// The formatted code, or `nil` when it could not be produced.
    ///
    /// D7 — a fragment copied from the middle of a file is invalid on its own, which is
    /// the *common* case for a clipboard rather than an edge one. `nil` for that, and the
    /// caller pastes the original untouched and quietly.
    func format(_ text: String, as language: CodeLanguage) async -> String?
}

/// What may be run, and nothing else.
///
/// An allowlist rather than a search, because the alternative is executing whatever
/// happens to be on `PATH` under a familiar name. The clipboard is the last place to be
/// relaxed about that: this feature exists to reformat things the user is about to paste
/// into production, and a poisoned `prettier` would be handed every one of them.
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

    /// The arguments that make it read from standard input and write to standard output.
    ///
    /// Standard input, never an argument. The code being formatted is the user's and may
    /// contain anything at all; putting it on a command line is how a clip becomes a
    /// command.
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

    /// How long a formatter may take before it is given up on.
    ///
    /// Bounded because this runs while the user is waiting on a paste, and because a
    /// program that has hung must not take the panel with it. Three seconds is long past
    /// what any of these need for a clip-sized input.
    public static let timeout: TimeInterval = 3
}
