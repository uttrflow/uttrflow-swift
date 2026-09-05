// Tests that every catalogued failure explains itself, offers a true recovery and says its cost.

import Testing

@testable import UttrflowCore

/// Every failure the product can raise, from the one catalogue the product keeps.
private let allFailures = FailureCatalogue.everyFailure

@Suite("The catalogue of failures")
struct FailureCatalogueTests {
    /// A case linked into its chain appears here with no test edited; one left out stops the module compiling.
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

    /// A backwards link loops and a repeated case hides the one it displaces; both show as a duplicate.
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
        // A policy-restricted microphone cannot be fixed by the user, so an action would be a lie.
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

    /// A message saying the text could not be copied must not come with a button meaning "paste it".
    @Test("never sends the user to the clipboard when the clipboard is what failed")
    func clipboardFailureDoesNotOfferAPaste() {
        let failure = TextInsertionError.clipboardUnavailable
        #expect(failure.recovery == .showRecentDictations)
        #expect(!failure.userMessage.lowercased().contains("paste"))
        #expect(failure.userMessage.contains("Recent"))
    }

    /// Only the error itself knows whether it cost the user their dictation or a second of their time.
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
        // Not an error at all: half a second of silence, worded and drawn so it does not read like one.
        #expect(SpeechEngineError.audioTooShort.severity == .informational)

        #expect(TransformationError.noCapableTransformer.severity == .degraded)

        #expect(TextInsertionError.noFocusedTextField.severity == .recoverable)
        #expect(TextInsertionError.accessibilityDenied.severity == .degraded)
        #expect(TextInsertionError.clipboardUnavailable.severity == .degraded)
        #expect(TextInsertionError.insertionRejected(description: "x").severity == .degraded)
    }

    /// Both hotkey errors stop dictation dead, and one shares its recovery with a merely degraded failure.
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
