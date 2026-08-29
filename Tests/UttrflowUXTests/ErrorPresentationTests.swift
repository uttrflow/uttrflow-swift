import Testing

@testable import UttrflowCore
@testable import UttrflowUX

/// Every failure the product can raise.
///
/// This walk is the point of the file: a failure with no user-facing story should not
/// be able to ship. The list itself used to be written out here by hand, and a second
/// copy in ``UttrflowCoreTests`` fell one enum behind it — so the list now comes from
/// ``FailureCatalogue``, which both targets share and whose per-enum chains the
/// compiler keeps complete.
private let everyFailure = FailureCatalogue.everyFailure

@Suite("Presenting any failure")
struct ErrorPresentationTests {
    /// The deliverable: every failure in the product, walked through the one presenter,
    /// producing something a user could act on.
    @Test("gives every failure a usable message")
    func everyFailureHasAMessage() {
        for failure in everyFailure {
            let shown = FailurePresenter.present(failure)
            #expect(!shown.headline.isEmpty, "\(failure) has no headline")
            // The design gives the headline one line of a 396-point banner. 96 is the
            // ceiling the product currently squeezes under; see ``longestHeadline``.
            #expect(
                shown.headline.count <= 96,
                "\(failure) opens with a headline too long to read: \(shown.headline)")
            #expect(
                shown.headline.hasSuffix(".") || shown.headline.hasSuffix("!"),
                "\(failure) does not open with a sentence: \(shown.headline)")
            #expect(shown.detail?.isEmpty != true, "\(failure) has an empty second line")
            // The whole message must survive the split, or the presenter is losing words
            // the error went to the trouble of writing.
            let rebuilt = shown.detail.map { "\(shown.headline) \($0)" } ?? shown.headline
            #expect(rebuilt == failure.userMessage, "\(failure) lost words in the split")
        }
    }

    @Test("gives every failure a sensible next step")
    func everyFailureHasSomewhereToGo() {
        for failure in everyFailure {
            let shown = FailurePresenter.present(failure)
            #expect(!shown.symbolName.isEmpty, "\(failure) has no badge")
            // An action, when there is one, must be a button the user can read and must
            // still be the action the error itself asked for.
            if let action = shown.action {
                #expect(!action.title.isEmpty, "\(failure) offers a nameless button")
                #expect(action.recovery == failure.recovery, "\(failure) offers the wrong fix")
            } else {
                #expect(failure.recovery == nil, "\(failure) dropped its recovery action")
            }
            // A failure nobody can act past must stay on screen until its cause is gone;
            // the menu bar is the only surface that does not dismiss itself.
            //
            // This used to say something stronger and wrong: that a failure offering no
            // action must be blocking, on the reasoning that nothing to do means nothing
            // to dictate past. `HistoryStoreError.couldNotWrite` is the counterexample —
            // there is genuinely nothing the user can do about a disk refusing a write,
            // and they can carry on dictating perfectly well, because the words went
            // where they were meant to go and only the note of it was lost.
            if shown.severity == .blocking {
                #expect(shown.placement == .menuBar, "\(failure) blocks but can dismiss itself")
            }
        }
    }

    /// The presenter's one job with severity is to pass it on. It used to work severity
    /// out from the recovery action, which cannot be done: these two ask for the very
    /// same fix and cost the user completely different amounts.
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

    /// §19: whatever fails, the user's words stay reachable. A failure that costs the
    /// user their dictation has to be the kind that waits for them in the menu bar.
    @Test("puts a failure where the user will still find it")
    func placementFollowsSeverity() {
        for failure in everyFailure {
            let shown = FailurePresenter.present(failure)
            let expected: FailurePlacement = shown.severity == .blocking ? .menuBar : .floatingButton
            #expect(shown.placement == expected, "\(failure) is shown in the wrong place")
        }
    }

    /// §16: the user must never learn which engine ran. The presenter adds words of its
    /// own — button titles and symbol names — so the guard is repeated on its output.
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

    /// The worst headline the product still has, written down rather than left to be
    /// noticed on screen.
    ///
    /// A message with no sentence break becomes a headline with nothing beneath it, and
    /// the design gives the headline one line. ``HotkeyError/shortcutUnavailable`` used
    /// to hold this record at 92 characters and was split into two sentences; what is
    /// left is a policy-blocked microphone, which is one clause and cannot be split
    /// without inventing a second thought the error does not have. Recorded so that a
    /// rewrite making it worse cannot pass unnoticed.
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

    /// Both entry points must agree, or the pipeline's failures and the ones caught
    /// directly would be two different products.
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

    /// Three sentences is one more than the design has room for, so the tail stays
    /// together as the second line rather than being thrown away.
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

    /// Only a blocking notice waits in the menu bar. The other three are news about a
    /// dictation that is already over, and a notice that outlived it would be a warning
    /// about nothing.
    @Test("keeps only a blocking notice on an always-visible surface")
    func placementFollowsSeverityAlone() {
        for severity in FailureSeverity.allCases {
            let shown = FailurePresenter.present(
                message: "Something happened.", recovery: nil, severity: severity)
            #expect(shown.placement == (severity == .blocking ? .menuBar : .floatingButton))
        }
    }

    /// The badge is read before the sentence is, so it must name where the user is
    /// about to be sent rather than merely that something is wrong.
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

    /// Two presentations of the same failure are compared to decide whether the menu
    /// bar has anything new to draw, so they have to be the same value.
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
