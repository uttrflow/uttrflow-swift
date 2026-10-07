// Named fixtures shared by every test target.
public import UttrflowCore
public import struct Foundation.URL
public import class Foundation.FileManager

// Named fixtures, so no test file re-invents a "typical" transcription or context.

extension AudioSamples {
    /// A silent buffer of a given length at the canonical rate.
    public static func silence(seconds: Double) -> AudioSamples {
        let count = Int(Double(canonicalSampleRate) * seconds)
        return AudioSamples(samples: Array(repeating: 0, count: count), sampleRate: canonicalSampleRate)
            ?? .empty
    }

    /// A quiet room at -70 dBFS: never loud enough to be speech, never the exact zeros of a muted input.
    public static func roomTone(seconds: Double) -> AudioSamples {
        let count = Int(Double(canonicalSampleRate) * seconds)
        let level: Float = 0.000_316
        return .canonical((0..<count).map { $0.isMultiple(of: 2) ? level : -level })
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
        bundleIdentifier: String? = DestinationRules.slack,
        documentName: String? = "#engineering",
        selectedText: String? = nil,
        precedingText: String? = nil,
        followingText: String? = nil,
        isSecure: Bool = false
    ) -> AppContext {
        AppContext(
            applicationName: applicationName,
            bundleIdentifier: bundleIdentifier,
            documentName: documentName,
            selectedText: selectedText,
            precedingText: precedingText,
            followingText: followingText,
            isSecure: isSecure
        )
    }
}

extension TransformationRequest {
    public static func fixture(
        transcription: Transcription = .fixture(),
        context: AppContext = .fixture(),
        profile: UserProfile = .default,
        situation: Situation? = nil
    ) -> TransformationRequest {
        TransformationRequest(
            transcription: transcription, context: context, profile: profile, situation: situation)
    }
}

/// The POSIX permissions of whatever is at `url`, so a test can say who may read what a store wrote.
public func posixMode(of url: URL) -> Int? {
    try? FileManager.default.attributesOfItem(atPath: url.path(percentEncoded: false))[
        .posixPermissions] as? Int
}
