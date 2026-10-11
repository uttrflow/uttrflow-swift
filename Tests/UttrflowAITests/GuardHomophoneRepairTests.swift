import Testing
import UttrflowCore

@testable import UttrflowAI

/// Issue 2325: a sound-alike respelled by the model is the word that was said, so the guard lets the repair through.
@Suite("MeaningPreservationGuard homophone repairs")
struct GuardHomophoneRepairTests {
    @Test(
        "accepts a misheard sound-alike the model respelled",
        arguments: [
            ("i new the build would fail", "I knew the build would fail."),
            ("we bought a knew printer", "We bought a new printer."),
            ("i can here you", "I can hear you."),
            ("we ship next weak", "We ship next week."),
            ("the signal is week", "The signal is weak."),
            ("a peace of the cake", "A piece of the cake."),
            ("lets meat at the station", "Let's meet at the station."),
            ("i no the answer to that question", "I know the answer to that question."),
            ("they no a better route", "They know a better route."),
        ]
    )
    func acceptsARespelledSoundAlike(kept: String, rewritten: String) {
        #expect(MeaningPreservationGuard.grammarVerdict(kept: kept, rewritten: rewritten).isAccepted)
    }

    @Test(
        "still refuses a swap for a word that only sounds near",
        arguments: [
            ("please confirm the order", "Please confuse the order."),
            ("the main branch is green", "The man branch is green."),
            ("send the contract today", "Send the contact today."),
            ("there is no milk left", "There is milk left."),
            ("i have no the time", "I have the time."),
            ("no the meeting is off", "The meeting is off."),
        ]
    )
    func refusesANearSound(kept: String, rewritten: String) {
        #expect(!MeaningPreservationGuard.grammarVerdict(kept: kept, rewritten: rewritten).isAccepted)
    }
}
