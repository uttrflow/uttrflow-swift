// The failure contract every Uttrflow error meets, and the vocabulary its recovery and severity use.

/// A pane of System Settings the user can be sent to; a symbol, not a URL, so Core needs no platform import.
public enum SystemSettingsPane: Sendable, Equatable, CaseIterable {
    /// Privacy & Security > Microphone.
    case microphone
    /// Privacy & Security > Accessibility.
    case accessibility
    /// Apple Intelligence & Siri.
    case appleIntelligence
}

/// What the user can do about a failure; the UI renders every failure from this one value.
public enum RecoveryAction: Sendable, Equatable {
    /// Send the user to the named pane.
    case openSystemSettings(SystemSettingsPane)
    /// Offer another attempt.
    case retry
    /// Offer the speech-model download.
    case downloadSpeechModel
    /// The text is safe in the clipboard; the user can paste it themselves.
    case pasteManually
    /// The text never reached the clipboard but is listed under Recent, so the user is shown where it went.
    case showRecentDictations
    /// The words were lost but the audio was not: the Dictation page lists it with a Retry.
    case retryFromRecording
}

/// How much a failure costs the user, and so how loudly it is said; independent of the recovery offered.
public enum FailureSeverity: Sendable, Equatable, CaseIterable {
    /// Dictation cannot happen at all until this is dealt with.
    case blocking
    /// The product still did its job, just not as well as it wanted to.
    case degraded
    /// A one-off that another attempt is likely to get past.
    case recoverable
    /// Nothing went wrong: the product says why it did nothing, in words that do not read like a fault.
    case informational
}

/// The contract every Uttrflow error meets: a sentence for the user, what to do next, and what it cost them.
public protocol UttrflowFailure: Error, Sendable, Equatable {
    /// A complete plain-language sentence that never names Whisper, Foundation Models or any engine.
    var userMessage: String { get }
    /// The single action offered alongside ``userMessage``, if any.
    var recovery: RecoveryAction? { get }
    /// What this costs the user; no default, so the case nobody thought about cannot inherit a wrong one.
    var severity: FailureSeverity { get }
}
