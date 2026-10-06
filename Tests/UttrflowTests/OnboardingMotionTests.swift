// Tests for what onboarding's moving pieces show at a moment.
import Testing

@testable import Uttrflow
import UttrflowUX

@Suite("Onboarding's moving pieces")
struct OnboardingMotionTests {
    @Test("the field types in over 2.4 s and out again by 4.8 s")
    func typesInAndOut() {
        #expect(OnboardingMotion.typed(10, at: 0) == 0)
        #expect(OnboardingMotion.typed(10, at: 1.2) == 5)
        #expect(OnboardingMotion.typed(10, at: 2.4) == 10)
        #expect(OnboardingMotion.typed(10, at: 3.6) == 5)
        #expect(OnboardingMotion.typed(10, at: 4.8) == 0)
    }

    @Test("a shake starts and ends at rest and moves at most four points")
    func shakeIsSmall() {
        #expect(abs(OnboardingMotion.shakeOffset(0)) < 1e-9)
        #expect(abs(OnboardingMotion.shakeOffset(1)) < 1e-9)
        #expect(abs(OnboardingMotion.shakeOffset(0.125) - 4) < 1e-9)
    }

    @Test("the download ring reads its state and percentage")
    func downloadLabels() {
        #expect(OnboardingMotion.downloadLabel(.running, share: 0.42) == "Downloading the speech model, 42%")
        #expect(OnboardingMotion.downloadLabel(.stopped, share: 0.5) == "The download stopped at 50%")
        #expect(OnboardingMotion.downloadLabel(.finished, share: 1) == "The speech model is ready")
    }
}
