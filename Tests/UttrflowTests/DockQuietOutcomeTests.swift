// Tests that the floating button's quiet outcomes say what happened without the pointer over them.

import AppKit
import UttrflowCore
import UttrflowPipeline
import Testing

@testable import Uttrflow

@MainActor
@Suite("The floating button's quiet outcomes at rest")
struct DockQuietOutcomeTests {
    private static let copied = DictationOutcome(
        text: "see you at noon", method: .clipboard, cleanedBy: .rules)
    private static let typed = DictationOutcome(
        text: "see you at noon", method: .accessibility, cleanedBy: .rules)

    @Test("says the words were copied, not typed, when Accessibility blocked typing")
    func copiedSaysSo() {
        let dock = DictationPresenter.dock(for: .inserted(Self.copied))

        #expect(DockView.restingWords(for: dock) == "Copied, not typed")
    }

    @Test("says the words were copied when a kept recording was copied")
    func copiedFromRecordingSaysSo() {
        let outcome = DictationOutcome(
            text: "see you at noon", method: .clipboard, cleanedBy: .rules, fromRecording: true)

        #expect(
            DockView.restingWords(for: DictationPresenter.dock(for: .inserted(outcome)))
                == "Copied, not typed")
    }

    @Test("says nothing was heard in words")
    func nothingHeardSaysSo() {
        let dock = DictationPresenter.dock(
            for: .failed(DictationFailure(SpeechEngineError.nothingHeard)))

        #expect(DockView.restingWords(for: dock) == "Didn't catch that.")
    }

    @Test("says a hold was too short and how to fix it")
    func tooShortSaysSo() {
        let dock = DictationPresenter.dock(
            for: .failed(DictationFailure(SpeechEngineError.audioTooShort)))

        #expect(DockView.restingWords(for: dock) == SpeechEngineError.audioTooShort.userMessage)
        #expect(dock.action == nil, "a press starts the next dictation rather than retrying a tap")
    }

    @Test("draws a plain insertion as the tick alone")
    func insertionHasNoWords() {
        #expect(DockView.restingWords(for: DictationPresenter.dock(for: .inserted(Self.typed))) == nil)
    }

    /// Measured at the view's font and width against one line of the same font, so nothing is drawn.
    @Test("fits each quiet sentence in the pill's two lines")
    func quietWordsFit() {
        let font = NSFont.systemFont(ofSize: DockMetrics.footnoteSize + 1)
        func height(_ text: String) -> CGFloat {
            (text as NSString).boundingRect(
                with: NSSize(
                    width: DockMetrics.quietTextMaxWidth - 2, height: .greatestFiniteMagnitude),
                options: [.usesLineFragmentOrigin], attributes: [.font: font]
            ).height
        }
        for error in [SpeechEngineError.nothingHeard, .audioTooShort] {
            let lines = Int((height(error.userMessage) / height("Ag")).rounded())
            #expect(lines <= 2, "\(error.userMessage) needs \(lines) lines")
        }
    }

    @Test("keeps copied words up as long as a failure, since they still have to be pasted")
    func copiedLingersLikeAFailure() {
        #expect(AppDelegate.linger(after: .inserted(Self.copied)) == AppDelegate.failureLingers)
        #expect(AppDelegate.linger(after: .inserted(Self.typed)) == AppDelegate.successLingers)
    }

    @Test("clears a quiet failure soon and a blocking one later, and never an unfinished state")
    func failuresLinger() {
        #expect(
            AppDelegate.linger(after: .failed(DictationFailure(SpeechEngineError.nothingHeard)))
                == AppDelegate.successLingers)
        #expect(
            AppDelegate.linger(after: .failed(DictationFailure(PermissionError.microphoneDenied)))
                == AppDelegate.failureLingers)
        #expect(AppDelegate.linger(after: .recording) == nil)
    }
}
