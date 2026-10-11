import Foundation
import UttrflowUX

/// What onboarding's moving pieces show at a moment, kept apart from the views so it can be tested.
enum OnboardingMotion {
    /// How many letters show: in over 2.4 s, then out again, over and over.
    static func typed(_ count: Int, at time: TimeInterval) -> Int {
        let phase = time.truncatingRemainder(dividingBy: 4.8) / 2.4
        let share = phase <= 1 ? phase : 2 - phase
        return Int((share * Double(count)).rounded())
    }

    /// How far a refused field shakes sideways, in points, at `travel` through the shake.
    static func shakeOffset(_ travel: Double) -> Double {
        4 * sin(travel * .pi * 4)
    }

    /// What VoiceOver reads for the download ring.
    static func downloadLabel(_ download: OnboardingDownload, share: Double) -> String {
        switch download {
        case .running: "Downloading the speech model, \(Int(share * 100))%"
        case .stopped: "The download stopped at \(Int(share * 100))%"
        case .finished: "The speech model is ready"
        }
    }
}
