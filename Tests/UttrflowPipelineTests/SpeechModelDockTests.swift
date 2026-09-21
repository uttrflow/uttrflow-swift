// Tests what the floating button shows while the speech model loads, and after it failed to.
import Testing

@testable import UttrflowCore
@testable import UttrflowPipeline

@Suite("The floating button during the speech model's load")
struct SpeechModelDockTests {
    @Test("resting during a load shows the load, with no minutes in its first seconds")
    func restingShowsTheLoad() {
        let dock = DictationPresenter.dock(for: .idle, speechModel: .loading(elapsed: .seconds(2)))

        #expect(dock.symbolName == "hourglass")
        #expect(dock.primaryLine == "Loading speech model…")
        #expect(dock.secondaryLine == "Dictation starts once it’s ready")
        #expect(dock.action == nil)
        #expect(!dock.showsProgress, "nothing reports how far a load has got, so nothing pretends to")
        #expect(!dock.accessibilityLabel.contains("minutes"))
    }

    @Test("gives the minutes once the load has run long enough to need them")
    func longLoadGivesTheEstimate() {
        let dock = DictationPresenter.dock(for: .idle, speechModel: .loading(elapsed: .seconds(30)))

        #expect(dock.secondaryLine == "First load after restart: about 2–3 min")
        #expect(dock.accessibilityLabel.contains("2 to 3 minutes"))
    }

    @Test("resting after a failed load says so and offers a fresh download")
    func failedLoadOffersDownload() {
        let dock = DictationPresenter.dock(for: .idle, speechModel: .failed)

        #expect(dock.primaryLine == "Speech model didn’t load")
        #expect(dock.action == .downloadSpeechModel)
        #expect(dock.symbolName == "exclamationmark.triangle")
    }

    /// Setup fetches a missing model, and the button stays the resting grip while it does.
    @Test("resting with no model on disk draws the resting button, not a warning")
    func missingModelLeavesTheButtonAlone() {
        #expect(
            DictationPresenter.dock(for: .idle, speechModel: .missing)
                == DictationPresenter.dock(for: .idle))
    }

    @Test("a refused attempt is drawn wide, with its words and why")
    func refusalIsDrawnWithWords() {
        let dock = DictationPresenter.dock(
            for: .failed(.stillLoading), speechModel: .loading(elapsed: .seconds(40)))

        #expect(dock.symbolName == "hourglass", "the quiet disc would drop the sentence")
        #expect(dock.primaryLine == "Speech model still loading…")
        #expect(dock.secondaryLine == "First load after restart: about 2–3 min")
        #expect(dock.accessibilityLabel.hasPrefix("Loading the speech model."))
    }

    @Test("the refusal still reads without the load beside it")
    func refusalAlone() {
        let dock = DictationPresenter.dock(for: .failed(.stillLoading))

        #expect(dock.primaryLine == "Speech model still loading…")
        #expect(dock.accessibilityLabel == "Speech model still loading.")
    }

    @Test("a failure with words to salvage keeps its own second line")
    func salvagedWordsKeepTheirLine() {
        let failure = DictationFailure(
            message: "Couldn’t tidy that.", recovery: .pasteManually, severity: .degraded,
            transcript: "The words.")
        let dock = DictationPresenter.dock(for: .failed(failure), speechModel: .failed)

        #expect(dock == DictationPresenter.dock(for: .failed(failure)))
    }

    @Test("another failure during the load keeps its button and gains the reason")
    func otherFailureGainsTheReason() {
        let failure = DictationFailure(SpeechEngineError.modelLoadFailed(description: "fixture"))
        let dock = DictationPresenter.dock(for: .failed(failure), speechModel: .failed)

        #expect(dock.primaryLine == failure.message)
        #expect(dock.action == .retry)
        #expect(dock.secondaryLine == "Dictation can’t start without it")
        #expect(dock.accessibilityLabel.hasSuffix("Download it again to repair it."))
    }

    @Test(
        "once loaded, every state is drawn exactly as before",
        arguments: [
            DictationState.idle, .recording, .transcribing, .tidying, .inserting,
            .inserted(DictationOutcome(text: "Done.", method: .accessibility, cleanedBy: .rules)),
        ])
    func loadedChangesNothing(state: DictationState) {
        #expect(DictationPresenter.dock(for: state, speechModel: nil) == DictationPresenter.dock(for: state))
    }

    @Test("a dictation under way is never covered by the load")
    func busyStatesAreNotCovered() {
        let load = SpeechModelLoad.loading(elapsed: .seconds(60))
        #expect(DictationPresenter.dock(for: .recording, speechModel: load).isRecording)
        #expect(DictationPresenter.dock(for: .tidying, speechModel: load).showsProgress)
    }
}
