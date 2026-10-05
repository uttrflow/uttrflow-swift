// Tests for how a dictation's state reads on onboarding's last page.
import Testing

@testable import Uttrflow
@testable import UttrflowPipeline
@testable import UttrflowUX

@Suite("A dictation on onboarding's last page")
struct OnboardingTrialTests {
    @Test("listens while recording, and shows the words that came back")
    func recordingThenWords() {
        #expect(OnboardingWindowController.trial(for: .recording) == .listening)
        #expect(OnboardingWindowController.trial(for: .failed(.stillLoading)) == .stillLoading)
        let outcome = DictationOutcome(text: "ship it", method: .accessibility, cleanedBy: .rules)
        #expect(OnboardingWindowController.trial(for: .inserted(outcome)) == .heard("ship it"))
    }

    /// Dictating into Uttrflow's own window is refused as an insertion, so the words come back on the failure.
    @Test("shows the words a failed insertion kept, and nothing when none were kept")
    func failuresCarryTheirWords() {
        let kept = DictationFailure(
            message: "No field.", recovery: nil, severity: .recoverable, transcript: "hello")
        #expect(OnboardingWindowController.trial(for: .failed(kept)) == .heard("hello"))
        let lost = DictationFailure(message: "No field.", recovery: nil, severity: .recoverable)
        #expect(OnboardingWindowController.trial(for: .failed(lost)) == .heard(""))
    }

    @Test("changes nothing while the words are still on their way")
    func inBetweenStatesChangeNothing() {
        for state in [DictationState.idle, .transcribing, .tidying, .inserting(into: nil)] {
            #expect(OnboardingWindowController.trial(for: state) == nil, "\(state)")
        }
    }
}
