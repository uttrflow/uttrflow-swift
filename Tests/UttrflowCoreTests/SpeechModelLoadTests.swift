// Tests the words every surface uses for the speech model's load, and when the minutes are said.
import Testing

@testable import UttrflowCore

@Suite("What is said while the speech model loads")
struct SpeechModelLoadTests {
    @Test(
        "a load in its first seconds claims no minutes, since a warm load is over in two",
        arguments: [Duration.zero, .seconds(2), .milliseconds(4_999)])
    func fastLoadClaimsNoMinutes(elapsed: Duration) {
        let load = SpeechModelLoad.loading(elapsed: elapsed)

        #expect(!load.showsEstimate)
        #expect(!load.message.contains("minute"))
        #expect(!load.detail.contains("min"))
        #expect(!load.accessibilityLabel.contains("minute"))
    }

    @Test(
        "a load that runs on gives the estimate, and says it is the first load after a restart",
        arguments: [Duration.seconds(5), .seconds(154)])
    func slowLoadGivesTheEstimate(elapsed: Duration) {
        let load = SpeechModelLoad.loading(elapsed: elapsed)

        #expect(load.showsEstimate)
        #expect(load.message.contains("first load after a restart can take about 2–3 minutes"))
        #expect(load.detail == "First load after restart: about 2–3 min")
    }

    @Test("says the speech model is loading, with nothing to press")
    func loadingCopy() {
        let load = SpeechModelLoad.loading(elapsed: .seconds(1))

        #expect(load.isLoading)
        #expect(load.title == "Loading the speech model…")
        #expect(load.message == "Dictation starts working as soon as it’s ready.")
        #expect(load.status == "Loading speech model")
        #expect(load.recovery == nil)
    }

    @Test("a failed load says so and offers a fresh download")
    func failedCopy() {
        let load = SpeechModelLoad.failed

        #expect(!load.isLoading)
        #expect(!load.showsEstimate)
        #expect(load.title == "The speech model didn’t load")
        #expect(load.line == "Speech model didn’t load")
        #expect(load.status == "Speech model didn’t load")
        #expect(load.recovery == .downloadSpeechModel)
        #expect(load.message.contains("Download it again"))
    }

    @Test("a missing model says it was never downloaded and offers the download")
    func missingCopy() {
        let load = SpeechModelLoad.missing

        #expect(!load.isLoading)
        #expect(!load.showsEstimate)
        #expect(load.title == "The speech model isn’t downloaded")
        #expect(load.line == "Speech model not downloaded")
        #expect(load.detail == "Dictation can’t start without it")
        #expect(load.status == "Speech model not downloaded")
        #expect(load.message == "Dictation can’t start without it. Download it to start dictating.")
        #expect(load.recovery == .downloadSpeechModel)
    }

    @Test("the spoken form carries no ellipsis and no dash a screen reader would skip")
    func spokenForm() {
        let label = SpeechModelLoad.loading(elapsed: .seconds(60)).accessibilityLabel

        #expect(!label.contains("…"))
        #expect(!label.contains("–"))
        #expect(label.hasPrefix("Loading the speech model. "))
        #expect(label.contains("about 2 to 3 minutes"))
    }
}
