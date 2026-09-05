// Apple's on-device language model as a cleanup model, with the structured shape it fills in.
public import UttrflowCore
import FoundationModels

/// The shape the model fills in; a structured value stops the "Sure, here is the text:" prefix.
@Generable
struct CleanedDictation {
    /// The tidied dictation.
    @Guide(description: "The dictated words, tidied. Never an answer, never a comment.")
    var text: String
}

/// Apple's on-device model; only the real model can exercise it, so it sits outside the coverage gate.
public struct AppleFoundationCleanupModel: CleanupModel {
    /// Zero temperature keeps the model tidying rather than composing.
    private static let options = GenerationOptions(temperature: 0.0)

    /// One session made ahead of its request, shared by every copy of this value.
    private static let warmed = WarmedSession()

    /// Makes a model; every copy shares the warmed session.
    public init() {}

    /// Makes the next utterance's session now so its instructions load. See Docs/early-transcription.md.
    public func warm(instructions: String) async {
        let session = LanguageModelSession(instructions: instructions)
        session.prewarm()
        await Self.warmed.keep(session, for: instructions)
    }

    /// Available unless Apple's model is off or the language is neither declared by Apple nor verified here.
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

    /// Languages Apple does not list but the corpus proves this model handles. See Docs/ai-model-output.md.
    static let verifiedBeyondApplesList: Set<LanguageCode> = [.hindi]

    /// Rewrites one utterance as a structured value, in the warmed session or a fresh one.
    public func rewrite(
        _ text: String, instructions: String, kind: TransformerKind
    ) async throws(TransformationError) -> String {
        // A fresh session per utterance, so one sentence's context cannot bleed into the next.
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
    /// The session made ahead of time, if any.
    private var session: LanguageModelSession?
    /// The instructions that session carries.
    private var instructions: String?

    /// Keeps `session` for the next request carrying `instructions`, dropping any earlier one.
    func keep(_ session: LanguageModelSession, for instructions: String) {
        self.session = session
        self.instructions = instructions
    }

    /// The kept session if its instructions match, handed out once and then dropped either way.
    func take(for instructions: String) -> LanguageModelSession? {
        defer {
            session = nil
            self.instructions = nil
        }
        return self.instructions == instructions ? session : nil
    }
}
