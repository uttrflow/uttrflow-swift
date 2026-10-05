// Tests what VoiceOver is told when a dictation starts, lands or fails.
import Foundation
import Testing

@testable import UttrflowCore
@testable import UttrflowPipeline

@Suite("Dictation announcements")
struct DictationAnnouncementTests {
    private static let words = "Right, so the plan for tomorrow is to finish the drafting."

    @Test("announces the cap warning without interrupting VoiceOver")
    func capWarningIsNonUrgent() {
        #expect(
            DictationPresenter.warningAnnouncement(for: .approaching(remaining: .seconds(60)))
                == DictationAnnouncement(text: "Dictation ends soon. 1 min left.", isUrgent: false))
        #expect(DictationPresenter.warningAnnouncement(for: .keepGoing) == nil)
        #expect(DictationPresenter.warningAnnouncement(for: .finishNow) == nil)
    }

    @Test("a near-miss tap is announced, not discarded in silence")
    func nearMissTap() {
        #expect(
            DictationPresenter.nearMissTapAnnouncement
                == DictationAnnouncement(text: "Tap too slow, double-tap faster", isUrgent: false))
    }

    @Test("says nothing while resting or waiting, since the cues already cover the wait")
    func quietStates() {
        for state in [DictationState.idle, .transcribing, .tidying, .inserting(into: nil)] {
            #expect(DictationPresenter.announcement(for: state) == nil, "\(state)")
        }
    }

    @Test("says the microphone is listening when a recording starts")
    func recording() {
        #expect(
            DictationPresenter.announcement(for: .recording)
                == DictationAnnouncement(text: "Listening.", isUrgent: false))
    }

    @Test("says the words were inserted, with a glance at them")
    func inserted() {
        let outcome = DictationOutcome(text: Self.words, method: .accessibility, cleanedBy: .rules)
        let said = DictationPresenter.announcement(for: .inserted(outcome))
        #expect(said == DictationAnnouncement(text: "Inserted: \(Self.words)", isUrgent: false))
    }

    @Test("never reads aloud the words typed into a secure field")
    func insertedIntoSecureField() throws {
        let outcome = DictationOutcome(
            text: Self.words, method: .accessibility, cleanedBy: .rules, intoSecureField: true)
        let said = try #require(DictationPresenter.announcement(for: .inserted(outcome)))
        #expect(!said.text.contains("drafting"))
        #expect(said.text == "Inserted: The words are hidden because the field is secure.")
    }

    @Test("never reads aloud a secure field's words when they were copied instead")
    func copiedFromSecureField() throws {
        let outcome = DictationOutcome(
            text: Self.words, method: .clipboard, cleanedBy: .rules, fromRecording: true,
            intoSecureField: true)
        let said = try #require(DictationPresenter.announcement(for: .inserted(outcome)))
        #expect(!said.text.contains("drafting"))
    }

    @Test("never reads a long dictation back in full")
    func longDictationIsShortened() throws {
        let long = Array(repeating: Self.words, count: 40).joined(separator: " ")
        let outcome = DictationOutcome(text: long, method: .accessibility, cleanedBy: .rules)
        let said = try #require(DictationPresenter.announcement(for: .inserted(outcome)))
        #expect(said.text.count < 100)
        #expect(said.text.hasSuffix("…"))
    }

    @Test("says a recording's words were copied rather than typed, and how to paste them")
    func copiedFromRecording() throws {
        let outcome = DictationOutcome(
            text: Self.words, method: .clipboard, cleanedBy: .rules, fromRecording: true)
        let said = try #require(DictationPresenter.announcement(for: .inserted(outcome)))
        #expect(said.text.hasPrefix("Copied to the clipboard. Press Command V to paste it."))
        #expect(said.text.hasSuffix(Self.words))
        #expect(!said.isUrgent)
    }

    @Test("says urgently that nothing was typed when Accessibility access is missing")
    func copiedForWantOfAccess() throws {
        let outcome = DictationOutcome(text: Self.words, method: .clipboard, cleanedBy: .rules)
        let said = try #require(DictationPresenter.announcement(for: .inserted(outcome)))
        #expect(said.text.contains("not typed"))
        #expect(said.text.contains("Accessibility access"))
        #expect(said.isUrgent)
    }

    @Test("says an unconfirmed paste may be missing and where the words still are")
    func unconfirmed() throws {
        let outcome = DictationOutcome(
            text: Self.words, method: .accessibility, cleanedBy: .rules, arrival: .unconfirmed)
        let said = try #require(DictationPresenter.announcement(for: .inserted(outcome)))
        #expect(said.text.hasPrefix("Inserted, but not confirmed."))
        #expect(!said.isUrgent)
    }

    @Test("says every recovery urgently and tells where to reach it")
    func failures() throws {
        let failures: [(DictationFailure, String?)] = [
            (
                DictationFailure(
                    message: PermissionError.microphoneDenied.userMessage,
                    recovery: .openSystemSettings(.microphone), severity: .blocking),
                "Open Settings from the Uttrflow menu."
            ),
            (
                DictationFailure(message: "Again.", recovery: .retry, severity: .recoverable),
                "Choose Try Again from the Uttrflow menu."
            ),
            (
                DictationFailure(
                    message: "Model unavailable.", recovery: .downloadSpeechModel,
                    severity: .blocking), "Choose Download from the Uttrflow menu."
            ),
            (
                DictationFailure(
                    message: "Copied.", recovery: .pasteManually, severity: .degraded),
                "The text is on your clipboard. Press Command V to paste it."
            ),
            (
                DictationFailure(
                    message: "Not delivered.", recovery: .showHistory,
                    severity: .degraded), "Open History from the Uttrflow menu to find your words."
            ),
            (
                DictationFailure(
                    message: "Transcription failed.", recovery: .retryFromRecording,
                    severity: .recoverable),
                "Open History from the Uttrflow menu, then choose Retry on the recording."
            ),
            (DictationFailure.stillLoading, nil),
        ]
        for (failure, instruction) in failures {
            let said = try #require(DictationPresenter.announcement(for: .failed(failure)))
            #expect(said.isUrgent)
            let message = failure.message.filter { $0 != "…" }
            #expect(said.text == instruction.map { "\(message) \($0)" } ?? message)
            #expect(!said.text.isEmpty)
        }
    }
}
