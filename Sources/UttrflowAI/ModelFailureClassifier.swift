// Maps the system language model's errors to the closed failure classes, by case and never by message.
public import UttrflowCore
import FoundationModels

extension ModelFailureClass {
    /// The class of an error thrown by Apple's on-device model; unknown cases are `other`.
    public static func ofSystemModel(_ error: any Error) -> ModelFailureClass {
        guard let generation = error as? LanguageModelSession.GenerationError else { return of(error) }
        switch generation {
        case .exceededContextWindowSize: return .contextTooLarge
        case .assetsUnavailable: return .notReady
        case .guardrailViolation: return .guardrail
        case .unsupportedGuide: return .unsupportedSchema
        case .unsupportedLanguageOrLocale: return .unsupportedLanguage
        case .decodingFailure: return .decoding
        case .rateLimited, .concurrentRequests: return .rateLimited
        case .refusal: return .refusedByModel
        @unknown default: return .other
        }
    }
}
