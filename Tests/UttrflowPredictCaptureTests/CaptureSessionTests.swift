import Foundation
import Testing
import UttrflowCore
import UttrflowPredict

@testable import UttrflowPredictCapture

/// A sink that remembers what it was told, so the session can be driven without a database.
private actor Recorder: CaptureSink {
    private(set) var recorded: [(text: String, surface: Surface, previous: String?)] = []
    private(set) var superseded: [(text: String, replacement: String)] = []
    private(set) var moments: [Date] = []

    func record(
        _ text: String, in surface: Surface, after previous: String?, selfSourced: Bool, at moment: Date
    ) {
        recorded.append((text, surface, previous))
        moments.append(moment)
    }

    func supersede(_ text: String, with replacement: String, in surface: Surface) {
        superseded.append((text, replacement))
    }

    private(set) var edits: [EditedSpan] = []

    func recordEditedSpan(_ edit: EditedSpan, in surface: Surface) {
        edits.append(edit)
    }

    var texts: [String] { recorded.map(\.text) }
}

/// Collects only the fixed reasons a finished line was excluded.
private actor SkipReasonRecorder {
    private(set) var reasons: [CaptureSkipReason] = []

    func record(_ reason: CaptureSkipReason) { reasons.append(reason) }
}

/// A sink that throws the first `recordFailures` record calls and the first `supersedeFailures` supersede calls, then accepts, so transient write failures can be exercised.
private actor FlakySink: CaptureSink {
    private(set) var recorded: [String] = []
    private(set) var superseded: [(text: String, replacement: String)] = []
    private var recordFailures: Int
    private var supersedeFailures: Int
    private var acceptFailures: Int
    private var retractFailures: Int
    private var shouldSuspendNextRecord = false
    private var recordSuspension: CheckedContinuation<Void, any Error>?
    private var recordSuspensionWaiter: CheckedContinuation<Void, Never>?
    private var isRecordSuspended = false
    private(set) var accepted: [String] = []

    init(
        recordFailures: Int = 0, supersedeFailures: Int = 0, acceptFailures: Int = 0,
        retractFailures: Int = 0
    ) {
        self.recordFailures = recordFailures
        self.supersedeFailures = supersedeFailures
        self.acceptFailures = acceptFailures
        self.retractFailures = retractFailures
    }

    func recordAccepted(_ text: String, in surface: Surface) throws {
        if acceptFailures > 0 {
            acceptFailures -= 1
            throw FlakySinkError.transient
        }
        accepted.append(text)
    }

    func record(
        _ text: String, in surface: Surface, after previous: String?, selfSourced: Bool, at moment: Date
    ) async throws {
        if shouldSuspendNextRecord {
            shouldSuspendNextRecord = false
            try await withCheckedThrowingContinuation {
                (continuation: CheckedContinuation<Void, any Error>) in
                recordSuspension = continuation
                isRecordSuspended = true
                recordSuspensionWaiter?.resume()
                recordSuspensionWaiter = nil
            }
        }
        if recordFailures > 0 {
            recordFailures -= 1
            throw FlakySinkError.transient
        }
        recorded.append(text)
    }

    func supersede(_ text: String, with replacement: String, in surface: Surface) throws {
        if supersedeFailures > 0 {
            supersedeFailures -= 1
            throw FlakySinkError.transient
        }
        superseded.append((text, replacement))
    }

    func retractAcceptance(_ text: String, in surface: Surface) throws {
        if retractFailures > 0 {
            retractFailures -= 1
            throw FlakySinkError.transient
        }
        if let index = accepted.firstIndex(of: text) { accepted.remove(at: index) }
    }

    func failNextRecordWrites(_ count: Int) {
        recordFailures = count
    }

    func suspendNextRecordWrite() {
        shouldSuspendNextRecord = true
    }

    func waitForSuspendedRecord() async {
        guard !isRecordSuspended else { return }
        await withCheckedContinuation { continuation in
            recordSuspensionWaiter = continuation
        }
    }

    func failSuspendedRecord() {
        recordSuspension?.resume(throwing: FlakySinkError.transient)
        recordSuspension = nil
        isRecordSuspended = false
    }
}

private enum FlakySinkError: Error { case transient }

/// A sink whose first record waits until released, so a second write can arrive while it is suspended.
private actor GatedSink: CaptureSink {
    private(set) var recorded: [(text: String, previous: String?)] = []
    private var gate: CheckedContinuation<Void, Never>?
    private var isHolding = true

    func record(
        _ text: String, in surface: Surface, after previous: String?, selfSourced: Bool, at moment: Date
    ) async {
        recorded.append((text, previous))
        guard isHolding else { return }
        isHolding = false
        await withCheckedContinuation { gate = $0 }
    }

    func supersede(_ text: String, with replacement: String, in surface: Surface) {}

    var isWaiting: Bool { gate != nil }

    func release() {
        gate?.resume()
        gate = nil
    }
}

/// A sink that fails its first record, holds the second until released, and then lets every write through.
private actor RetryGateSink: CaptureSink {
    private(set) var recorded: [String] = []
    private var calls = 0
    private var gate: CheckedContinuation<Bool, Never>?

    func record(
        _ text: String, in surface: Surface, after previous: String?, selfSourced: Bool, at moment: Date
    ) async throws {
        calls += 1
        if calls == 1 { throw FlakySinkError.transient }
        if calls == 2, await withCheckedContinuation({ gate = $0 }) { throw FlakySinkError.transient }
        recorded.append(text)
    }

    func supersede(_ text: String, with replacement: String, in surface: Surface) {}

    var isWaiting: Bool { gate != nil }

    /// Resumes the held record, failing it when asked.
    func release(failing: Bool) {
        gate?.resume(returning: failing)
        gate = nil
    }
}

private let start = Date(timeIntervalSince1970: 1_800_000_000)
private let terminal = FieldReading(bundleIdentifier: "com.example.terminal", role: "AXTextArea")
private let browser = FieldReading(
    bundleIdentifier: "com.example.browser", role: "AXTextField", identifier: "omnibox")

/// A policy that finishes a field only this way, so recording through it proves the reason a commit carried.
private func only(_ reason: CommitReason) -> CommitPolicy {
    CommitPolicy { ended, _ in ended == reason }
}

/// A session over a scratch preferences file, with the given applications already opted in.
private func session<Sink: CaptureSink>(
    _ scratch: borrowing Scratch, _ sink: Sink, allowing: [String] = [],
    policy: CommitPolicy = .everyEnding
)
    async throws -> CaptureSession
{
    let session = CaptureSession(
        sink: sink, preferencesFile: CapturePreferencesFile(path: scratch.preferencesPath),
        policy: policy)
    for bundleIdentifier in allowing { try await session.record(.allowed, for: bundleIdentifier) }
    return session
}

@Suite("Capturing what the user finishes")
struct CaptureSessionTests {
    @Test("a skipped finished line reports its fixed reason without its text")
    func skippedLineReportsReason() async throws {
        let scratch = Scratch()
        let sink = Recorder()
        let skips = SkipReasonRecorder()
        let capture = CaptureSession(
            sink: sink, preferencesFile: CapturePreferencesFile(path: scratch.preferencesPath),
            onCommitSkipped: { reason in await skips.record(reason) })
        try await capture.record(.allowed, for: terminal.bundleIdentifier)
        _ = try await capture.handle(.keystroke("kubectl get po", at: start), in: terminal)
        _ = try await capture.handle(
            .typed("ds", at: start.addingTimeInterval(0.01)), in: terminal)
        _ = try await capture.handle(
            .keystroke("kubectl get podx", at: start.addingTimeInterval(0.5)), in: terminal)
        _ = try await capture.handle(.returnPressed(at: start.addingTimeInterval(1)), in: terminal)

        #expect(await skips.reasons == [.unmatchedKeys])
        #expect(await sink.texts.isEmpty)
    }

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

    @Test("A dictation followed by one typed key and Return writes nothing at a typed line's weight.")
    func aDictatedLineIsNotWritten() async throws {
        let scratch = Scratch()
        let recorder = Recorder()
        let chat = FieldReading(bundleIdentifier: "com.example.chat", role: "AXTextArea")
        let session = try await session(scratch, recorder, allowing: ["com.example.chat"])
        let line = "can we move the review to thursday afternoon?"
        for event in CaptureEvent.marking([.keystroke(line, at: start)], insertedAt: start) {
            #expect(try await session.handle(event, in: chat) == .nothing)
        }
        #expect(try await session.handle(.returnPressed(at: start), in: chat) == .nothing)
        #expect(await recorder.texts.isEmpty)
    }

    @Test("A paste followed by Return writes nothing, and the next line typed by hand is written.")
    func aPastedLineIsNotWritten() async throws {
        let scratch = Scratch()
        let recorder = Recorder()
        let chat = FieldReading(bundleIdentifier: "com.example.chat", role: "AXTextArea")
        let session = try await session(scratch, recorder, allowing: ["com.example.chat"])
        let pasted = ReturnCatchUp.events(read: "https://example.com/some/long/link", handed: "", at: start)
        for event in CaptureEvent.marking(pasted, insertedAt: start) {
            _ = try await session.handle(event, in: chat)
        }
        #expect(await recorder.texts.isEmpty)
        _ = try await session.handle(.keystroke("thanks", at: start), in: chat)
        #expect(try await session.handle(.returnPressed(at: start), in: chat) == .recorded("thanks"))
    }

    @Test("A menu paste followed by a typed character and Return writes nothing.")
    func aMenuPastedLineWithOneTypedCharacterIsNotWritten() async throws {
        let scratch = Scratch()
        let recorder = Recorder()
        let chat = FieldReading(bundleIdentifier: "com.example.chat", role: "AXTextArea")
        let session = try await session(scratch, recorder, allowing: ["com.example.chat"])
        let pasted = "https://example.com/some/long/link"
        let moment = start.addingTimeInterval(1)

        _ = try await session.handle(.typed("x", at: moment), in: chat)
        _ = try await session.handle(.keystroke(pasted + "x", at: moment), in: chat)
        _ = try await session.handle(.inserted(at: moment), in: chat)

        #expect(try await session.handle(.returnPressed(at: moment), in: chat) == .nothing)
        #expect(await recorder.texts.isEmpty)
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

    @Test("An accepted suggestion in a password field is refused and never recorded.")
    func acceptedSuggestionInSecureFieldIsRefused() async throws {
        let scratch = Scratch()
        let recorder = Recorder()
        let session = try await session(scratch, recorder, allowing: ["com.example.terminal"])
        let secure = FieldReading(
            bundleIdentifier: "com.example.terminal", role: "AXTextField",
            subrole: "AXSecureTextField")

        #expect(
            try await session.accepted("suggested value", in: secure, at: start)
                == .refused(.secureField))
        #expect(await recorder.texts.isEmpty)
    }

    @Test("An application nobody has been asked about is learned from, since learning is on by default.")
    func unknownApplicationIsLearned() async throws {
        let scratch = Scratch()
        let recorder = Recorder()
        let session = try await session(scratch, recorder)
        _ = try await session.handle(.keystroke("git status", at: start), in: terminal)
        let outcome = try await session.handle(.returnPressed(at: start), in: terminal)
        #expect(outcome == .recorded("git status"))
        #expect(await recorder.texts == ["git status"])
    }

    @Test("An accepted suggestion in an unasked application is recorded, since learning is on by default.")
    func acceptedSuggestionInUnaskedApplicationIsRecorded() async throws {
        let scratch = Scratch()
        let recorder = Recorder()
        let session = try await session(scratch, recorder)

        #expect(try await session.accepted("git status", in: terminal, at: start) == .recorded("git status"))
        #expect(await recorder.texts == ["git status"])
    }

    @Test("An accepted suggestion in a declined application is refused and never recorded.")
    func acceptedSuggestionInDeclinedApplicationIsRefused() async throws {
        let scratch = Scratch()
        let recorder = Recorder()
        let session = try await session(scratch, recorder)
        try await session.record(.declined, for: "com.example.terminal")

        #expect(
            try await session.accepted("git status", in: terminal, at: start)
                == .refused(.consentDeclined))
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

    @Test("An accepted secret-shaped suggestion is refused and never recorded.")
    func acceptedSecretShapedSuggestionIsRefused() async throws {
        let scratch = Scratch()
        let recorder = Recorder()
        let session = try await session(scratch, recorder, allowing: ["com.example.terminal"])
        let secret = "export API_KEY=sk-ant-abcdefghijklmnop0123"

        #expect(
            try await session.accepted(secret, in: terminal, at: start)
                == .refused(.looksLikeSecret))
        #expect(await recorder.texts.isEmpty)
    }

    @Test("An accepted suggestion without a surface records nothing.")
    func acceptedSuggestionWithoutSurfaceRecordsNothing() async throws {
        let scratch = Scratch()
        let recorder = Recorder()
        let session = try await session(scratch, recorder)
        let nameless = FieldReading(bundleIdentifier: "", role: "AXTextField")

        #expect(try await session.accepted("hello", in: nameless, at: start) == .nothing)
        #expect(await recorder.texts.isEmpty)
    }

    @Test("Return after accepting a correction records only the accepted line, not the typo it replaced.")
    func returnAfterAcceptedCorrectionRecordsNothingNew() async throws {
        let scratch = Scratch()
        let recorder = Recorder()
        let session = try await session(scratch, recorder, allowing: ["com.example.terminal"])
        _ = try await session.handle(.keystroke("git chekout", at: start), in: terminal)
        _ = try await session.accepted("git checkout main", in: terminal, at: start.addingTimeInterval(1))
        #expect(
            try await session.handle(.returnPressed(at: start.addingTimeInterval(2)), in: terminal)
                == .nothing)
        #expect(await recorder.texts == ["git checkout main"])
    }

    @Test("An accepted extension followed by typing retires the idle draft it extended.")
    func acceptedExtensionFollowedByTypingSupersedesIdleDraft() async throws {
        let scratch = Scratch()
        let recorder = Recorder()
        let session = try await session(scratch, recorder, allowing: ["com.example.terminal"])
        _ = try await session.handle(.keystroke("foo bar", at: start), in: terminal)
        #expect(
            try await session.handle(
                .tick(at: start.addingTimeInterval(CommitDetector.idleInterval)), in: terminal)
                == .recorded("foo bar"))

        #expect(
            try await session.accepted(
                "foo bar baz", over: "foo bar", in: terminal,
                at: start.addingTimeInterval(CommitDetector.idleInterval + 1))
                == .recorded("foo bar baz"))
        #expect(await recorder.superseded.map(\.text) == ["foo bar"])
        #expect(await recorder.superseded.map(\.replacement) == ["foo bar baz"])
        _ = try await session.handle(
            .keystroke("foo bar baz!", at: start.addingTimeInterval(CommitDetector.idleInterval + 2)),
            in: terminal)
        #expect(
            try await session.handle(
                .returnPressed(at: start.addingTimeInterval(CommitDetector.idleInterval + 3)),
                in: terminal) == .recorded("foo bar baz!"))

        #expect(await recorder.superseded.map(\.text) == ["foo bar", "foo bar baz"])
        #expect(await recorder.superseded.map(\.replacement) == ["foo bar baz", "foo bar baz!"])
    }

    @Test("A held accepted extension is retired after a typed continuation reaches the sink.")
    func heldAcceptedExtensionFollowsTypedContinuation() async throws {
        let scratch = Scratch()
        let sink = FlakySink()
        let session = try await session(scratch, sink, allowing: ["com.example.terminal"])
        _ = try await session.handle(.keystroke("foo bar", at: start), in: terminal)
        #expect(
            try await session.handle(
                .tick(at: start.addingTimeInterval(CommitDetector.idleInterval)), in: terminal)
                == .recorded("foo bar"))
        await sink.failNextRecordWrites(3)
        await #expect(throws: FlakySinkError.self) {
            _ = try await session.accepted(
                "foo bar baz", over: "foo bar", in: terminal,
                at: start.addingTimeInterval(CommitDetector.idleInterval + 1))
        }

        _ = try await session.handle(
            .keystroke("foo bar baz!", at: start.addingTimeInterval(CommitDetector.idleInterval + 2)),
            in: terminal)
        #expect(
            try await session.handle(
                .returnPressed(at: start.addingTimeInterval(CommitDetector.idleInterval + 3)),
                in: terminal) == .recorded("foo bar baz!"))
        _ = try await session.handle(
            .tick(at: start.addingTimeInterval(CommitDetector.idleInterval + 4)), in: terminal)

        #expect(await sink.recorded == ["foo bar", "foo bar baz!", "foo bar baz"])
        #expect(await sink.superseded.map(\.text) == ["foo bar baz", "foo bar", "foo bar baz"])
        #expect(
            await sink.superseded.map(\.replacement) == [
                "foo bar baz!", "foo bar baz", "foo bar baz!",
            ])
    }

    @Test("A continuation during a suspended acceptance write is retained when that write fails.")
    func inFlightAcceptedExtensionFollowsTypedContinuation() async throws {
        let scratch = Scratch()
        let sink = FlakySink()
        let session = try await session(scratch, sink, allowing: ["com.example.terminal"])
        _ = try await session.handle(.keystroke("foo bar", at: start), in: terminal)
        #expect(
            try await session.handle(
                .tick(at: start.addingTimeInterval(CommitDetector.idleInterval)), in: terminal)
                == .recorded("foo bar"))

        await sink.suspendNextRecordWrite()
        let accepted = Task {
            try await session.accepted(
                "foo bar baz", over: "foo bar", in: terminal,
                at: start.addingTimeInterval(CommitDetector.idleInterval + 1))
        }
        await sink.waitForSuspendedRecord()
        _ = try await session.handle(
            .keystroke("foo bar baz!", at: start.addingTimeInterval(CommitDetector.idleInterval + 2)),
            in: terminal)
        #expect(
            try await session.handle(
                .returnPressed(at: start.addingTimeInterval(CommitDetector.idleInterval + 3)),
                in: terminal) == .recorded("foo bar baz!"))

        await sink.failSuspendedRecord()
        await #expect(throws: FlakySinkError.self) { _ = try await accepted.value }
        #expect(await session.unwrittenAcceptanceCount() == 1)
        _ = try await session.handle(
            .tick(at: start.addingTimeInterval(CommitDetector.idleInterval + 4)), in: terminal)

        #expect(await sink.recorded == ["foo bar", "foo bar baz!", "foo bar baz"])
        #expect(await sink.superseded.map(\.text) == ["foo bar baz", "foo bar", "foo bar baz"])
        #expect(
            await sink.superseded.map(\.replacement) == [
                "foo bar baz!", "foo bar baz", "foo bar baz!",
            ])
        #expect(await sink.accepted == ["foo bar baz"])
    }

    @Test("Typing more after accepting commits the whole line as it then stands.")
    func typingAfterAcceptCommitsTheFullLine() async throws {
        let scratch = Scratch()
        let recorder = Recorder()
        let session = try await session(scratch, recorder, allowing: ["com.example.terminal"])
        _ = try await session.handle(.keystroke("git chekout", at: start), in: terminal)
        _ = try await session.accepted("git checkout main", in: terminal, at: start.addingTimeInterval(1))
        _ = try await session.handle(
            .keystroke("git checkout main -q", at: start.addingTimeInterval(2)), in: terminal)
        #expect(
            try await session.handle(.returnPressed(at: start.addingTimeInterval(3)), in: terminal)
                == .recorded("git checkout main -q"))
        #expect(await recorder.texts == ["git checkout main", "git checkout main -q"])
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

    @Test("A refused idle value is never handed to the sink as the one a later line replaces.")
    func refusedValueIsNeverSuperseded() async throws {
        let scratch = Scratch()
        let recorder = Recorder()
        let session = try await session(scratch, recorder)
        try await session.record(.declined, for: "com.example.terminal")
        _ = try await session.handle(.keystroke("git pu", at: start), in: terminal)
        #expect(
            try await session.handle(.tick(at: start.addingTimeInterval(60)), in: terminal)
                == .refused(.consentDeclined))
        try await session.record(.allowed, for: "com.example.terminal")
        _ = try await session.handle(.keystroke("git push", at: start.addingTimeInterval(61)), in: terminal)
        #expect(
            try await session.handle(.returnPressed(at: start.addingTimeInterval(62)), in: terminal)
                == .recorded("git push"))
        #expect(await recorder.superseded.isEmpty)
        #expect(await recorder.texts == ["git push"])
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

    @Test(
        "In a shell only Return finishes the line, so what Tab-cycling left behind is not learned on the way out."
    )
    func shellsFinishOnReturnAlone() async throws {
        let scratch = Scratch()
        let recorder = Recorder()
        let session = try await session(
            scratch, recorder, allowing: ["com.example.terminal"],
            policy: returnOnlyInTerminal)
        _ = try await session.handle(.keystroke("lsbom", at: start), in: terminal)
        #expect(try await session.handle(.focusLeft(at: start), in: terminal) == .nothing)
        _ = try await session.handle(.keystroke("lsbom", at: start), in: terminal)
        #expect(try await session.handle(.applicationDeactivated(at: start), in: terminal) == .nothing)
        _ = try await session.handle(.keystroke("ls -la", at: start), in: terminal)
        #expect(try await session.handle(.returnPressed(at: start), in: terminal) == .recorded("ls -la"))
        #expect(await recorder.texts == ["ls -la"])
    }

    @Test(
        "A line left paused where Return sends it is still learned when Return is pressed.",
        arguments: ["com.apple.Terminal", "com.apple.MobileSMS"])
    func pausedLineIsLearnedOnReturn(bundleIdentifier: String) async throws {
        let scratch = Scratch()
        let recorder = Recorder()
        let session = try await session(
            scratch, recorder, allowing: [bundleIdentifier], policy: .whereReturnSends)
        let field = FieldReading(bundleIdentifier: bundleIdentifier, role: "AXTextArea")
        _ = try await session.handle(.keystroke("git status", at: start), in: field)
        #expect(try await session.handle(.tick(at: start.addingTimeInterval(9)), in: field) == .nothing)
        #expect(try await session.handle(.tick(at: start.addingTimeInterval(12)), in: field) == .nothing)
        #expect(
            try await session.handle(.returnPressed(at: start.addingTimeInterval(13)), in: field)
                == .recorded("git status"))
        #expect(await recorder.texts == ["git status"])
    }

    @Test("Where an idle is admitted it learns the line once, and Return does not repeat it.")
    func admittedIdleIsLearnedOnce() async throws {
        let scratch = Scratch()
        let recorder = Recorder()
        let session = try await session(
            scratch, recorder, allowing: ["com.apple.TextEdit"], policy: .whereReturnSends)
        let field = FieldReading(bundleIdentifier: "com.apple.TextEdit", role: "AXTextArea")
        _ = try await session.handle(.keystroke("see you soon", at: start), in: field)
        #expect(
            try await session.handle(.tick(at: start.addingTimeInterval(9)), in: field)
                == .recorded("see you soon"))
        #expect(try await session.handle(.tick(at: start.addingTimeInterval(12)), in: field) == .nothing)
        #expect(
            try await session.handle(.returnPressed(at: start.addingTimeInterval(13)), in: field) == .nothing)
        #expect(await recorder.texts == ["see you soon"])
    }

    @Test("Outside the named shells, leaving a field still finishes what it held.")
    func otherApplicationsFinishOnLeaving() async throws {
        let scratch = Scratch()
        let recorder = Recorder()
        let session = try await session(
            scratch, recorder, allowing: ["com.example.browser"],
            policy: returnOnlyInTerminal)
        _ = try await session.handle(.keystroke("example.com", at: start), in: browser)
        #expect(try await session.handle(.focusLeft(at: start), in: browser) == .recorded("example.com"))
    }

    @Test("Deactivation named against another field still ends the focused one, once, as a deactivation.")
    func deactivationEndsTheFocusedField() async throws {
        let scratch = Scratch()
        let recorder = Recorder()
        let session = try await session(
            scratch, recorder, allowing: ["com.example.terminal", "com.example.browser"],
            policy: only(.applicationDeactivated))
        _ = try await session.handle(.keystroke("make verify", at: start), in: terminal)
        let outcome = try await session.handle(
            .applicationDeactivated(at: start.addingTimeInterval(1)), in: browser)
        #expect(outcome == .recorded("make verify"))
        #expect(await recorder.recorded.map(\.surface) == [terminal.surface])
        _ = try await session.handle(.keystroke("example.com", at: start.addingTimeInterval(2)), in: browser)
        #expect(await recorder.texts == ["make verify"])
    }

    @Test("Deactivation named against the focused field itself commits it once, as a deactivation.")
    func deactivationInTheFocusedFieldCommitsOnce() async throws {
        let scratch = Scratch()
        let recorder = Recorder()
        let session = try await session(
            scratch, recorder, allowing: ["com.example.terminal"], policy: only(.applicationDeactivated))
        _ = try await session.handle(.keystroke("make verify", at: start), in: terminal)
        #expect(
            try await session.handle(.applicationDeactivated(at: start), in: terminal)
                == .recorded("make verify"))
        #expect(try await session.handle(.keystroke("ls", at: start), in: terminal) == .nothing)
        #expect(await recorder.texts == ["make verify"])
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

    @Test("A shell history import whose write fails is not marked done, and the next call finishes it.")
    func failedShellHistoryImportIsRetried() async throws {
        let scratch = Scratch()
        try scratch.write("git status\nmake verify\nswift build\n", to: ".bash_history")
        let sink = FlakySink(recordFailures: 1)
        let session = try await session(scratch, sink, allowing: ["com.example.terminal"])
        let surface = try #require(terminal.surface)
        await #expect(throws: (any Error).self) {
            try await session.importShellHistory(
                forHomeDirectory: scratch.directory, into: surface, at: start)
        }
        #expect(await !session.decisions().hasImportedShellHistory)
        let imported = try await session.importShellHistory(
            forHomeDirectory: scratch.directory, into: surface, at: start)
        #expect(imported == 3)
        #expect(await sink.recorded == ["git status", "make verify", "swift build"])
        #expect(await session.decisions().hasImportedShellHistory)
    }

    @Test("Imported commands are stamped oldest first, ending at the import, so eviction keeps the newest.")
    func importedCommandsKeepTheirOrderInTime() async throws {
        let scratch = Scratch()
        try scratch.write("git status\nmake verify\nswift build\n", to: ".bash_history")
        let recorder = Recorder()
        let session = try await session(scratch, recorder, allowing: ["com.example.terminal"])
        let surface = try #require(terminal.surface)
        _ = try await session.importShellHistory(
            forHomeDirectory: scratch.directory, into: surface, at: start)
        #expect(
            await recorder.moments == [
                start.addingTimeInterval(-2), start.addingTimeInterval(-1), start,
            ])
    }

    @Test("A history line with a command substitution is not imported.")
    func shellHistorySkipsUnresolvedLines() async throws {
        let scratch = Scratch()
        try scratch.write(
            ": 1:0;rm -rf $(find . -name node_modules)\n: 2:0;make verify\n", to: ".zsh_history")
        let recorder = Recorder()
        let session = try await session(scratch, recorder, allowing: ["com.example.terminal"])
        let surface = try #require(terminal.surface)
        let imported = try await session.importShellHistory(
            forHomeDirectory: scratch.directory, into: surface, at: start)
        #expect(imported == 1)
        #expect(await recorder.texts == ["make verify"])
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

@Suite("Forgetting every answer")
struct CaptureSessionForgettingTests {
    @Test("Forgetting every answer empties memory and disk, and the next answer brings none back.")
    func forgettingIsNotUndoneByTheNextAnswer() async throws {
        let scratch = Scratch()
        let session = try await session(scratch, Recorder(), allowing: ["com.example.terminal"])
        try await session.forgetEveryAnswer()
        #expect(await session.decisions() == CapturePreferences())
        #expect(!FileManager.default.fileExists(atPath: scratch.preferencesPath))

        try await session.record(.allowed, for: "com.example.editor")
        let reloaded = CapturePreferencesFile(path: scratch.preferencesPath).load()
        #expect(reloaded.state(of: "com.example.terminal") == .unknown)
        #expect(reloaded.state(of: "com.example.editor") == .allowed)
    }
}

@Suite("Forgetting what was learned")
struct CaptureSessionForgetLearnedTests {
    @Test("A line recorded after its application is forgotten does not follow the forgotten one.")
    func forgettingAnApplicationDropsItsLastLine() async throws {
        let scratch = Scratch()
        let recorder = Recorder()
        let session = try await session(
            scratch, recorder, allowing: ["com.example.terminal", "com.example.browser"])
        _ = try await session.handle(.keystroke("secret line", at: start), in: terminal)
        _ = try await session.handle(.returnPressed(at: start), in: terminal)
        _ = try await session.handle(.keystroke("example.com", at: start), in: browser)
        _ = try await session.handle(.returnPressed(at: start), in: browser)
        await session.forgetLearned(from: "com.example.terminal")
        _ = try await session.handle(.keystroke("next line", at: start), in: terminal)
        _ = try await session.handle(.returnPressed(at: start), in: terminal)
        _ = try await session.handle(.keystroke("example.org", at: start), in: browser)
        _ = try await session.handle(.returnPressed(at: start), in: browser)
        #expect(await recorder.recorded.map(\.previous) == [nil, nil, nil, "example.com"])
    }

    @Test("Forgetting everything drops every last line and every answer, in memory and on disk.")
    func forgettingEverythingDropsLinesAndAnswers() async throws {
        let scratch = Scratch()
        let recorder = Recorder()
        let session = try await session(scratch, recorder, allowing: ["com.example.terminal"])
        _ = try await session.handle(.keystroke("secret line", at: start), in: terminal)
        _ = try await session.handle(.returnPressed(at: start), in: terminal)
        try await session.forgetEverythingLearned()
        #expect(await session.decisions() == CapturePreferences())
        #expect(!FileManager.default.fileExists(atPath: scratch.preferencesPath))
        try await session.record(.allowed, for: "com.example.terminal")
        _ = try await session.handle(.keystroke("next line", at: start), in: terminal)
        _ = try await session.handle(.returnPressed(at: start), in: terminal)
        #expect(await recorder.recorded.map(\.previous) == [nil, nil])
    }
}

@Suite("Surviving a transient capture write failure")
struct CaptureSessionTransientFailureTests {
    @Test(
        "A field's ending whose write fails is held and written before the next event.",
        arguments: [CommitReason.returnPressed, .focusLeft, .applicationDeactivated])
    func failedEndingIsRetriedByTheNextEvent(reason: CommitReason) async throws {
        let scratch = Scratch()
        let sink = FlakySink(recordFailures: 1)
        let session = try await session(
            scratch, sink, allowing: ["com.example.terminal"], policy: only(reason))
        _ = try await session.handle(.keystroke("git status", at: start), in: terminal)
        let ending: CaptureEvent =
            switch reason {
            case .returnPressed: .returnPressed(at: start)
            case .focusLeft: .focusLeft(at: start)
            default: .applicationDeactivated(at: start)
            }
        await #expect(throws: FlakySinkError.self) { _ = try await session.handle(ending, in: terminal) }
        #expect(await sink.recorded.isEmpty)
        #expect(await session.unwrittenCommitCount() == 1)

        _ = try await session.handle(.keystroke("ls", at: start.addingTimeInterval(1)), in: terminal)
        #expect(await sink.recorded == ["git status"])
        #expect(await session.unwrittenCommitCount() == 0)
    }

    @Test("Moving to a new field whose old value fails to write still takes the new field's event.")
    func failedImplicitFlushKeepsTheNewEvent() async throws {
        let scratch = Scratch()
        let sink = FlakySink(recordFailures: 1)
        let session = try await session(
            scratch, sink, allowing: ["com.example.terminal", "com.example.browser"])
        _ = try await session.handle(.keystroke("git status", at: start), in: terminal)
        _ = try await session.handle(.keystroke("example.com", at: start), in: browser)
        #expect(try await session.handle(.returnPressed(at: start), in: browser) == .recorded("example.com"))
        #expect(await sink.recorded == ["git status", "example.com"])
    }

    @Test("Held values are bounded, and forgetting an application drops its own.")
    func heldValuesAreBoundedAndForgotten() async throws {
        let scratch = Scratch()
        let limit = CaptureSession.unwrittenCommitLimit
        let sink = FlakySink(recordFailures: .max)
        let session = try await session(
            scratch, sink, allowing: ["com.example.terminal"], policy: only(.returnPressed))
        for index in 0...limit {
            _ = try await session.handle(.keystroke("echo \(index)", at: start), in: terminal)
            _ = try? await session.handle(.returnPressed(at: start), in: terminal)
        }
        #expect(await session.unwrittenCommitCount() == limit)
        await session.forgetLearned(from: "com.example.terminal")
        #expect(await session.unwrittenCommitCount() == 0)
    }

    @Test("A failed idle write does not lock the detector; the next eligible tick retries it.")
    func failedIdleIsRetriedByTheNextTick() async throws {
        let scratch = Scratch()
        let sink = FlakySink(recordFailures: 1)
        let session = try await session(scratch, sink, allowing: ["com.example.terminal"])
        _ = try await session.handle(.keystroke("git status", at: start), in: terminal)

        let firstTick = start.addingTimeInterval(CommitDetector.idleInterval)
        await #expect(throws: FlakySinkError.self) {
            _ = try await session.handle(.tick(at: firstTick), in: terminal)
        }
        #expect(await sink.recorded.isEmpty)

        let secondTick = firstTick.addingTimeInterval(CommitDetector.idleInterval)
        let outcome = try await session.handle(.tick(at: secondTick), in: terminal)
        #expect(outcome == .recorded("git status"))
        #expect(await sink.recorded == ["git status"])
    }

    @Test("After a recovered idle write, a Return of the same value is not recorded twice.")
    func returnAfterRecoveredIdleIsNotARecord() async throws {
        let scratch = Scratch()
        let sink = FlakySink(recordFailures: 1)
        let session = try await session(scratch, sink, allowing: ["com.example.terminal"])
        _ = try await session.handle(.keystroke("git status", at: start), in: terminal)

        let firstTick = start.addingTimeInterval(CommitDetector.idleInterval)
        await #expect(throws: FlakySinkError.self) {
            _ = try await session.handle(.tick(at: firstTick), in: terminal)
        }
        let secondTick = firstTick.addingTimeInterval(CommitDetector.idleInterval)
        #expect(try await session.handle(.tick(at: secondTick), in: terminal) == .recorded("git status"))
        #expect(
            try await session.handle(.returnPressed(at: secondTick.addingTimeInterval(1)), in: terminal)
                == .nothing)
        #expect(await sink.recorded == ["git status"])
    }

    @Test("A failing supersede leaves the session coherent, so a later tick still retires the draft.")
    func failedSupersedeKeepsStateCoherent() async throws {
        let scratch = Scratch()
        let sink = FlakySink(recordFailures: 0, supersedeFailures: 1)
        let session = try await session(scratch, sink, allowing: ["com.example.terminal"])
        let field = FieldReading(bundleIdentifier: "com.example.terminal", role: "AXTextArea")

        _ = try await session.handle(.keystroke("git pu", at: start), in: field)
        let firstIdle = start.addingTimeInterval(CommitDetector.idleInterval)
        #expect(try await session.handle(.tick(at: firstIdle), in: field) == .recorded("git pu"))
        _ = try await session.handle(.keystroke("git push", at: firstIdle.addingTimeInterval(1)), in: field)
        let supersedeTick = firstIdle.addingTimeInterval(1 + CommitDetector.idleInterval)
        await #expect(throws: FlakySinkError.self) {
            _ = try await session.handle(.tick(at: supersedeTick), in: field)
        }
        #expect(await sink.recorded == ["git pu"])

        let retryTick = supersedeTick.addingTimeInterval(CommitDetector.idleInterval)
        let outcome = try await session.handle(.tick(at: retryTick), in: field)
        #expect(outcome == .recorded("git push"))
        #expect(await sink.recorded == ["git pu", "git push"])
        #expect(await sink.superseded.map(\.text) == ["git pu"])
    }

    @Test("A failed acceptance write is retried by the next event, once.")
    func failedAcceptanceIsRetried() async throws {
        let scratch = Scratch()
        let sink = FlakySink(recordFailures: 1)
        let session = try await session(scratch, sink, allowing: ["com.example.terminal"])
        await #expect(throws: FlakySinkError.self) {
            _ = try await session.accepted("git status", in: terminal, at: start)
        }
        #expect(await session.unwrittenAcceptanceCount() == 1)
        _ = try await session.handle(.tick(at: start.addingTimeInterval(1)), in: terminal)
        #expect(await sink.recorded == ["git status"])
        #expect(await sink.accepted == ["git status"])
        #expect(await session.unwrittenAcceptanceCount() == 0)
    }

    @Test("A failed acceptance count is retried without recording its line twice.")
    func failedCountIsRetriedAlone() async throws {
        let scratch = Scratch()
        let sink = FlakySink(acceptFailures: 2)
        let session = try await session(scratch, sink, allowing: ["com.example.terminal"])
        await #expect(throws: FlakySinkError.self) {
            _ = try await session.accepted("git status", in: terminal, at: start)
        }
        _ = try await session.handle(.tick(at: start.addingTimeInterval(1)), in: terminal)
        #expect(await session.unwrittenAcceptanceCount() == 1)
        #expect(
            try await session.accepted("git push", in: terminal, at: start.addingTimeInterval(2))
                == .recorded("git push"))
        #expect(await sink.recorded == ["git status", "git push"])
        #expect(await sink.accepted == ["git status", "git push"])
    }

    @Test("A failed undo retraction is retried by the next event.")
    func failedRetractionIsRetried() async throws {
        let scratch = Scratch()
        let sink = FlakySink(retractFailures: 1)
        let session = try await session(scratch, sink, allowing: ["com.example.terminal"])
        _ = try await session.accepted("git status", over: "git", in: terminal, at: start)

        _ = try await session.handle(
            .keystroke("git", at: start.addingTimeInterval(1)), in: terminal)
        #expect(await sink.accepted == ["git status"])
        #expect(await session.unwrittenRetractionCount() == 1)

        _ = try await session.handle(.tick(at: start.addingTimeInterval(2)), in: terminal)
        #expect(await sink.accepted.isEmpty)
        #expect(await session.unwrittenRetractionCount() == 0)
    }

    @Test("Held acceptances are bounded, and forgetting an application drops its own.")
    func heldAcceptancesAreBoundedAndForgotten() async throws {
        let scratch = Scratch()
        let limit = CaptureSession.unwrittenAcceptanceLimit
        let sink = FlakySink(acceptFailures: 10 * limit)
        let session = try await session(scratch, sink, allowing: ["com.example.terminal"])
        for index in 0..<(limit + 3) {
            _ = try? await session.accepted("line \(index)", in: terminal, at: start)
        }
        #expect(await session.unwrittenAcceptanceCount() == limit)
        await session.forgetLearned(from: "com.example.terminal")
        #expect(await session.unwrittenAcceptanceCount() == 0)
    }
}

/// Return alone finishes a field in the example terminal, and every ending finishes one elsewhere.
private let returnOnlyInTerminal = CommitPolicy { reason, reading in
    reason == .returnPressed || reading.bundleIdentifier != "com.example.terminal"
}

@Suite("A field's identity across readings")
struct CaptureSessionFieldIdentityTests {
    @Test("A title mark appearing mid-line is the same field, so nothing is committed early.")
    func titleMarkIsNotAFocusChange() async throws {
        let scratch = Scratch()
        let recorder = Recorder()
        let session = try await session(scratch, recorder, allowing: ["com.example.notes"])
        let clean = FieldReading(
            bundleIdentifier: "com.example.notes", role: "AXTextArea", windowTitle: "Groceries")
        let edited = FieldReading(
            bundleIdentifier: "com.example.notes", role: "AXTextArea", windowTitle: "Groceries •")
        #expect(clean.surface == edited.surface)
        #expect(try await session.handle(.keystroke("buy", at: start), in: clean) == .nothing)
        let outcome = try await session.handle(
            .keystroke("buy milk", at: start.addingTimeInterval(1)), in: edited)
        #expect(outcome == .nothing)
        #expect(await recorder.texts.isEmpty)
        let finished = try await session.handle(.returnPressed(at: start.addingTimeInterval(2)), in: edited)
        #expect(finished == .recorded("buy milk"))
    }

    @Test("An acceptance arriving while a finished line is still being written follows that line.")
    func acceptanceDuringWriteFollowsIt() async throws {
        let scratch = Scratch()
        let sink = GatedSink()
        let session = try await session(scratch, sink, allowing: ["com.example.terminal"])
        _ = try await session.handle(.keystroke("hello", at: start), in: terminal)
        let typed = Task { try await session.handle(.returnPressed(at: start), in: terminal) }
        while !(await sink.isWaiting) { await Task.yield() }
        _ = try await session.accepted("world", in: terminal, at: start)
        await sink.release()
        _ = try await typed.value
        #expect(await sink.recorded.map(\.previous) == [nil, "hello"])
    }
}

/// Which retry queue a reentrancy test drives.
enum HeldQueue: CaseIterable, Sendable { case commits, acceptances }

@Suite("Retrying held writes while the session is re-entered")
struct CaptureSessionRetryReentrancyTests {
    /// A session with one entry held in the given queue, and the sink whose next record will wait.
    private func holdingOne(
        _ queue: HeldQueue, _ scratch: borrowing Scratch
    ) async throws -> (CaptureSession, RetryGateSink) {
        let sink = RetryGateSink()
        let session = try await session(
            scratch, sink, allowing: ["com.example.terminal"], policy: only(.returnPressed))
        switch queue {
        case .commits:
            _ = try await session.handle(.keystroke("git status", at: start), in: terminal)
            _ = try? await session.handle(.returnPressed(at: start), in: terminal)
            #expect(await session.unwrittenCommitCount() == 1)
        case .acceptances:
            _ = try? await session.accepted("git status", in: terminal, at: start)
            #expect(await session.unwrittenAcceptanceCount() == 1)
        }
        return (session, sink)
    }

    @Test(
        "Forgetting everything while a held write is suspended leaves the retry nothing to remove.",
        arguments: HeldQueue.allCases, [false, true])
    func forgetDuringRetry(queue: HeldQueue, resumeFailing: Bool) async throws {
        let scratch = Scratch()
        let (session, sink) = try await holdingOne(queue, scratch)
        let retry = Task { try await session.handle(.tick(at: start.addingTimeInterval(1)), in: terminal) }
        while !(await sink.isWaiting) { await Task.yield() }
        try await session.forgetEverythingLearned()
        await sink.release(failing: resumeFailing)
        _ = try await retry.value
        #expect(await session.unwrittenCommitCount() == 0)
        #expect(await session.unwrittenAcceptanceCount() == 0)
    }

    @Test(
        "A second retry arriving while the first is suspended does not write the held entry again.",
        arguments: HeldQueue.allCases)
    func concurrentRetryWritesOnce(queue: HeldQueue) async throws {
        let scratch = Scratch()
        let (session, sink) = try await holdingOne(queue, scratch)
        let retry = Task { try await session.handle(.tick(at: start.addingTimeInterval(1)), in: terminal) }
        while !(await sink.isWaiting) { await Task.yield() }
        _ = try await session.handle(.tick(at: start.addingTimeInterval(2)), in: terminal)
        #expect(await sink.recorded.isEmpty)
        await sink.release(failing: false)
        _ = try await retry.value
        #expect(await sink.recorded == ["git status"])
        #expect(await session.unwrittenCommitCount() == 0)
        #expect(await session.unwrittenAcceptanceCount() == 0)
    }

    /// Dictates `inserted` into an empty line of `field`, types `replacement` over `old` and presses Return.
    private func dictateAndEdit(
        _ inserted: String, replacing old: String, with replacement: String, in field: FieldReading,
        allowing: [String]
    ) async throws -> [EditedSpan] {
        let scratch = Scratch()
        let recorder = Recorder()
        let session = try await session(scratch, recorder, allowing: allowing)
        _ = try await session.handle(.keystroke("", at: start), in: field)
        for event in CaptureEvent.marking([.keystroke(inserted, at: start)], insertedAt: start) {
            _ = try await session.handle(event, in: field)
        }
        let edited = inserted.replacingOccurrences(of: old, with: replacement)
        _ = try await session.handle(.typed(replacement, at: start), in: field)
        _ = try await session.handle(.keystroke(edited, at: start), in: field)
        #expect(try await session.handle(.returnPressed(at: start), in: field) == .nothing)
        #expect(await recorder.texts.isEmpty)
        return await recorder.edits
    }

    @Test("A word replaced inside dictated text reaches the sink as one edit.")
    func anEditInsideDictationReachesTheSink() async throws {
        let chat = FieldReading(bundleIdentifier: "com.example.chat", role: "AXTextArea")
        let edits = try await dictateAndEdit(
            "see you on tuesday", replacing: "tuesday", with: "thursday", in: chat,
            allowing: ["com.example.chat"])
        #expect(edits == [EditedSpan(position: 3, old: ["tuesday"], new: ["thursday"])])
    }

    @Test("An edit in an application not yet asked about is heard, since learning is on by default.")
    func anEditInAnUnaskedApplicationIsHeard() async throws {
        let chat = FieldReading(bundleIdentifier: "com.example.chat", role: "AXTextArea")
        let edits = try await dictateAndEdit(
            "see you on tuesday", replacing: "tuesday", with: "thursday", in: chat, allowing: [])
        #expect(edits == [EditedSpan(position: 3, old: ["tuesday"], new: ["thursday"])])
    }

    @Test("An edit in a secure field, an opted-out application or of a secret shape is never heard.")
    func refusedEditsAreNotHeard() async throws {
        let chat = FieldReading(bundleIdentifier: "com.example.chat", role: "AXTextArea")
        let secure = FieldReading(
            bundleIdentifier: "com.example.chat", role: "AXTextField", subrole: "AXSecureTextField")
        #expect(
            try await dictateAndEdit(
                "my code is tuesday", replacing: "tuesday", with: "thursday", in: secure,
                allowing: ["com.example.chat"]
            ).isEmpty)
        let declining = Scratch()
        let recorder = Recorder()
        let session = try await session(declining, recorder)
        try await session.record(.declined, for: "com.example.chat")
        _ = try await session.handle(.keystroke("", at: start), in: chat)
        let dictated = [CaptureEvent.keystroke("see you on tuesday", at: start)]
        for event in CaptureEvent.marking(dictated, insertedAt: start) {
            _ = try await session.handle(event, in: chat)
        }
        _ = try await session.handle(.typed("thursday", at: start), in: chat)
        _ = try await session.handle(.keystroke("see you on thursday", at: start), in: chat)
        _ = try await session.handle(.returnPressed(at: start), in: chat)
        #expect(await recorder.edits.isEmpty)
        #expect(
            try await dictateAndEdit(
                "the key is tuesday", replacing: "tuesday", with: "ASIAY34FZKBOKMUTVV7A", in: chat,
                allowing: ["com.example.chat"]
            ).isEmpty)
    }
}
