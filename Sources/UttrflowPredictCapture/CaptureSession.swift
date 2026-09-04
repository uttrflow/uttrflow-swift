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

/// Watches one field at a time and writes what the user finishes in it.
public actor CaptureSession {
    private let sink: any CaptureSink
    private let preferencesFile: CapturePreferencesFile
    private let policy: CommitPolicy
    private var preferences: CapturePreferences
    private var focused: FieldReading?
    private var detector = CommitDetector()
    private var previous: [Surface: String] = [:]

    public init(
        sink: any CaptureSink, preferencesFile: CapturePreferencesFile, policy: CommitPolicy = .everyEnding
    ) {
        self.sink = sink
        self.preferencesFile = preferencesFile
        self.policy = policy
        preferences = preferencesFile.load()
    }

    /// Takes one event in one field and answers with what it came to.
    public func handle(_ event: CaptureEvent, in reading: FieldReading) async throws -> CaptureOutcome {
        // The application leaving is the one still focused here, whatever field the caller last read in it.
        if case .applicationDeactivated = event, focused != reading {
            defer { focused = nil }
            return try await flush(with: event)
        }
        if focused != reading {
            _ = try await flush(with: .focusLeft(at: event.moment))
            focused = reading
        }
        guard let surface = reading.surface, let commit = detector.receive(event) else { return .nothing }
        return try await write(commit, from: reading, in: surface, at: event.moment)
    }

    /// Records a completion the person took as a line of theirs, through the same refusals as anything they typed.
    public func accepted(
        _ text: String, in reading: FieldReading, at moment: Date
    ) async throws -> CaptureOutcome {
        guard let surface = reading.surface else { return .nothing }
        if let refusal = CaptureGate.refusal(toRecord: text, from: reading, given: preferences) {
            return .refused(refusal)
        }
        // The line is recorded before the acceptance is counted, so the first acceptance of a new line is not lost.
        try await sink.record(text, in: surface, after: previous[surface], selfSourced: true, at: moment)
        try await sink.recordAccepted(text, in: surface)
        previous[surface] = text
        return .recorded(text)
    }

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

    /// Ends the focused field with this event, so a half-finished value is not lost.
    private func flush(with ending: CaptureEvent) async throws -> CaptureOutcome {
        defer { detector.reset() }
        guard let leaving = focused, let surface = leaving.surface, let commit = detector.receive(ending)
        else { return .nothing }
        return try await write(commit, from: leaving, in: surface, at: ending.moment)
    }

    /// Puts a finished value through every refusal and then into the corpus.
    private func write(
        _ commit: Commit, from reading: FieldReading, in surface: Surface, at moment: Date
    ) async throws -> CaptureOutcome {
        guard policy.admits(commit.reason, in: reading) else { return .nothing }
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
}
