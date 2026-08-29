/// A failure enum that can hand back one value of every case it has.
///
/// Swift synthesises `CaseIterable` only for enums whose cases all lack associated
/// values, and half of Uttrflow's do not qualify. So the cases are chained by hand —
/// but through a `switch`, which the compiler *does* check: adding a case makes
/// ``caseAfter`` non-exhaustive and the module stops building until the new case has
/// been given a place in the chain. That is the difference between this and a plain
/// hand-written array, which is what silently lost ``HotkeyError`` from one of the two
/// lists that used to exist.
///
/// The chain is not proof against a deliberately wrong link — an author who answers the
/// compiler with `nil` in the middle truncates the list, and one who links backwards
/// makes ``everyCase`` spin. Neither survives reading the diff, which a missing array
/// entry did.
public protocol CataloguedFailure: UttrflowFailure {
    /// The head of the chain.
    static var firstCase: Self { get }
    /// The case after this one, or `nil` at the end of the chain.
    var caseAfter: Self? { get }
}

extension CataloguedFailure {
    /// One value of every case, in the order the chain links them.
    ///
    /// Values carrying associated data get an empty placeholder: this list exists to
    /// prove that every *case* has a story for the user, and no message is written from
    /// the data anyway.
    public static var everyCase: [Self] { Array(sequence(first: firstCase, next: \.caseAfter)) }
}

extension PermissionError: CataloguedFailure {
    public static var firstCase: Self { .microphoneDenied }

    public var caseAfter: Self? {
        switch self {
        case .microphoneDenied: .microphoneRestricted
        case .microphoneRestricted: .accessibilityNotTrusted
        case .accessibilityNotTrusted: nil
        }
    }
}

extension AudioCaptureError: CataloguedFailure {
    public static var firstCase: Self { .noInputDevice }

    public var caseAfter: Self? {
        switch self {
        case .noInputDevice: .alreadyRecording
        case .alreadyRecording: .notRecording
        case .notRecording: .unsupportedInputFormat
        case .unsupportedInputFormat: .engineFailed(description: "")
        case .engineFailed: nil
        }
    }
}

extension SpeechEngineError: CataloguedFailure {
    public static var firstCase: Self { .modelNotInstalled }

    public var caseAfter: Self? {
        switch self {
        case .modelNotInstalled: .modelDownloadFailed(description: "")
        case .modelDownloadFailed: .modelLoadFailed(description: "")
        case .modelLoadFailed: .audioTooShort
        case .audioTooShort: .nothingHeard
        case .nothingHeard: .transcriptionFailed(description: "")
        case .transcriptionFailed: nil
        }
    }
}

extension TransformationError: CataloguedFailure {
    public static var firstCase: Self { .noCapableTransformer }

    public var caseAfter: Self? {
        switch self {
        case .noCapableTransformer: .transformFailed(kind: .rules, description: "")
        case .transformFailed: .outputRejected(reason: "")
        case .outputRejected: nil
        }
    }
}

extension AccountError: CataloguedFailure {
    public static var firstCase: Self { .serverUnreachable }

    public var caseAfter: Self? {
        switch self {
        case .serverUnreachable: .providerRefused(description: "")
        case .providerRefused: .sessionMalformed
        case .sessionMalformed: .sessionCouldNotBeKept
        case .sessionCouldNotBeKept: nil
        }
    }
}

extension DictionaryStoreError: CataloguedFailure {
    public static var firstCase: Self { .couldNotWrite }

    public var caseAfter: Self? {
        switch self {
        case .couldNotWrite: .wordIsEmpty
        case .wordIsEmpty: .wordAlreadyKnown
        case .wordAlreadyKnown: nil
        }
    }
}

extension SnippetStoreError: CataloguedFailure {
    public static var firstCase: Self { .couldNotWrite }

    public var caseAfter: Self? {
        switch self {
        case .couldNotWrite: .triggerHasNoWords
        case .triggerHasNoWords: .triggerAlreadyUsed
        case .triggerAlreadyUsed: .expansionIsEmpty
        case .expansionIsEmpty: nil
        }
    }
}

extension HistoryStoreError: CataloguedFailure {
    public static var firstCase: Self { .couldNotWrite }

    public var caseAfter: Self? {
        switch self {
        case .couldNotWrite: nil
        }
    }
}

extension TextInsertionError: CataloguedFailure {
    public static var firstCase: Self { .noFocusedTextField }

    public var caseAfter: Self? {
        switch self {
        case .noFocusedTextField: .accessibilityDenied
        case .accessibilityDenied: .clipboardUnavailable
        case .clipboardUnavailable: .insertionRejected(description: "")
        case .insertionRejected: nil
        }
    }
}

extension HotkeyError: CataloguedFailure {
    public static var firstCase: Self { .observationNotPermitted }

    public var caseAfter: Self? {
        switch self {
        case .observationNotPermitted: .shortcutUnavailable
        case .shortcutUnavailable: nil
        }
    }
}

/// Every failure the product can raise, in one place.
///
/// One list rather than one per test target. The two that existed before disagreed —
/// ``HotkeyError`` was in the interface's and missing from the core's — and a rule that
/// is only enforced against half the errors is not enforced.
///
/// Registering a *new enum* here is the one step still left to a person: Swift cannot
/// enumerate the conformers of a protocol, so nothing can notice a seventh error type
/// that never joined the list. What it can do is make forgetting cost something —
/// there is now exactly one line to add, and every failure test walks this.
public enum FailureCatalogue {
    /// One value of every case of every failure enum in the product.
    public static let everyFailure: [any UttrflowFailure] =
        cases(of: PermissionError.self)
        + cases(of: AudioCaptureError.self)
        + cases(of: SpeechEngineError.self)
        + cases(of: TransformationError.self)
        + cases(of: TextInsertionError.self)
        + cases(of: HotkeyError.self)
        + cases(of: HistoryStoreError.self)
        + cases(of: AccountError.self)
        + cases(of: DictionaryStoreError.self)
        + cases(of: SnippetStoreError.self)

    /// Widens one enum's cases to the existential the list is built from.
    private static func cases<Failure: CataloguedFailure>(
        of type: Failure.Type
    ) -> [any UttrflowFailure] {
        Failure.everyCase
    }
}
