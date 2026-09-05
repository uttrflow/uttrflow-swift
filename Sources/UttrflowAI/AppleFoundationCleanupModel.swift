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

    /// One session made ahead of its request, shared by every copy of this value.
    private static let warmed = WarmedSession()

    public init() {}

    /// Makes the next utterance's session now and lets the system load its instructions. See `Docs/early-transcription.md`.
    public func warm(instructions: String) async {
        let session = LanguageModelSession(instructions: instructions)
        session.prewarm()
        await Self.warmed.keep(session, for: instructions)
    }

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
        let session =
            await Self.warmed.take(for: instructions) ?? LanguageModelSession(instructions: instructions)
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

/// Holds one session that was made before its request, and hands it out exactly once.
private actor WarmedSession {
    private var session: LanguageModelSession?
    private var instructions: String?

    /// Keeps `session` for the next request carrying `instructions`, dropping any earlier one.
    func keep(_ session: LanguageModelSession, for instructions: String) {
        self.session = session
        self.instructions = instructions
    }

    /// The kept session when it was made for `instructions`, and never the same one twice.
    func take(for instructions: String) -> LanguageModelSession? {
        defer {
            session = nil
            self.instructions = nil
        }
        return self.instructions == instructions ? session : nil
    }
}
