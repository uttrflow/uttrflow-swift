// Every failure enum chained into one list, so one test can prove each case has a sentence for the user.

/// A failure enum that hands back one value of every case through a `switch` the compiler checks for gaps.
public protocol CataloguedFailure: UttrflowFailure {
    /// The head of the chain.
    static var firstCase: Self { get }
    /// The case after this one, or `nil` at the end of the chain.
    var caseAfter: Self? { get }
}

extension CataloguedFailure {
    /// One value of every case in chain order, with empty placeholders for associated data.
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

/// Every failure the product can raise, in one list; a new failure enum is added with exactly one line here.
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
