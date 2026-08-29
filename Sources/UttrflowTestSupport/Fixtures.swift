public import UttrflowCore

// Named fixtures keep tests readable and stop every test file from re-inventing a
// "typical" transcription or context.

extension AudioSamples {
    /// A silent buffer of a given length at the canonical rate.
    public static func silence(seconds: Double) -> AudioSamples {
        let count = Int(Double(canonicalSampleRate) * seconds)
        return AudioSamples(samples: Array(repeating: 0, count: count), sampleRate: canonicalSampleRate)
            ?? .empty
    }
}

extension Transcription {
    /// A short, realistic raw transcript: filler word, no punctuation, lowercase.
    public static func fixture(
        text: String = "um i'll be about twenty minutes late to the meeting",
        language: LanguageCode? = .english,
        confidence: Double? = 0.95,
        audioDuration: Duration = .seconds(4)
    ) -> Transcription {
        Transcription(
            text: text,
            detectedLanguage: language.map { DetectedLanguage(code: $0, confidence: confidence) },
            audioDuration: audioDuration
        )
    }
}

extension AppContext {
    /// A messaging app, the commonest real target.
    public static func fixture(
        applicationName: String? = "Slack",
        bundleIdentifier: String? = "com.tinyspeck.slackmacgap",
        documentName: String? = "#engineering",
        selectedText: String? = nil
    ) -> AppContext {
        AppContext(
            applicationName: applicationName,
            bundleIdentifier: bundleIdentifier,
            documentName: documentName,
            selectedText: selectedText
        )
    }
}

extension TransformationRequest {
    public static func fixture(
        transcription: Transcription = .fixture(),
        context: AppContext = .fixture(),
        profile: UserProfile = .default
    ) -> TransformationRequest {
        TransformationRequest(transcription: transcription, context: context, profile: profile)
    }
}
