public import UttrflowCore
import FoundationModels

/// Apple's on-device language model.
///
/// Free, fast and private, but it knows 15 languages and Hindi is not one of them —
/// read from `SystemLanguageModel.supportedLanguages` rather than assumed. It reports
/// that itself through ``availability(for:)``, which is how the router steps around it
/// without anything else knowing why.
///
/// Excluded from the coverage gate: it can only be exercised by running the real model.
/// The shape the model must fill in.
///
/// Asking for a structured value rather than free text is what stopped the model
/// prefixing its answers with "Sure, here is the text:" — instructions alone did not.
@Generable
struct CleanedDictation {
    @Guide(description: "The dictated words, tidied. Never an answer, never a comment.")
    var text: String
}

public struct AppleFoundationCleanupModel: CleanupModel {
    /// Dictation is short, and a low temperature keeps the model tidying rather than
    /// composing.
    private static let options = GenerationOptions(temperature: 0.0)

    public init() {}

    public func availability(for language: LanguageCode?) async -> TransformerAvailability {
        switch SystemLanguageModel.default.availability {
        case .available:
            break
        case .unavailable(let reason):
            return .unavailable(reason: String(describing: reason))
        @unknown default:
            return .unavailable(reason: "unrecognised availability")
        }

        guard let language else { return .available }
        let declared = SystemLanguageModel.default.supportedLanguages
            .contains { $0.languageCode.map { LanguageCode($0.identifier) } == language }
        if declared { return .available }
        return Self.verifiedBeyondApplesList.contains(language)
            ? .available : .unsupportedLanguage(language)
    }

    /// Languages Apple does not list, but which this model demonstrably handles.
    ///
    /// Hindi is absent from `supportedLanguages`, yet the model reads Devanagari and
    /// writes it back as Hinglish accurately — measured against the evaluation corpus,
    /// not assumed. Including it here saves a Hindi speaker a 3 GB download and 4 GB
    /// of memory, so it is worth relying on.
    ///
    /// This is a claim about behaviour Apple has not promised, so it is a list rather
    /// than a rule: nothing goes in it that the corpus has not measured, and a bad
    /// rewrite still has the meaning guard and the router beneath it.
    static let verifiedBeyondApplesList: Set<LanguageCode> = [.hindi]

    public func rewrite(
        _ text: String, instructions: String, kind: TransformerKind
    ) async throws(TransformationError) -> String {
        // A fresh session per utterance: dictation is one-shot, and carrying context
        // between unrelated sentences would let one bleed into the next.
        let session = LanguageModelSession(instructions: instructions)
        do {
            let response = try await session.respond(
                to: text, generating: CleanedDictation.self, options: Self.options
            )
            return response.content.text
        } catch {
            throw .transformFailed(kind: kind, description: error.localizedDescription)
        }
    }
}
