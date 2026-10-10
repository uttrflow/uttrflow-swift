// Pins every field the floating button draws for each case the presenter distinguishes.
import Foundation
import Testing

@testable import UttrflowCore
@testable import UttrflowPipeline

private let words = "Right, so the plan for tomorrow is to finish the drafting."

private let somewhereSecure = "The words are hidden because the field is secure."

private let microphoneDenied = DictationFailure(PermissionError.microphoneDenied)

@Suite("Each case the floating button draws, field by field")
struct DockPresentationCaseTests {
    @Test("idle rests on the microphone with nothing to say")
    func idle() {
        #expect(
            DictationPresenter.dock(for: .idle)
                == DockPresentation(
                    symbolName: "mic", primaryLine: nil, secondaryLine: nil, showsWaveform: false,
                    showsProgress: false, isRecording: false, action: nil,
                    accessibilityLabel: "Uttrflow. Ready to listen."))
    }

    @Test("recording lights the waveform and says how to finish, with the words heard so far")
    func recording() {
        #expect(
            DictationPresenter.dock(for: .recording, stopGesture: .clickAgain, heardSoFar: "alpha  beta")
                == DockPresentation(
                    symbolName: "mic.fill", primaryLine: "Click to finish", secondaryLine: "alpha beta",
                    showsWaveform: true, showsProgress: false, isRecording: true, action: nil,
                    accessibilityLabel: "Listening. Click the button again to finish."))
    }

    @Test("recording near its cap puts the time left on the second line and in the label")
    func recordingNearItsCap() {
        #expect(
            DictationPresenter.dock(
                for: .recording, advice: .approaching(remaining: .seconds(10)), heardSoFar: "alpha")
                == DockPresentation(
                    symbolName: "mic.fill", primaryLine: "Let go to finish", secondaryLine: "10 sec left",
                    showsWaveform: true, showsProgress: false, isRecording: true, action: nil,
                    accessibilityLabel: "Listening. Let go to finish. 10 sec left."))
    }

    @Test("a short wait shows the shared working line")
    func shortWait() {
        #expect(
            DictationPresenter.dock(for: .transcribing)
                == DockPresentation(
                    symbolName: "sparkles", primaryLine: "Tidying up…", secondaryLine: nil,
                    showsWaveform: false, showsProgress: true, isRecording: false, action: nil,
                    accessibilityLabel: "Working on what you said."))
    }

    @Test("a long wait names its stage and the seconds waited")
    func longWait() {
        #expect(
            DictationPresenter.dock(for: .inserting(into: nil), waited: .seconds(25))
                == DockPresentation(
                    symbolName: "sparkles", primaryLine: "Waiting for the app…", secondaryLine: "0:25",
                    showsWaveform: false, showsProgress: true, isRecording: false, action: nil,
                    accessibilityLabel: "Waiting for the app."))
    }

    @Test("a copy from a kept recording asks for ⌘V and offers nothing else")
    func copiedFromARecording() {
        let outcome = DictationOutcome(
            text: words, method: .clipboard, cleanedBy: .rules, fromRecording: true, missedPieces: 1)
        #expect(
            DictationPresenter.dock(for: .inserted(outcome))
                == DockPresentation(
                    symbolName: "doc.on.clipboard", primaryLine: "Copied — press ⌘V", secondaryLine: words,
                    showsWaveform: false, showsProgress: false, isRecording: false, action: nil,
                    accessibilityLabel: "Copied to the clipboard. Press Command V to paste it. "
                        + "\(MissedSpeech.sentence) \(words)"))
    }

    @Test("a copy made for want of Accessibility access offers the setting")
    func copiedForWantOfAccess() {
        let outcome = DictationOutcome(text: words, method: .clipboard, cleanedBy: .rules)
        #expect(
            DictationPresenter.dock(for: .inserted(outcome))
                == DockPresentation(
                    symbolName: "doc.on.clipboard", primaryLine: "Copied — press ⌘V", secondaryLine: words,
                    showsWaveform: false, showsProgress: false, isRecording: false,
                    action: .openSystemSettings(.accessibility),
                    accessibilityLabel: "Copied to the clipboard, not typed. Press Command V to paste it. "
                        + "Uttrflow needs Accessibility access to type for you. \(words)"))
    }

    @Test("an unconfirmed paste says where the words still are")
    func unconfirmed() {
        let outcome = DictationOutcome(
            text: words, method: .pasteboard, cleanedBy: .rules, arrival: .unconfirmed,
            intoSecureField: true)
        #expect(
            DictationPresenter.dock(for: .inserted(outcome))
                == DockPresentation(
                    symbolName: "questionmark.circle", primaryLine: "Inserted — not confirmed",
                    secondaryLine: "Still on the clipboard — press ⌘V if it is missing",
                    showsWaveform: false, showsProgress: false, isRecording: false, action: nil,
                    accessibilityLabel: "Inserted, but not confirmed. The words are still on the clipboard, "
                        + "so press Command V if they are missing. \(somewhereSecure)"))
    }

    @Test("an insertion missing part of the speech says so instead of ticking")
    func missingSpeech() {
        let outcome = DictationOutcome(
            text: words, method: .accessibility, cleanedBy: .rules, missedPieces: 2)
        #expect(
            DictationPresenter.dock(for: .inserted(outcome))
                == DockPresentation(
                    symbolName: "exclamationmark.circle", primaryLine: MissedSpeech.line,
                    secondaryLine: MissedSpeech.detail, showsWaveform: false, showsProgress: false,
                    isRecording: false, action: nil,
                    accessibilityLabel: "Inserted. \(MissedSpeech.sentence) \(words)"))
    }

    @Test("a plain insertion ticks and withholds words from a secure field")
    func plainInsertion() {
        let outcome = DictationOutcome(
            text: words, method: .accessibility, cleanedBy: .rules, intoSecureField: true)
        #expect(
            DictationPresenter.dock(for: .inserted(outcome))
                == DockPresentation(
                    symbolName: "checkmark", primaryLine: "Inserted", secondaryLine: nil,
                    showsWaveform: false, showsProgress: false, isRecording: false, action: nil,
                    accessibilityLabel: "Inserted: \(somewhereSecure)"))
    }

    @Test("a discard with nothing kept says nothing was typed")
    func discardedWithNothingKept() {
        let discard = DictationDiscard(spokenFor: .seconds(3), keptRecording: nil)
        #expect(
            DictationPresenter.dock(for: .discarded(discard))
                == DockPresentation(
                    symbolName: "trash", primaryLine: "Discarded", secondaryLine: "Nothing was typed",
                    showsWaveform: false, showsProgress: false, isRecording: false, action: nil,
                    accessibilityLabel: "Discarded. Nothing was typed."))
    }

    @Test("a discard with a kept recording offers to restore it")
    func discardedWithARecordingKept() {
        let discard = DictationDiscard(spokenFor: .seconds(3), keptRecording: UUID())
        #expect(
            DictationPresenter.dock(for: .discarded(discard))
                == DockPresentation(
                    symbolName: "trash", primaryLine: "Discarded", secondaryLine: "Restore within a minute",
                    showsWaveform: false, showsProgress: false, isRecording: false,
                    action: .restoreRecording,
                    accessibilityLabel: "Discarded. Nothing was typed. Restore within a minute."))
    }

    @Test("a dictation tried while the model loads waits on an hourglass")
    func stillLoading() {
        #expect(
            DictationPresenter.dock(for: .failed(.stillLoading))
                == DockPresentation(
                    symbolName: "hourglass", primaryLine: "Speech model still loading…", secondaryLine: nil,
                    showsWaveform: false, showsProgress: false, isRecording: false, action: nil,
                    accessibilityLabel: "Speech model still loading."))
    }

    @Test("a failure that heard nothing is drawn softly")
    func informationalFailure() {
        let failure = DictationFailure(SpeechEngineError.nothingHeard)
        #expect(
            DictationPresenter.dock(for: .failed(failure))
                == DockPresentation(
                    symbolName: "waveform.slash", primaryLine: failure.message, secondaryLine: nil,
                    showsWaveform: false, showsProgress: false, isRecording: false, action: failure.recovery,
                    accessibilityLabel: failure.message))
    }

    @Test("a failure with words keeps a glance at them and its own recovery")
    func failureWithWords() {
        let failure = DictationFailure(
            message: "The text could not be typed.", recovery: .pasteManually, severity: .degraded,
            transcript: words)
        #expect(
            DictationPresenter.dock(for: .failed(failure))
                == DockPresentation(
                    symbolName: "exclamationmark.triangle", primaryLine: "The text could not be typed.",
                    secondaryLine: words, showsWaveform: false, showsProgress: false, isRecording: false,
                    action: .pasteManually, accessibilityLabel: "The text could not be typed."))
    }

    @Test("resting during a download fills a ring to the share done")
    func restingWhileDownloading() {
        #expect(
            DictationPresenter.dock(for: .idle, speechModel: nil, download: 0.42)
                == DockPresentation(
                    symbolName: "arrow.down.circle", primaryLine: "Setting up", secondaryLine: "42%",
                    showsWaveform: false, showsProgress: false, isRecording: false, action: nil,
                    accessibilityLabel: "Setting up. Downloading the speech model, 42 percent.",
                    setup: .downloading(0.42)))
    }

    @Test("resting during a short load spins on an hourglass")
    func restingWhileLoading() {
        let load = SpeechModelLoad.loading(elapsed: .seconds(2))
        #expect(
            DictationPresenter.dock(for: .idle, speechModel: load)
                == DockPresentation(
                    symbolName: "hourglass", primaryLine: "Getting ready…", secondaryLine: nil,
                    showsWaveform: false, showsProgress: false, isRecording: false, action: nil,
                    accessibilityLabel: load.accessibilityLabel, setup: .loading(nil)))
    }

    @Test("resting after a failed load offers Retry")
    func restingAfterAFailedLoad() {
        #expect(
            DictationPresenter.dock(for: .idle, speechModel: .failed)
                == DockPresentation(
                    symbolName: "exclamationmark.triangle", primaryLine: "Speech model didn’t load",
                    secondaryLine: "Dictation can’t start without it", showsWaveform: false,
                    showsProgress: false, isRecording: false, action: .retry,
                    accessibilityLabel:
                        "The speech model didn’t load. Dictation can’t start without it. Try loading it again.",
                    setup: .failed))
    }

    @Test("resting on a damaged model offers a fresh download")
    func restingOnABrokenModel() {
        #expect(
            DictationPresenter.dock(for: .idle, speechModel: .broken)
                == DockPresentation(
                    symbolName: "exclamationmark.triangle", primaryLine: "Speech model is damaged",
                    secondaryLine: "Dictation can’t start without it", showsWaveform: false,
                    showsProgress: false, isRecording: false, action: .downloadSpeechModel,
                    accessibilityLabel: SpeechModelLoad.broken.accessibilityLabel, setup: .broken))
    }

    @Test("resting with no model on disk offers the download")
    func restingWithNoModel() {
        #expect(
            DictationPresenter.dock(for: .idle, speechModel: .missing)
                == DockPresentation(
                    symbolName: "exclamationmark.triangle", primaryLine: "Speech model needed",
                    secondaryLine: "Dictation can’t start without it", showsWaveform: false,
                    showsProgress: false, isRecording: false, action: .downloadSpeechModel,
                    accessibilityLabel: SpeechModelLoad.missing.accessibilityLabel, setup: .missing))
    }

    @Test("a failure while the model is unusable keeps its line and button and says why")
    func failureWhileTheModelIsUnusable() {
        #expect(
            DictationPresenter.dock(for: .failed(microphoneDenied), speechModel: .failed)
                == DockPresentation(
                    symbolName: "exclamationmark.triangle", primaryLine: microphoneDenied.message,
                    secondaryLine: "Dictation can’t start without it", showsWaveform: false,
                    showsProgress: false, isRecording: false, action: microphoneDenied.recovery,
                    accessibilityLabel:
                        "\(microphoneDenied.message) \(SpeechModelLoad.failed.accessibilityLabel)"))
    }

    @Test("a dictation tried during the load reads only the load")
    func stillLoadingDuringTheLoad() {
        let load = SpeechModelLoad.loading(elapsed: .seconds(2))
        #expect(
            DictationPresenter.dock(for: .failed(.stillLoading), speechModel: load)
                == DockPresentation(
                    symbolName: "hourglass", primaryLine: "Speech model still loading…",
                    secondaryLine: "Dictation starts once it’s ready", showsWaveform: false,
                    showsProgress: false, isRecording: false, action: nil,
                    accessibilityLabel: load.accessibilityLabel))
    }

    @Test("a notice about something else draws words and nothing that moves")
    func passingNotice() {
        #expect(
            DictationPresenter.dock(
                notice: "doc.on.clipboard", primaryLine: "Copied", secondaryLine: "From history",
                accessibilityLabel: "Copied from history.")
                == DockPresentation(
                    symbolName: "doc.on.clipboard", primaryLine: "Copied", secondaryLine: "From history",
                    showsWaveform: false, showsProgress: false, isRecording: false, action: nil,
                    accessibilityLabel: "Copied from history."))
    }
}
