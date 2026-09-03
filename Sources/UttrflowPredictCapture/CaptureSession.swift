public import UttrflowPredict

public import struct Foundation.Date

/// What came of one event, which is nothing at all almost every time.
public enum CaptureOutcome: Sendable, Equatable {
    /// Nothing was finished, so nothing was written.
    case nothing
    /// A finished value reached the corpus.
    case recorded(String)
    /// A finished value was refused before it could be written.
    case refused(CaptureRefusal)
}

/// Watches one field at a time, writes what the user finishes, and measures what would have been drawn.
public actor CaptureSession {
    private let sink: any CaptureSink
    private let preferencesFile: CapturePreferencesFile
    private var preferences: CapturePreferences
    private var focused: FieldReading?
    private var detector = CommitDetector()
    private var run = ShadowRun()
    private var previous: [Surface: String] = [:]
    private var tallies: [String: ShadowTally] = [:]

    public init(sink: any CaptureSink, preferencesFile: CapturePreferencesFile) {
        self.sink = sink
        self.preferencesFile = preferencesFile
        preferences = preferencesFile.load()
    }

    /// Takes one event in one field and answers with what it came to.
    public func handle(_ event: CaptureEvent, in reading: FieldReading) async throws -> CaptureOutcome {
        if focused != reading {
            try await flush(at: event.moment)
            focused = reading
        }
        guard let surface = reading.surface else { return .nothing }
        if case .keystroke(let typed, let moment) = event {
            await observe(typed, in: surface, at: moment)
        }
        guard let commit = detector.receive(event) else { return .nothing }
        return try await write(commit, from: reading, in: surface, at: event.moment)
    }

    /// What shadow mode has counted, per application, which is the whole point of this phase.
    public func measurements() -> [String: ShadowTally] { tallies }

    /// What the user has decided about capture so far.
    public func decisions() -> CapturePreferences { preferences }

    /// Records the user's answer about one application and keeps it for the next launch.
    public func record(_ state: ConsentState, for bundleIdentifier: String) throws {
        preferences.record(state, for: bundleIdentifier)
        try preferencesFile.save(preferences)
    }

    /// Seeds a terminal from the shell's history, once, and only because the user asked for it.
    public func importShellHistory(
        forHomeDirectory home: String, into surface: Surface, at moment: Date
    ) async throws -> Int {
        guard !preferences.hasImportedShellHistory else { return 0 }
        preferences.hasImportedShellHistory = true
        try preferencesFile.save(preferences)
        for path in ShellHistory.paths(inHomeDirectory: home) {
            let commands = ShellHistory.read(atPath: path)
            guard !commands.isEmpty else { continue }
            var stored = 0
            for command in commands where !DestructiveCommand.matches(command) {
                try await sink.record(
                    command, in: surface, after: nil, selfSourced: false, at: moment)
                stored += 1
            }
            return stored
        }
        return 0
    }

    /// Asks the engine what it would draw at this keystroke, counts the answer, and draws nothing.
    private func observe(_ typed: String, in surface: Surface, at moment: Date) async {
        guard !typed.isEmpty else { return }
        let candidates = (try? await sink.candidates(for: surface, matching: typed)) ?? []
        let context = PredictionContext(typed: typed, isSecure: false)
        run.observe(PredictionEngine.suggestion(from: candidates, in: context, now: moment))
    }

    /// Commits whatever the field the focus is leaving still holds, so a half-finished value is not lost.
    private func flush(at moment: Date) async throws {
        defer {
            detector.reset()
            run.discard()
        }
        guard let leaving = focused, let surface = leaving.surface,
            let commit = detector.receive(.focusLeft(at: moment))
        else { return }
        _ = try await write(commit, from: leaving, in: surface, at: moment)
    }

    /// Puts a finished value through every refusal and then into the corpus.
    private func write(
        _ commit: Commit, from reading: FieldReading, in surface: Surface, at moment: Date
    ) async throws -> CaptureOutcome {
        fold(run.resolve(against: commit.text), into: reading.bundleIdentifier)
        if let refusal = CaptureGate.refusal(
            toRecord: commit.text, from: reading, given: preferences)
        {
            return .refused(refusal)
        }
        if let superseded = commit.supersedes {
            try await sink.supersede(superseded, with: commit.text, in: surface)
        }
        try await sink.record(
            commit.text, in: surface, after: previous[surface], selfSourced: false, at: moment)
        previous[surface] = commit.text
        return .recorded(commit.text)
    }

    /// Adds one field's measurements to the application they belong to.
    private func fold(_ tally: ShadowTally, into bundleIdentifier: String) {
        tallies[bundleIdentifier] = (tallies[bundleIdentifier] ?? ShadowTally()) + tally
    }
}
