// Tests what the floating button shows for each state.
import Foundation
import Testing

@testable import UttrflowCore
@testable import UttrflowPipeline

// MARK: - Fixtures

/// Free of any word the §16 guard forbids, so a leak is the presenter's doing, never the fixture's.
private let spokenWords = "Right, so the plan for tomorrow is to finish the drafting."

private let insertedOutcome = DictationOutcome(
    text: spokenWords, method: .accessibility, cleanedBy: .rules)

/// A failure that still has the user's words to offer — §19's case.
private let failureWithWords = DictationFailure(
    message: TransformationError.outputRejected(reason: "meaning changed").userMessage,
    recovery: .pasteManually,
    severity: .degraded,
    transcript: spokenWords)

/// A failure with nothing to salvage, so the second line has nothing to say.
private let failureWithoutWords = DictationFailure(
    message: PermissionError.microphoneDenied.userMessage,
    recovery: .openSystemSettings(.microphone),
    severity: .blocking)

/// Every state the interface can draw, so a new case cannot be added without meeting the rules.
private let everyState: [DictationState] = [
    .idle,
    .recording,
    .transcribing,
    .tidying,
    .inserted(insertedOutcome),
    .failed(failureWithWords),
    .failed(failureWithoutWords),
]

/// Punctuation a spoken sentence may reasonably end on.
private let sentenceEndings = [".", "!", "?", "…"]

// MARK: - Coverage of every state

@Suite("Dictation presentation")
struct DictationPresentationTests {
    @Test("draws something for every state the pipeline can be in")
    func everyStateHasAPresentation() {
        for state in everyState {
            let dock = DictationPresenter.dock(for: state)
            #expect(!dock.symbolName.isEmpty, "\(state) has no dock symbol")
            #expect(!dock.accessibilityLabel.isEmpty, "\(state) has no dock label")
        }
    }

    @Test("lights the recording indicator and the waveform only while listening")
    func onlyRecordingIsRecording() {
        for state in everyState {
            let dock = DictationPresenter.dock(for: state)
            let listening = state == .recording
            #expect(dock.isRecording == listening, "\(state) got isRecording \(dock.isRecording)")
            #expect(
                dock.showsWaveform == listening, "\(state) got showsWaveform \(dock.showsWaveform)")
        }
    }

    @Test("shows progress only while there is work under way")
    func onlyWorkingStatesShowProgress() {
        for state in everyState {
            let dock = DictationPresenter.dock(for: state)
            let working = state == .transcribing || state == .tidying
            #expect(dock.showsProgress == working, "\(state) got showsProgress \(dock.showsProgress)")
        }
    }

    /// Transcribing and tidying are one wait to the person waiting.
    @Test("presents transcribing and tidying as the same single wait")
    func transcribingAndTidyingAreIndistinguishable() {
        #expect(DictationPresenter.dock(for: .transcribing) == DictationPresenter.dock(for: .tidying))
    }

    @Test("offers nothing to do when there is nothing the user could do")
    func onlyFailuresCarryAnAction() {
        for state in [
            DictationState.idle, .recording, .transcribing, .tidying,
            .inserted(insertedOutcome),
        ] {
            #expect(DictationPresenter.dock(for: state).action == nil, "\(state) offers an action")
        }
    }

    @Test("says nothing on the second line until there is something worth saying")
    func quietStatesHaveNoSecondLine() {
        for state in [DictationState.idle, .recording, .transcribing, .tidying] {
            let dock = DictationPresenter.dock(for: state)
            #expect(dock.secondaryLine == nil, "\(state) has a second line")
        }
        #expect(DictationPresenter.dock(for: .idle).primaryLine == nil)
        #expect(DictationPresenter.dock(for: .recording).primaryLine == "Let go to finish")
    }
}

// MARK: - Failure

@Suite("Failure presentation on screen")
struct FailureOnScreenTests {
    @Test("shows the failure's own sentence rather than a generic one")
    func surfacesTheFailuresMessage() {
        let dock = DictationPresenter.dock(for: .failed(failureWithoutWords))
        #expect(dock.primaryLine == failureWithoutWords.message)
        #expect(dock.accessibilityLabel == failureWithoutWords.message)
    }

    @Test("offers the failure's own recovery action")
    func surfacesTheRecoveryAction() {
        #expect(
            DictationPresenter.dock(for: .failed(failureWithoutWords)).action
                == .openSystemSettings(.microphone))
        #expect(DictationPresenter.dock(for: .failed(failureWithWords)).action == .pasteManually)
    }

    /// §19: whatever fails, the user's words must stay reachable.
    @Test("keeps the user's words on screen when the failure has any to offer")
    func surfacesTheTranscriptPreview() {
        let withWords = DictationPresenter.dock(for: .failed(failureWithWords))
        #expect(withWords.secondaryLine == DictationPresenter.preview(of: spokenWords))
        #expect(withWords.secondaryLine?.isEmpty == false)

        let withoutWords = DictationPresenter.dock(for: .failed(failureWithoutWords))
        #expect(withoutWords.secondaryLine == nil)
    }

    @Test("does not fall back to a generic notice when a failure explains itself")
    func doesNotReplaceAWrittenMessage() {
        struct UnforeseenError: Error {}
        let generic = DictationFailure(UnforeseenError())
        #expect(generic.message == "Something went wrong. Please try again.")
        #expect(DictationPresenter.dock(for: .failed(failureWithWords)).primaryLine != generic.message)
    }
}

// MARK: - Success

@Suite("Inserted presentation")
struct InsertedPresentationTests {
    @Test("shows a glance at the text that was just inserted")
    func previewsTheInsertedText() {
        let dock = DictationPresenter.dock(for: .inserted(insertedOutcome))
        #expect(dock.primaryLine == "Inserted")
        #expect(dock.secondaryLine == DictationPresenter.preview(of: spokenWords))
        #expect(dock.accessibilityLabel.contains(spokenWords))
    }

    @Test("shortens a long insertion so the button cannot cover the user's work")
    func previewsOnlyAGlanceOfALongInsertion() {
        let long = String(repeating: "one more sentence of dictation. ", count: 20)
        let outcome = DictationOutcome(text: long, method: .pasteboard, cleanedBy: .rules)
        let secondary = DictationPresenter.dock(for: .inserted(outcome)).secondaryLine
        #expect(secondary?.hasSuffix("…") == true)
        #expect((secondary?.count ?? 0) <= 61)
    }
}

// MARK: - §16

@Suite("Engine anonymity")
struct EngineAnonymityTests {
    /// §16: the user must never learn which engine ran, or a swap becomes a broken promise.
    @Test("never leaks an implementation name into anything the user can see or hear")
    func neverNamesAnEngine() {
        let forbidden = [
            "whisper", "whisperkit", "foundation model", "llm", "mlx", "coreml",
            "gemma", "qwen", "llama", "model", "inference", "transformer", "token",
        ]

        for state in everyState {
            let dock = DictationPresenter.dock(for: state)
            let visible: [String] =
                [dock.symbolName, dock.accessibilityLabel]
                + [dock.primaryLine, dock.secondaryLine].compactMap { $0 }

            for string in visible {
                let lowered = string.lowercased()
                for term in forbidden {
                    #expect(!lowered.contains(term), "\(state) leaks '\(term)': \(string)")
                }
            }
        }
    }
}

// MARK: - Preview

@Suite("Text preview")
struct TextPreviewTests {
    @Test("leaves a short line of text exactly as it was said")
    func shortTextIsUntouched() {
        #expect(DictationPresenter.preview(of: "Morning.") == "Morning.")
        #expect(DictationPresenter.preview(of: spokenWords) == spokenWords)
    }

    @Test("shortens a long line to the limit and marks that it was shortened")
    func longTextIsTruncated() {
        let long = String(repeating: "a", count: 200)
        let preview = DictationPresenter.preview(of: long, limit: 60)
        #expect(preview.hasSuffix("…"))
        #expect(preview.count == 61)
        #expect(String(preview.dropLast()) == String(repeating: "a", count: 60))
    }

    @Test("collapses runs of spaces and newlines into single spaces")
    func whitespaceIsCollapsed() {
        #expect(DictationPresenter.preview(of: "one   two\n\nthree\tfour") == "one two three four")
        #expect(DictationPresenter.preview(of: "  leading and trailing  ") == "leading and trailing")
    }

    /// Truncation that lands on a word boundary would otherwise read as "word …".
    @Test("never leaves a dangling space in front of the ellipsis")
    func noDanglingSpaceBeforeTheEllipsis() {
        let preview = DictationPresenter.preview(of: "abcdefghi jklmnop", limit: 10)
        #expect(preview == "abcdefghi…")
        #expect(!preview.contains(" …"))
    }

    @Test("returns nothing at all for text that has nothing in it")
    func emptyTextPreviewsAsEmpty() {
        #expect(DictationPresenter.preview(of: "").isEmpty)
        #expect(DictationPresenter.preview(of: "   \n\t ").isEmpty)
    }

    @Test("leaves text that is exactly at the limit unshortened")
    func textExactlyAtTheLimitIsKeptWhole() {
        let exact = String(repeating: "b", count: 40)
        let preview = DictationPresenter.preview(of: exact, limit: 40)
        #expect(preview == exact)
        #expect(!preview.hasSuffix("…"))

        // One character more is the first that gets shortened.
        #expect(DictationPresenter.preview(of: exact + "b", limit: 40).hasSuffix("…"))
    }
}

// MARK: - VoiceOver

@Suite("Spoken labels")
struct SpokenLabelTests {
    @Test("gives every state a label a screen reader can read aloud as a sentence")
    func everyLabelIsASpokenSentence() {
        for state in everyState {
            let dock = DictationPresenter.dock(for: state)

            for (label, symbol) in [(dock.accessibilityLabel, dock.symbolName)] {
                // An icon name read aloud is a leak of the drawing, not a description of what is happening.
                #expect(label != symbol, "\(state) reads out its icon name")
                #expect(
                    label.contains { $0.isWhitespace },
                    "\(state) label is a single word, not a sentence: \(label)")
                #expect(
                    sentenceEndings.contains { label.hasSuffix($0) },
                    "\(state) label is not a finished sentence: \(label)")
            }
        }
    }
}

@Suite("Small values the interface leans on")
struct HotkeyAndCueValueTests {
    /// A shortcut with no modifier would fire while the user typed an ordinary letter.
    @Test("treats a shortcut with no modifier as unusable")
    func requiresAModifier() {
        #expect(HotkeyBinding.optionSpace.isUsable)
        #expect(!HotkeyBinding(keyCode: 49, modifiers: []).isUsable)
        #expect(HotkeyBinding(keyCode: 1, modifiers: [.command, .shift]).isUsable)
    }

    @Test("ships bound to Option and Space")
    func defaultBinding() {
        #expect(HotkeyBinding.optionSpace.keyCode == 49)
        #expect(HotkeyBinding.optionSpace.modifiers == [.option])
    }

    @Test("round-trips a binding through Codable so a chosen shortcut survives relaunch")
    func bindingIsCodable() throws {
        let decoded = try JSONDecoder().decode(
            HotkeyBinding.self, from: JSONEncoder().encode(HotkeyBinding.optionSpace))
        #expect(decoded == .optionSpace)
    }

    /// Sounds off means nothing, without the caller needing to know.
    @Test("says nothing when the user has turned sounds off")
    func silentCueIsSilent() {
        let cue = SilentCue()
        cue.playStart()
        cue.playStop()
    }
}

@Suite("Being told nothing was heard")
struct HeardNothingTests {
    /// A dictation that produced nothing must say so, or the app looks broken.
    @Test("says so, softly, rather than saying nothing")
    func drawnAsANotice() {
        let shown = DictationPresenter.dock(
            for: .failed(DictationFailure(SpeechEngineError.nothingHeard)))

        #expect(shown.primaryLine == "Didn't catch that.")
        #expect(shown.symbolName != "exclamationmark.triangle", "nothing went wrong")
        #expect(shown.action == nil, "the remedy is to speak again, not to press something")
    }

    /// The soft treatment is for the severity, not for everything on the same channel.
    @Test("a genuine failure still carries a warning and its fix")
    func realFailuresAreStillAlarming() {
        let shown = DictationPresenter.dock(
            for: .failed(DictationFailure(PermissionError.microphoneDenied)))

        #expect(shown.symbolName == "exclamationmark.triangle")
        #expect(shown.action != nil)
    }
}

@Suite("How long the microphone has been open")
struct DictationElapsedTests {
    @Test("counts in minutes and seconds, padded")
    func format() {
        #expect(DictationPresenter.elapsed(.seconds(0)) == "0:00")
        #expect(DictationPresenter.elapsed(.seconds(4)) == "0:04")
        #expect(DictationPresenter.elapsed(.seconds(59)) == "0:59")
        #expect(DictationPresenter.elapsed(.seconds(60)) == "1:00")
        #expect(DictationPresenter.elapsed(.seconds(83)) == "1:23")
    }

    /// A button reading "0:04" an hour into a stuck recording would hide the thing worth noticing.
    @Test("keeps counting in minutes rather than rolling over at an hour")
    func pastAnHour() {
        #expect(DictationPresenter.elapsed(.seconds(3_600)) == "60:00")
        #expect(DictationPresenter.elapsed(.seconds(3_845)) == "64:05")
    }

    /// A clock cannot be run backwards by a system clock that moved under it.
    @Test("a negative duration reads as nothing yet")
    func negative() {
        #expect(DictationPresenter.elapsed(.seconds(-5)) == "0:00")
    }
}
