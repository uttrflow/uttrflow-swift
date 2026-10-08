// Why the speech model did not load, said without the recogniser's own error text.

/// The closed set of reasons a speech model load ended without a model, which Diagnostics names.
public enum SpeechLoadFailureClass: String, Sendable, Equatable, CaseIterable, Codable {
    /// A pinned file or the tokenizer is missing or not at its pinned size.
    case missingFiles
    /// Every file is there, but some do not hash to their pins.
    case damaged
    /// The load did not finish within the pipeline's load limit.
    case timedOut
    /// Any failure no other case names, which a retry may get past.
    case other

    /// The class of a load that threw `error`.
    public init(_ error: any Error) {
        switch error as? SpeechEngineError {
        case .modelNotInstalled: self = .missingFiles
        case .modelDamaged: self = .damaged
        default: self = .other
        }
    }

    /// What Diagnostics says after "Failed to load".
    public var summary: String {
        switch self {
        case .missingFiles: "files missing"
        case .damaged: "files damaged"
        case .timedOut: "timed out"
        case .other: "unknown cause"
        }
    }
}
