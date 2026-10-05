// Why a clean-up model ran and gave no answer, said without the model's own error text.

/// The closed set of reasons a model gave no answer, which a record and a pasted report may carry.
public enum ModelFailureClass: String, Sendable, Equatable, CaseIterable, Codable {
    /// The model's safety filter refused the request or its answer.
    case guardrail
    /// The request did not fit the model's context window.
    case contextTooLarge
    /// The model's weights or assets were not ready to run.
    case notReady
    /// The system throttled the request or another request held the model.
    case rateLimited
    /// The model does not work in the language or locale it was given.
    case unsupportedLanguage
    /// The model could not fill in the structured answer it was asked for.
    case decoding
    /// The model rejected the shape of the structured answer it was asked for.
    case unsupportedSchema
    /// The model itself declined to answer.
    case refusedByModel
    /// The model took longer than the route allowed.
    case timedOut
    /// The request was cancelled before the model answered.
    case cancelled
    /// Any failure no other case names.
    case other

    /// The class of an error no model framework names, which is a cancellation or nothing known.
    public static func of(_ error: any Error) -> ModelFailureClass {
        error is CancellationError ? .cancelled : .other
    }

    /// What a pasted report calls this, which names the class and never the error text.
    public var summary: String {
        switch self {
        case .guardrail: "the safety filter refused it"
        case .contextTooLarge: "the request was too long for the model"
        case .notReady: "the model was not ready"
        case .rateLimited: "the model was busy or throttled"
        case .unsupportedLanguage: "the model does not support the language"
        case .decoding: "the model's answer could not be read"
        case .unsupportedSchema: "the model rejected the answer's shape"
        case .refusedByModel: "the model declined to answer"
        case .timedOut: "timed out"
        case .cancelled: "cancelled"
        case .other: "failed"
        }
    }
}
