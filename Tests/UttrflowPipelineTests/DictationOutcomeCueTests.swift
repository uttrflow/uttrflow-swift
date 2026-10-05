// Tests which outcome cue a finished dictation earns and when it is allowed to play.
import Synchronization
import Testing

@testable import UttrflowCore
@testable import UttrflowPipeline

@Suite("Dictation outcome cues")
struct DictationOutcomeCueTests {
    private static func inserted(
        _ method: TextInsertionMethod = .accessibility, arrival: InsertionArrival = .confirmed,
        fromRecording: Bool = false
    ) -> DictationState {
        .inserted(
            DictationOutcome(
                text: "The words.", method: method, cleanedBy: .rules, fromRecording: fromRecording,
                arrival: arrival))
    }

    private static func failed(_ severity: FailureSeverity) -> DictationState {
        .failed(DictationFailure(message: "It failed.", recovery: nil, severity: severity))
    }

    private static func reporter(
        _ spy: OutcomeCueSpy, sounds: Bool = true, landed: Bool = true, attention: Bool = true,
        voiceOver: Bool = false
    ) -> DictationOutcomeCueReporter {
        DictationOutcomeCueReporter(
            cue: spy,
            switches: OutcomeCueSwitches(
                soundsEnabled: { sounds }, landedEnabled: { landed }, attentionEnabled: { attention },
                voiceOverSpeaks: { voiceOver }))
    }

    @Test("earns the landed cue only for a typed dictation seen to arrive")
    func landedNeedsConfirmedArrival() {
        #expect(DictationOutcomeCue.cue(for: Self.inserted()) == .landed)
        for arrival in [InsertionArrival.unconfirmed, .notReported] {
            #expect(DictationOutcomeCue.cue(for: Self.inserted(arrival: arrival)) == nil, "\(arrival)")
        }
        #expect(DictationOutcomeCue.cue(for: Self.inserted(.clipboard)) == nil)
        #expect(DictationOutcomeCue.cue(for: Self.inserted(fromRecording: true)) == nil)
    }

    @Test("earns the attention cue for every failure that is not informational")
    func attentionSkipsInformational() {
        for severity in FailureSeverity.allCases {
            let expected: DictationOutcomeCue? = severity == .informational ? nil : .attention
            #expect(DictationOutcomeCue.cue(for: Self.failed(severity)) == expected, "\(severity)")
        }
    }

    @Test("earns nothing while resting, recording or working")
    func quietStates() {
        for state in [DictationState.idle, .recording, .transcribing, .tidying, .inserting] {
            #expect(DictationOutcomeCue.cue(for: state) == nil, "\(state)")
        }
    }

    @Test("plays each cue once per arrival")
    func playsOncePerEvent() {
        let spy = OutcomeCueSpy()
        let reporter = Self.reporter(spy)
        reporter.report(Self.inserted())
        reporter.report(Self.failed(.recoverable))
        reporter.report(Self.inserted(arrival: .unconfirmed))
        reporter.report(Self.failed(.informational))
        #expect(spy.played == [.landed, .attention])
    }

    @Test("obeys its own switch, the master switch and VoiceOver")
    func switches() {
        let cases:
            [(sounds: Bool, landed: Bool, attention: Bool, voiceOver: Bool, heard: [DictationOutcomeCue])] = [
                (true, true, true, false, [.landed, .attention]),
                (false, true, true, false, []),
                (true, false, true, false, [.attention]),
                (true, true, false, false, [.landed]),
                (true, true, true, true, []),
            ]
        for row in cases {
            let spy = OutcomeCueSpy()
            let reporter = Self.reporter(
                spy, sounds: row.sounds, landed: row.landed, attention: row.attention,
                voiceOver: row.voiceOver)
            reporter.report(Self.inserted())
            reporter.report(Self.failed(.blocking))
            #expect(spy.played == row.heard, "\(row)")
        }
    }

    @Test("stays silent by default until a cue is switched on")
    func offByDefault() {
        let spy = OutcomeCueSpy()
        let reporter = DictationOutcomeCueReporter(
            cue: spy, switches: OutcomeCueSwitches(soundsEnabled: { true }, voiceOverSpeaks: { false }))
        reporter.report(Self.inserted())
        reporter.report(Self.failed(.blocking))
        #expect(spy.played.isEmpty)
    }

    @Test("the silent cue plays nothing and can stand in anywhere")
    func silentCue() {
        let reporter = DictationOutcomeCueReporter(
            cue: SilentOutcomeCue(),
            switches: OutcomeCueSwitches(
                soundsEnabled: { true }, landedEnabled: { true }, attentionEnabled: { true },
                voiceOverSpeaks: { false }))
        reporter.report(Self.inserted())
        reporter.report(Self.failed(.blocking))
    }
}

private final class OutcomeCueSpy: OutcomeCueing {
    private let heard = Mutex<[DictationOutcomeCue]>([])
    var played: [DictationOutcomeCue] { heard.withLock { $0 } }
    func playLanded() { heard.withLock { $0.append(.landed) } }
    func playAttention() { heard.withLock { $0.append(.attention) } }
}
