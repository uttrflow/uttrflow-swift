import Testing

@testable import UttrflowCore

/// Every failure the product can raise, from the catalogue the product itself keeps.
///
/// Written out here once, as a hand-maintained array in two separate test targets, it
/// drifted: ``HotkeyError`` reached the interface's list and never reached this one, so
/// the two hotkey errors went unchecked by the very file that exists to prove every
/// failure explains itself. ``FailureCatalogue`` is now the single list, and each enum's
/// share of it is chained through a `switch` the compiler will not let go stale.
private let allFailures = FailureCatalogue.everyFailure

@Suite("The catalogue of failures")
struct FailureCatalogueTests {
    /// What the chain is for. If a case is added to an enum and linked in, it appears
    /// here without anyone editing a test; if it is added and not linked in, the module
    /// does not compile. Neither is what happened to ``HotkeyError``, which is the point.
    @Test("lists every case of every failure the product declares")
    func coversEveryCase() {
        #expect(PermissionError.everyCase.count == 3)
        #expect(AccountError.everyCase.count == 4)
        #expect(SnippetStoreError.everyCase.count == 4)
        #expect(AudioCaptureError.everyCase.count == 5)
        #expect(SpeechEngineError.everyCase.count == 6)
        #expect(TransformationError.everyCase.count == 3)
        #expect(TextInsertionError.everyCase.count == 4)
        #expect(HotkeyError.everyCase.count == 2)
        #expect(DictionaryStoreError.everyCase.count == 3)
        #expect(allFailures.count == 35)
    }

    /// A chain that links backwards would loop forever, and one that repeats a case
    /// would hide the case it displaced. Both show up as a duplicate.
    @Test("links each case exactly once")
    func chainsWithoutRepeating() {
        for cases in [
            PermissionError.everyCase.map { "\($0)" },
            AudioCaptureError.everyCase.map { "\($0)" },
            SpeechEngineError.everyCase.map { "\($0)" },
            TransformationError.everyCase.map { "\($0)" },
            TextInsertionError.everyCase.map { "\($0)" },
            HotkeyError.everyCase.map { "\($0)" },
        ] {
            #expect(Set(cases).count == cases.count, "a case is chained twice: \(cases)")
        }
    }
}

@Suite("Failure presentation")
struct FailurePresentationTests {
    @Test("gives every failure a complete, non-empty sentence")
    func everyFailureExplainsItself() {
        for failure in allFailures {
            #expect(!failure.userMessage.isEmpty, "\(failure) has no message")
            #expect(
                failure.userMessage.hasSuffix(".") || failure.userMessage.hasSuffix("!"),
                "\(failure) message is not a sentence: \(failure.userMessage)"
            )
        }
    }

    /// §16: the user must never learn which engine is running.
    @Test("never leaks an implementation name into a user-facing message")
    func neverNamesAnEngine() {
        let forbidden = [
            "whisper", "whisperkit", "foundation model", "llm", "coreml", "mlx",
            "model weights", "transformer", "inference",
        ]
        for failure in allFailures {
            let message = failure.userMessage.lowercased()
            for term in forbidden {
                #expect(!message.contains(term), "\(failure) leaks '\(term)': \(failure.userMessage)")
            }
        }
    }

    @Test("offers a recovery action wherever one could actually help")
    func recoveryActions() {
        #expect(PermissionError.microphoneDenied.recovery == .openSystemSettings(.microphone))
        #expect(PermissionError.accessibilityNotTrusted.recovery == .openSystemSettings(.accessibility))
        // A policy-restricted microphone cannot be fixed by the user, so offering an
        // action would be a lie.
        #expect(PermissionError.microphoneRestricted.recovery == nil)

        #expect(AudioCaptureError.noInputDevice.recovery == nil)
        #expect(AudioCaptureError.unsupportedInputFormat.recovery == nil)
        #expect(AudioCaptureError.alreadyRecording.recovery == .retry)
        #expect(AudioCaptureError.notRecording.recovery == .retry)
        #expect(AudioCaptureError.engineFailed(description: "x").recovery == .retry)

        #expect(SpeechEngineError.modelNotInstalled.recovery == .downloadSpeechModel)
        #expect(SpeechEngineError.modelDownloadFailed(description: "x").recovery == .downloadSpeechModel)
        #expect(SpeechEngineError.modelLoadFailed(description: "x").recovery == .retry)
        #expect(SpeechEngineError.audioTooShort.recovery == .retry)
        #expect(SpeechEngineError.transcriptionFailed(description: "x").recovery == .retry)

        #expect(TextInsertionError.noFocusedTextField.recovery == .retry)
        #expect(TextInsertionError.accessibilityDenied.recovery == .openSystemSettings(.accessibility))
        #expect(TextInsertionError.insertionRejected(description: "x").recovery == .pasteManually)

        #expect(HotkeyError.observationNotPermitted.recovery == .openSystemSettings(.accessibility))
        #expect(HotkeyError.shortcutUnavailable.recovery == .retry)
    }

    /// The one failure whose message and action used to contradict each other: it said
    /// the text could not be copied and then offered a button that meant "paste it".
    @Test("never sends the user to the clipboard when the clipboard is what failed")
    func clipboardFailureDoesNotOfferAPaste() {
        let failure = TextInsertionError.clipboardUnavailable
        #expect(failure.recovery == .showRecentDictations)
        #expect(!failure.userMessage.lowercased().contains("paste"))
        #expect(failure.userMessage.contains("Recent"))
    }

    /// §19 read strictly: a failure that costs the user their dictation is a different
    /// thing to show than one that costs them a second of their time, and only the
    /// error itself knows which it is.
    @Test("says what each failure actually costs")
    func severities() {
        #expect(PermissionError.microphoneDenied.severity == .blocking)
        #expect(PermissionError.microphoneRestricted.severity == .blocking)
        // The words still arrive, on the clipboard rather than in the app.
        #expect(PermissionError.accessibilityNotTrusted.severity == .degraded)

        #expect(AudioCaptureError.noInputDevice.severity == .blocking)
        #expect(AudioCaptureError.unsupportedInputFormat.severity == .blocking)
        #expect(AudioCaptureError.alreadyRecording.severity == .recoverable)
        #expect(AudioCaptureError.notRecording.severity == .recoverable)
        #expect(AudioCaptureError.engineFailed(description: "x").severity == .recoverable)

        #expect(SpeechEngineError.modelNotInstalled.severity == .recoverable)
        #expect(SpeechEngineError.modelDownloadFailed(description: "x").severity == .recoverable)
        #expect(SpeechEngineError.modelLoadFailed(description: "x").severity == .recoverable)
        #expect(SpeechEngineError.transcriptionFailed(description: "x").severity == .recoverable)
        // Not an error at all: half a second of silence, worded so it does not read
        // like one and drawn grey rather than orange.
        #expect(SpeechEngineError.audioTooShort.severity == .informational)

        #expect(TransformationError.noCapableTransformer.severity == .degraded)

        #expect(TextInsertionError.noFocusedTextField.severity == .recoverable)
        #expect(TextInsertionError.accessibilityDenied.severity == .degraded)
        #expect(TextInsertionError.clipboardUnavailable.severity == .degraded)
        #expect(TextInsertionError.insertionRejected(description: "x").severity == .degraded)
    }

    /// The defect that made severity worth declaring at all. Both hotkey errors stop
    /// dictation dead, and one of them asks for the same Accessibility pane as a
    /// genuinely degraded failure — so anything reading severity off the recovery
    /// action called it degraded and let the notice dismiss itself.
    @Test("treats a shortcut that cannot fire as blocking, however it is fixed")
    func hotkeyFailuresAreBlocking() {
        for failure in HotkeyError.everyCase {
            #expect(failure.severity == .blocking, "\(failure) is not blocking")
        }
        #expect(
            HotkeyError.observationNotPermitted.recovery
                == PermissionError.accessibilityNotTrusted.recovery,
            "the two share a recovery, which is why severity cannot be read off it")
        #expect(PermissionError.accessibilityNotTrusted.severity == .degraded)
    }

    /// §19: a clean-up failure must never lose the user's words.
    @Test("always keeps the transcript reachable when clean-up fails")
    func transformationFailuresPreserveTheTranscript() {
        let failures: [TransformationError] = [
            .noCapableTransformer,
            .transformFailed(kind: .localModel, description: "x"),
            .outputRejected(reason: "x"),
        ]
        for failure in failures {
            #expect(failure.recovery == .pasteManually)
        }
    }

    @Test("distinguishes failures that carry different detail")
    func equatable() {
        #expect(AudioCaptureError.engineFailed(description: "a") != .engineFailed(description: "b"))
        #expect(
            TransformationError.transformFailed(kind: .rules, description: "a")
                != .transformFailed(kind: .localModel, description: "a")
        )
        #expect(SpeechEngineError.modelNotInstalled == .modelNotInstalled)
    }
}

@Suite("Permission mapping")
struct PermissionMappingTests {
    @Test("sends each permission to the settings pane that actually controls it")
    func settingsPanes() {
        #expect(PermissionKind.microphone.settingsPane == .microphone)
        #expect(PermissionKind.accessibility.settingsPane == .accessibility)
    }

    @Test("maps each permission to the failure raised when it is missing")
    func failures() {
        #expect(PermissionKind.microphone.failure == .microphoneDenied)
        #expect(PermissionKind.accessibility.failure == .accessibilityNotTrusted)
    }

    @Test("maps every permission without a gap")
    func coversEveryPermission() {
        for kind in PermissionKind.allCases {
            #expect(SystemSettingsPane.allCases.contains(kind.settingsPane))
        }
    }

    @Test("treats only granted as granted")
    func grantedStatus() {
        #expect(PermissionStatus.granted.isGranted)
        for status in [PermissionStatus.notDetermined, .denied, .restricted] {
            #expect(!status.isGranted)
        }
    }
}
