import Foundation
import Testing
import UttrflowPredict

@testable import UttrflowPredictCapture

/// A sink that remembers what it was told, so the session can be driven without a database.
private actor Recorder: CaptureSink {
    private(set) var recorded: [(text: String, surface: Surface, previous: String?)] = []
    private(set) var superseded: [(text: String, replacement: String)] = []
    private var offered: [String: [Candidate]] = [:]

    /// Answers a typed prefix with candidates, so shadow mode has something to be right or wrong about.
    func offer(_ candidates: [Candidate], forTyped typed: String) {
        offered[typed] = candidates
    }

    func candidates(for surface: Surface, matching typed: String) -> [Candidate] {
        offered[typed] ?? []
    }

    func successors(for surface: Surface, after previous: String) -> [Candidate] { [] }

    func record(
        _ text: String, in surface: Surface, after previous: String?, selfSourced: Bool, at moment: Date
    ) {
        recorded.append((text, surface, previous))
    }

    func supersede(_ text: String, with replacement: String, in surface: Surface) {
        superseded.append((text, replacement))
    }

    var texts: [String] { recorded.map(\.text) }
}

private let start = Date(timeIntervalSince1970: 1_800_000_000)
private let terminal = FieldReading(bundleIdentifier: "com.example.terminal", role: "AXTextArea")
private let browser = FieldReading(
    bundleIdentifier: "com.example.browser", role: "AXTextField", identifier: "omnibox")

/// A candidate with enough behind it that the engine will speak of it.
private func remembered(_ text: String, count: Int = 20) -> Candidate {
    Candidate(
        text: text, source: .personal,
        evidence: Entry(text: text, count: count, lastUsed: start))
}

/// A session over a scratch preferences file, with the given applications already opted in.
private func session(
    _ scratch: borrowing Scratch, _ recorder: Recorder, allowing: [String] = []
)
    async throws -> CaptureSession
{
    let session = CaptureSession(
        sink: recorder, preferencesFile: CapturePreferencesFile(path: scratch.preferencesPath))
    for bundleIdentifier in allowing { try await session.record(.allowed, for: bundleIdentifier) }
    return session
}

@Suite("Capturing what the user finishes")
struct CaptureSessionTests {
    @Test("Typing writes nothing; only finishing does.")
    func onlyFinishedValuesAreWritten() async throws {
        let scratch = Scratch()
        let recorder = Recorder()
        let session = try await session(scratch, recorder, allowing: ["com.example.terminal"])
        for (index, prefix) in ["g", "gi", "git"].enumerated() {
            let outcome = try await session.handle(
                .keystroke(prefix, at: start.addingTimeInterval(Double(index))), in: terminal)
            #expect(outcome == .nothing)
        }
        #expect(await recorder.texts.isEmpty)
        let outcome = try await session.handle(.returnPressed(at: start), in: terminal)
        #expect(outcome == .recorded("git"))
        #expect(await recorder.texts == ["git"])
    }

    @Test("A password field is refused, so what is typed into it is never written.")
    func secureFieldsAreRefused() async throws {
        let scratch = Scratch()
        let recorder = Recorder()
        let session = try await session(scratch, recorder, allowing: ["com.example.terminal"])
        let secure = FieldReading(
            bundleIdentifier: "com.example.terminal", role: "AXTextField",
            subrole: "AXSecureTextField")
        _ = try await session.handle(.keystroke("correct horse", at: start), in: secure)
        let outcome = try await session.handle(.returnPressed(at: start), in: secure)
        #expect(outcome == .refused(.secureField))
        #expect(await recorder.texts.isEmpty)
    }

    @Test("An application nobody has opted into is refused, and says so, so the user can be asked.")
    func unknownApplicationIsRefused() async throws {
        let scratch = Scratch()
        let recorder = Recorder()
        let session = try await session(scratch, recorder)
        _ = try await session.handle(.keystroke("git status", at: start), in: terminal)
        let outcome = try await session.handle(.returnPressed(at: start), in: terminal)
        #expect(outcome == .refused(.consentNotGiven))
        #expect(await recorder.texts.isEmpty)
    }

    @Test("Opting in is remembered for the next launch.")
    func consentOutlivesTheSession() async throws {
        let scratch = Scratch()
        let recorder = Recorder()
        let session = try await session(scratch, recorder, allowing: ["com.example.terminal"])
        #expect(await session.decisions().state(of: "com.example.terminal") == .allowed)
        let file = CapturePreferencesFile(path: scratch.preferencesPath)
        #expect(file.load().state(of: "com.example.terminal") == .allowed)
    }

    @Test("A credential is refused even in an application the user opted into.")
    func secretsAreRefused() async throws {
        let scratch = Scratch()
        let recorder = Recorder()
        let session = try await session(scratch, recorder, allowing: ["com.example.terminal"])
        let secret = "export API_KEY=sk-ant-abcdefghijklmnop0123"
        _ = try await session.handle(.keystroke(secret, at: start), in: terminal)
        #expect(
            try await session.handle(.returnPressed(at: start), in: terminal)
                == .refused(.looksLikeSecret))
        #expect(await recorder.texts.isEmpty)
    }

    @Test("The value entered before is what the next one is recorded as following.")
    func successionIsRecorded() async throws {
        let scratch = Scratch()
        let recorder = Recorder()
        let session = try await session(scratch, recorder, allowing: ["com.example.terminal"])
        _ = try await session.handle(.keystroke("git add -p", at: start), in: terminal)
        _ = try await session.handle(.returnPressed(at: start), in: terminal)
        _ = try await session.handle(.keystroke("git commit", at: start), in: terminal)
        _ = try await session.handle(.returnPressed(at: start), in: terminal)
        #expect(await recorder.recorded.map(\.previous) == [nil, "git add -p"])
    }

    @Test("A value extended after it went idle replaces the half-written one rather than joining it.")
    func continuingSupersedes() async throws {
        let scratch = Scratch()
        let recorder = Recorder()
        let session = try await session(scratch, recorder, allowing: ["com.example.terminal"])
        _ = try await session.handle(.keystroke("git pu", at: start), in: terminal)
        #expect(
            try await session.handle(.tick(at: start.addingTimeInterval(60)), in: terminal)
                == .recorded("git pu"))
        _ = try await session.handle(.keystroke("git push", at: start.addingTimeInterval(61)), in: terminal)
        _ = try await session.handle(.returnPressed(at: start.addingTimeInterval(62)), in: terminal)
        #expect(await recorder.superseded.map(\.text) == ["git pu"])
        #expect(await recorder.texts == ["git pu", "git push"])
    }

    @Test("Moving to another field commits what the first one still held.")
    func changingFieldCommitsTheOldOne() async throws {
        let scratch = Scratch()
        let recorder = Recorder()
        let session = try await session(
            scratch, recorder, allowing: ["com.example.terminal", "com.example.browser"])
        _ = try await session.handle(.keystroke("make verify", at: start), in: terminal)
        _ = try await session.handle(
            .keystroke("example.com", at: start.addingTimeInterval(1)), in: browser)
        #expect(await recorder.texts == ["make verify"])
        #expect(await recorder.recorded.first?.surface == terminal.surface)
    }

    @Test("A field that says too little to be told apart is watched but never written.")
    func namelessFieldsAreIgnored() async throws {
        let scratch = Scratch()
        let recorder = Recorder()
        let session = try await session(scratch, recorder, allowing: [""])
        let nameless = FieldReading(bundleIdentifier: "", role: "AXTextField")
        #expect(try await session.handle(.keystroke("hello", at: start), in: nameless) == .nothing)
        #expect(try await session.handle(.returnPressed(at: start), in: nameless) == .nothing)
        #expect(await recorder.texts.isEmpty)
    }

    @Test("Shadow mode counts what would have been drawn and draws none of it.")
    func shadowModeMeasures() async throws {
        let scratch = Scratch()
        let recorder = Recorder()
        await recorder.offer([remembered("git status")], forTyped: "git s")
        await recorder.offer([remembered("git push"), remembered("git pull")], forTyped: "git st")
        await recorder.offer([remembered("git stash")], forTyped: "git sta")
        let session = try await session(scratch, recorder, allowing: ["com.example.terminal"])
        for typed in ["git s", "git st", "git sta", "git status"] {
            _ = try await session.handle(.keystroke(typed, at: start), in: terminal)
        }
        _ = try await session.handle(.returnPressed(at: start), in: terminal)
        let tally = try #require(await session.measurements()["com.example.terminal"])
        #expect(tally == ShadowTally(keystrokes: 4, shown: 3, matched: 1, confidentlyWrong: 1))
    }

    @Test("Measurements are kept per application, so one app's numbers never flatter another's.")
    func measurementsArePerApplication() async throws {
        let scratch = Scratch()
        let recorder = Recorder()
        let session = try await session(
            scratch, recorder, allowing: ["com.example.terminal", "com.example.browser"])
        _ = try await session.handle(.keystroke("ls", at: start), in: terminal)
        _ = try await session.handle(.returnPressed(at: start), in: terminal)
        _ = try await session.handle(.keystroke("example.com", at: start), in: browser)
        _ = try await session.handle(.returnPressed(at: start), in: browser)
        #expect(
            await session.measurements().keys.sorted() == ["com.example.browser", "com.example.terminal"])
    }

    @Test("Importing a shell history seeds the terminal, and never happens twice.")
    func shellHistoryImportsOnce() async throws {
        let scratch = Scratch()
        try scratch.write(": 1:0;git status\n: 2:0;make verify\n", to: ".zsh_history")
        let recorder = Recorder()
        let session = try await session(scratch, recorder, allowing: ["com.example.terminal"])
        let surface = try #require(terminal.surface)
        let imported = try await session.importShellHistory(
            forHomeDirectory: scratch.directory, into: surface, at: start)
        #expect(imported == 2)
        #expect(await recorder.texts == ["git status", "make verify"])
        let again = try await session.importShellHistory(
            forHomeDirectory: scratch.directory, into: surface, at: start)
        #expect(again == 0)
        #expect(await recorder.texts.count == 2)
    }

    @Test("A home directory with no history in it imports nothing and is not tried again.")
    func shellHistoryMayBeAbsent() async throws {
        let scratch = Scratch()
        let recorder = Recorder()
        let session = try await session(scratch, recorder, allowing: ["com.example.terminal"])
        let surface = try #require(terminal.surface)
        #expect(
            try await session.importShellHistory(
                forHomeDirectory: scratch.directory, into: surface, at: start) == 0)
        #expect(await session.decisions().hasImportedShellHistory)
    }

    @Test("Bash history is read when there is no zsh history beside it.")
    func bashHistoryIsRead() async throws {
        let scratch = Scratch()
        try scratch.write("make verify\n", to: ".bash_history")
        let recorder = Recorder()
        let session = try await session(scratch, recorder, allowing: ["com.example.terminal"])
        let surface = try #require(terminal.surface)
        _ = try await session.importShellHistory(
            forHomeDirectory: scratch.directory, into: surface, at: start)
        #expect(await recorder.texts == ["make verify"])
    }
}
