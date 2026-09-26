import Foundation
import UttrflowTestSupport

@testable import UttrflowPredict

/// A machine that says what a test tells it to, and counts how often it is asked.
actor StubEnvironment: EnvironmentReading {
    /// What to answer for each kind; a kind absent here is one the machine cannot read.
    private let answers: [EnvironmentKind: [String]]
    /// How long each read takes, for the tests about a machine too slow to wait for.
    private let delay: Duration?
    /// How many reads it has been asked for.
    private(set) var reads = 0

    /// A machine that answers this and takes this long over it.
    init(_ answers: [EnvironmentKind: [String]], delay: Duration? = nil) {
        self.answers = answers
        self.delay = delay
    }

    /// What it was told to answer for this kind, after whatever delay it was given; a substitute machine knows everything already, so narrowing it is left to the caller.
    func values(of kind: EnvironmentKind, in directory: String, matching prefix: String) async -> [String]? {
        reads += 1
        if let delay { try? await Task.sleep(for: delay) }
        return answers[kind]
    }
}

/// A model that says what a test tells it to, and counts how often it is asked.
actor ScriptedScoring: CandidateScoring {
    /// The score to answer with, absent for a model that has no opinion.
    private let score: Double?
    /// Whether the model is up, for the tests about one still loading.
    private let loaded: Bool
    /// The clock a slow model runs past the budget on, for the tests about a model too slow to wait for.
    private let overrunning: ManualClock?
    /// How many scores it has been asked for.
    private(set) var asked = 0

    /// A model that answers this, is up or is not, and runs past the budget on `overrunning` when given one.
    init(_ score: Double?, loaded: Bool = true, overrunning: ManualClock? = nil) {
        self.score = score
        self.loaded = loaded
        self.overrunning = overrunning
    }

    /// Whether the model is up.
    var isReady: Bool { loaded }

    /// The score it was told to answer, only after the budget has run out when it is a slow one.
    func logLikelihood(of candidate: String, following context: String) async -> Double? {
        asked += 1
        if let overrunning {
            overrunning.advance(by: .seconds(3_600))
            // Cut short when the verifier stops waiting; a verifier that never stops gets the score late.
            try? await Task.sleep(for: .seconds(30))
        }
        return score
    }
}

/// A model that answers this, but blocks the thread rather than honouring cancellation while it does.
actor NoncooperativeScoring: CandidateScoring {
    /// The score to answer with once the sleep is over.
    private let score: Double?
    /// How long the thread is held regardless of whether the caller has stopped waiting.
    private let holdForMilliseconds: Int
    /// The clock a deadline waits on, pushed past its budget the moment this is asked, as `ScriptedScoring` does.
    private let advancing: ManualClock?

    /// A model that answers `score` after blocking the thread for `holdForMilliseconds`, cancellation or not.
    init(
        _ score: Double?, holdingThreadForMilliseconds holdForMilliseconds: Int,
        advancing: ManualClock? = nil
    ) {
        self.score = score
        self.holdForMilliseconds = holdForMilliseconds
        self.advancing = advancing
    }

    var isReady: Bool { true }

    /// Blocks with `usleep`, a plain C call with no cancellation check, unlike `Task.sleep`.
    func logLikelihood(of candidate: String, following context: String) async -> Double? {
        advancing?.advance(by: .seconds(3_600))
        usleep(useconds_t(holdForMilliseconds * 1_000))
        return score
    }
}

/// A store that only remembers being told a candidate was wrong.
actor RecordingSupersession: SupersessionRecording {
    /// Each supersession as `wrong → right`.
    private(set) var recorded: [String] = []
    /// Each text condemned with nothing to put in its place.
    private(set) var rejected: [String] = []

    /// Notes one supersession without doing anything else about it.
    func recordSupersession(of text: String, by replacement: String, in surface: Surface) {
        recorded.append("\(text) → \(replacement)")
    }

    /// Notes one rejection without doing anything else about it.
    func recordRejection(of text: String, in surface: Surface) {
        rejected.append(text)
    }
}
