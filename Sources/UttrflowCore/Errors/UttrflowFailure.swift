/// A pane of System Settings the user can be sent to in order to fix something.
///
/// Held as a symbol rather than a URL so that ``UttrflowCore`` stays free of platform
/// imports; the presentation layer owns the mapping to an actual settings link.
public enum SystemSettingsPane: Sendable, Equatable, CaseIterable {
    case microphone
    case accessibility
    case appleIntelligence
}

/// What the user can do about a failure.
///
/// The UI renders any failure from this one value, so a new error never needs new
/// presentation code — only a correct ``UttrflowFailure/recovery``.
public enum RecoveryAction: Sendable, Equatable {
    case openSystemSettings(SystemSettingsPane)
    case retry
    case downloadSpeechModel
    /// The text is safe in the clipboard; the user can paste it themselves.
    case pasteManually
    /// The text never reached the clipboard, but it was not lost: it is listed under
    /// Recent in the menu bar. Offering ``pasteManually`` here would name the one
    /// place the words are certainly not, so the user is shown where they went instead.
    case showRecentDictations
    /// The words were lost but the audio was not: the Dictation page lists it with a Retry.
    case retryFromRecording
}

/// How much a failure costs the user, and therefore how loudly it is said.
///
/// Declared by each error rather than worked out from ``UttrflowFailure/recovery``,
/// because the two are genuinely independent: the same "open System Settings" is a
/// dead stop for the microphone and an inconvenience for Accessibility, and the same
/// "try again" is an apology after a crash and a shrug after half a second of silence.
/// Reading one off the other got exactly those cases wrong.
public enum FailureSeverity: Sendable, Equatable, CaseIterable {
    /// Dictation cannot happen at all until this is dealt with.
    case blocking
    /// The product still did its job, just not as well as it wanted to.
    case degraded
    /// A one-off that another attempt is likely to get past.
    case recoverable
    /// Nothing went wrong: the product is saying why it did nothing, and the words are
    /// chosen so that it does not read like a fault.
    case informational
}

/// The contract every Uttrflow error meets: it can explain itself to a user, it says
/// what to do next, and it says how much the user has lost.
///
/// Conforming to this instead of writing per-error alert code is what keeps §19's
/// error handling in one place.
public protocol UttrflowFailure: Error, Sendable, Equatable {
    /// A complete sentence, in plain language, with no implementation detail in it.
    /// Never mentions Whisper, Foundation Models, or any engine name.
    var userMessage: String { get }
    /// The single action offered alongside ``userMessage``, if any.
    var recovery: RecoveryAction? { get }
    /// What this costs the user.
    ///
    /// Deliberately without a default. A default is how one wrong answer spreads: the
    /// case that gets it wrong is the one nobody thought about, which is precisely the
    /// case that would have inherited the default.
    var severity: FailureSeverity { get }
}
