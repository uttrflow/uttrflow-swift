// Tests for the failure presenter: every failure gets a message, a next step, a severity and a place.
import Testing

@testable import UttrflowCore
@testable import UttrflowUX

/// Every failure the product can raise, from the catalogue both test targets share.
private let everyFailure = FailureCatalogue.everyFailure

@Suite("Presenting any failure")
struct ErrorPresentationTests {
    /// Every failure, walked through the one presenter, producing something a user can act on.
    @Test("gives every failure a usable message")
    func everyFailureHasAMessage() {
        for failure in everyFailure {
            let shown = FailurePresenter.present(failure)
            #expect(!shown.headline.isEmpty, "\(failure) has no headline")
            // One line of a 396-point banner; 96 is the ceiling the product squeezes under.
            #expect(
                shown.headline.count <= 96,
                "\(failure) opens with a headline too long to read: \(shown.headline)")
            #expect(
                shown.headline.hasSuffix(".") || shown.headline.hasSuffix("!"),
                "\(failure) does not open with a sentence: \(shown.headline)")
            #expect(shown.detail?.isEmpty != true, "\(failure) has an empty second line")
            // The whole message must survive the split, or the presenter is losing words.
            let rebuilt = shown.detail.map { "\(shown.headline) \($0)" } ?? shown.headline
            #expect(rebuilt == failure.userMessage, "\(failure) lost words in the split")
        }
    }

    @Test("gives every failure a sensible next step")
    func everyFailureHasSomewhereToGo() {
        for failure in everyFailure {
            let shown = FailurePresenter.present(failure)
            #expect(!shown.symbolName.isEmpty, "\(failure) has no badge")
            // An action, when there is one, must be readable and must be the one the error asked for.
            if let action = shown.action {
                #expect(!action.title.isEmpty, "\(failure) offers a nameless button")
                #expect(action.recovery == failure.recovery, "\(failure) offers the wrong fix")
            } else {
                #expect(failure.recovery == nil, "\(failure) dropped its recovery action")
            }
            // A blocking failure stays on the menu bar, the only surface that does not dismiss itself.
            if shown.severity == .blocking {
                #expect(shown.placement == .menuBar, "\(failure) blocks but can dismiss itself")
            }
        }
    }

    /// Severity is passed on, never inferred: these two ask for the same fix and cost different amounts.
    @Test("takes each failure's own severity rather than inferring one")
    func severityComesFromTheFailure() {
        for failure in everyFailure {
            #expect(
                FailurePresenter.present(failure).severity == failure.severity,
                "\(failure) was shown at a severity it did not declare")
        }

        let blocked = FailurePresenter.present(HotkeyError.observationNotPermitted)
        let degraded = FailurePresenter.present(PermissionError.accessibilityNotTrusted)
        #expect(blocked.action == degraded.action, "the two offer the same fix")
        #expect(blocked.severity == .blocking)
        #expect(degraded.severity == .degraded)
        #expect(blocked.placement == .menuBar)
        #expect(degraded.placement == .floatingButton)
    }

    /// §19: whatever fails, the user's words stay reachable, so a costly failure waits in the menu bar.
    @Test("puts a failure where the user will still find it")
    func placementFollowsSeverity() {
        for failure in everyFailure {
            let shown = FailurePresenter.present(failure)
            let expected: FailurePlacement = shown.severity == .blocking ? .menuBar : .floatingButton
            #expect(shown.placement == expected, "\(failure) is shown in the wrong place")
        }
    }

    /// §16: the presenter adds words of its own, so the no-engine-names guard is repeated on its output.
    @Test("never leaks an implementation name into anything shown")
    func neverNamesAnEngine() {
        let forbidden = [
            "whisper", "foundation model", "llm", "coreml", "mlx", "transformer", "inference",
        ]
        for failure in everyFailure {
            let shown = FailurePresenter.present(failure)
            let words = [shown.headline, shown.detail ?? "", shown.action?.title ?? ""]
                .joined(separator: " ")
                .lowercased()
            for term in forbidden {
                #expect(!words.contains(term), "\(failure) leaks '\(term)'")
            }
        }
    }

    /// The worst headline the product has, recorded so a rewrite making it worse cannot pass unnoticed.
    @Test("records the longest headline the product still has")
    func longestHeadline() {
        let worst =
            everyFailure
            .map { FailurePresenter.present($0) }
            .max { $0.headline.count < $1.headline.count }
        #expect(worst?.headline == PermissionError.microphoneRestricted.userMessage)
        #expect(worst?.detail == nil)
        #expect(worst?.headline.count == 75)
    }

    // MARK: - The rules, stated one at a time

    /// Both entry points must agree, or the pipeline's failures and the caught ones would be two products.
    @Test("presents a reduced failure exactly as it presents the error")
    func reducedFailureMatches() {
        let error = TextInsertionError.insertionRejected(description: "read-only field")
        let direct = FailurePresenter.present(error)
        let reduced = FailurePresenter.present(
            message: error.userMessage, recovery: error.recovery, severity: error.severity)
        #expect(direct == reduced)
    }

    @Test("splits a two-sentence message into a headline and a detail")
    func splitsOnTheSentenceBreak() {
        let shown = FailurePresenter.present(
            message: "No microphone was found. Connect one and try again.", recovery: nil,
            severity: .blocking)
        #expect(shown.headline == "No microphone was found.")
        #expect(shown.detail == "Connect one and try again.")
    }

    @Test("leaves a one-sentence message with nothing underneath it")
    func keepsASingleSentenceWhole() {
        let shown = FailurePresenter.present(
            message: "Recording is already in progress.", recovery: .retry, severity: .recoverable)
        #expect(shown.headline == "Recording is already in progress.")
        #expect(shown.detail == nil)
    }

    /// Three sentences is one more than the design has room for, so the tail stays together as line two.
    @Test("keeps everything after the first sentence together")
    func keepsTheTailTogether() {
        let shown = FailurePresenter.present(
            message: "One. Two. Three.", recovery: nil, severity: .blocking)
        #expect(shown.headline == "One.")
        #expect(shown.detail == "Two. Three.")
    }

    @Test("does not leave an empty second line behind a trailing space")
    func ignoresATrailingBreak() {
        let shown = FailurePresenter.present(
            message: "Nothing follows this. ", recovery: nil, severity: .blocking)
        #expect(shown.headline == "Nothing follows this.")
        #expect(shown.detail == nil)
    }

    /// Only a blocking notice waits in the menu bar; the others are news about a dictation already over.
    @Test("keeps only a blocking notice on an always-visible surface")
    func placementFollowsSeverityAlone() {
        for severity in FailureSeverity.allCases {
            let shown = FailurePresenter.present(
                message: "Something happened.", recovery: nil, severity: severity)
            #expect(shown.placement == (severity == .blocking ? .menuBar : .floatingButton))
        }
    }

    /// The badge is read before the sentence, so it names where the user is about to be sent.
    @Test("badges a failure with the thing that needs attention")
    func badgesNameTheirSubject() {
        #expect(FailurePresenter.symbolName(for: .openSystemSettings(.microphone)) == "mic.slash")
        #expect(FailurePresenter.symbolName(for: .openSystemSettings(.accessibility)) == "accessibility")
        #expect(FailurePresenter.symbolName(for: .openSystemSettings(.appleIntelligence)) == "sparkles")
        #expect(FailurePresenter.symbolName(for: .downloadSpeechModel) == "arrow.down.circle")
        #expect(FailurePresenter.symbolName(for: .retry) == "arrow.clockwise")
        #expect(FailurePresenter.symbolName(for: .pasteManually) == "doc.on.clipboard")
        #expect(
            FailurePresenter.symbolName(for: .showRecentDictations)
                == "menubar.arrow.up.rectangle")
        #expect(FailurePresenter.symbolName(for: nil) == "exclamationmark.triangle")
    }

    /// A button that says "OK" tells the user nothing about what it is going to do.
    @Test("names every button after what it will do")
    func buttonsSayWhatTheyDo() {
        #expect(FailurePresenter.title(for: .openSystemSettings(.microphone)) == "Open System Settings")
        #expect(FailurePresenter.title(for: .retry) == "Try Again")
        #expect(FailurePresenter.title(for: .downloadSpeechModel) == "Finish Setup")
        #expect(FailurePresenter.title(for: .pasteManually) == "Paste")
        #expect(FailurePresenter.title(for: .showRecentDictations) == "Show Recent")
    }

    /// Two presentations of the same failure are compared to decide whether the menu bar redraws.
    @Test("presents the same failure as the same thing twice")
    func presentationsAreValues() {
        #expect(
            FailurePresenter.present(PermissionError.microphoneDenied)
                == FailurePresenter.present(PermissionError.microphoneDenied))
        #expect(
            FailurePresenter.present(PermissionError.microphoneDenied)
                != FailurePresenter.present(PermissionError.accessibilityNotTrusted))
    }
}
