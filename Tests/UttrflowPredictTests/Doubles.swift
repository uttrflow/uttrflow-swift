import Foundation

@testable import UttrflowPredict

/// A machine that says what a test tells it to, and counts how often it is asked.
actor StubEnvironment: EnvironmentReading {
    /// What to answer for each kind; a kind it was told nothing about is one it cannot read.
    private let answers: [EnvironmentKind: [String]]
    /// How long each read takes, for the tests about a machine too slow to wait for.
    private let delay: Duration?
    /// How many reads it has been asked for.
    private(set) var reads = 0

    init(_ answers: [EnvironmentKind: [String]], delay: Duration? = nil) {
        self.answers = answers
        self.delay = delay
    }

    func values(of kind: EnvironmentKind, in directory: String) async -> [String]? {
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
    /// How long a score takes, for the tests about a model too slow to wait for.
    private let delay: Duration?
    /// How many scores it has been asked for.
    private(set) var asked = 0

    init(_ score: Double?, loaded: Bool = true, delay: Duration? = nil) {
        self.score = score
        self.loaded = loaded
        self.delay = delay
    }

    var isReady: Bool { loaded }

    func logLikelihood(of candidate: String, following context: String) async -> Double? {
        asked += 1
        if let delay { try? await Task.sleep(for: delay) }
        return score
    }
}

/// A store that only remembers being told a candidate was wrong.
actor RecordingSupersession: SupersessionRecording {
    /// Each supersession as `wrong → right`.
    private(set) var recorded: [String] = []
    /// Each text condemned with nothing to put in its place.
    private(set) var rejected: [String] = []

    func recordSupersession(of text: String, by replacement: String, in surface: Surface) {
        recorded.append("\(text) → \(replacement)")
    }

    func recordRejection(of text: String, in surface: Surface) {
        rejected.append(text)
    }
}
