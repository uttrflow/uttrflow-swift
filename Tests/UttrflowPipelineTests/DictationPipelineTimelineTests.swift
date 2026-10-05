// Pins working ahead and stage overlap on a virtual clock, with scripted recognition and tidy durations.
import Foundation
import Synchronization
import Testing

@testable import UttrflowCore
@testable import UttrflowPipeline
@testable import UttrflowTestSupport

// MARK: - Virtual timeline

/// One stage call as it ran on the virtual clock, numbered in the order its kind was called.
private struct StageRun: Sendable, Equatable {
    let name: String
    let start: Duration
    var end: Duration?
}

/// Every stage call the fakes made, so a test can read what ran beside what.
private final class Timeline: Sendable {
    private let runs = Mutex<[StageRun]>([])

    /// Records a stage starting now, named by its kind and how many of that kind came before it.
    func begin(_ kind: String, at now: Duration) -> Int {
        runs.withLock { runs in
            let ordinal = runs.filter { $0.name.hasPrefix(kind + " ") }.count + 1
            runs.append(StageRun(name: "\(kind) \(ordinal)", start: now))
            return runs.count - 1
        }
    }

    func end(_ index: Int, at now: Duration) {
        runs.withLock { $0[index].end = now }
    }

    /// The stages started and not yet finished, in the order they started.
    var running: Set<String> { runs.withLock { Set($0.filter { $0.end == nil }.map(\.name)) } }

    func run(_ name: String) -> StageRun? { runs.withLock { $0.first { $0.name == name } } }
}

/// A view of the shared virtual clock that logs each sleep as one call of a named stage.
private struct StageClock: Clock {
    typealias Instant = ManualClock.Instant

    let base: ManualClock
    let kind: String
    let timeline: Timeline

    var now: Instant { base.now }
    var minimumResolution: Duration { base.minimumResolution }

    func sleep(until deadline: Instant, tolerance: Duration?) async throws {
        let index = timeline.begin(kind, at: base.now.offset)
        do {
            try await base.sleep(until: deadline, tolerance: tolerance)
        } catch {
            timeline.end(index, at: base.now.offset)
            throw error
        }
        // The deadline, not the reading after waking, since the test may advance again before this resumes.
        timeline.end(index, at: deadline.offset)
    }
}

/// Recordings whose pauses fall where the windowing below cuts.
private enum Take {
    static let rate = AudioSamples.canonicalSampleRate

    static func tone(_ seconds: Double) -> [Float] {
        (0..<Int(seconds * Double(rate))).map { 0.3 * Float(sin(Double($0) * 0.07)) }
    }

    static func silence(_ seconds: Double) -> [Float] {
        [Float](repeating: 0, count: Int(seconds * Double(rate)))
    }

    /// Two pieces ended by a pause and a third the key-up ends.
    static let threePieces = AudioSamples.canonical(
        tone(1.2) + silence(0.5) + tone(1.2) + silence(0.5) + tone(0.4))
}

/// Windows short enough for a test recording to have several.
private let quick = SpeechWindowing(
    minimumLength: 1, sentencePause: 0.3, comfortableLength: 2, anyPause: 0.2, maximumLength: 5,
    minimumSpeech: 0.2)

private let recognition = Duration.milliseconds(300)
private let tidy = Duration.milliseconds(200)

/// A pipeline whose recogniser and tidier take scripted virtual time, and the clock and log that show it.
private struct Rig {
    let clock = ManualClock()
    let timeline = Timeline()
    let capture: FakeAudioCaptureEngine
    let speech: FakeSpeechEngine
    let pipeline: DictationPipeline

    init(
        audio: AudioSamples = Take.threePieces, windowing: SpeechWindowing = quick,
        heard: ScriptedSequence<Transcription, SpeechEngineError> = .successes(
            [.fixture(text: "one"), .fixture(text: "two"), .fixture(text: "three")])
    ) {
        capture = FakeAudioCaptureEngine(stopOutcome: .success(audio))
        speech = FakeSpeechEngine(
            transcribing: heard,
            takes: .slept(recognition, on: StageClock(base: clock, kind: "recognise", timeline: timeline)))
        let cleaner = FakeTranscriptCleaner(
            takes: .slept(tidy, on: StageClock(base: clock, kind: "tidy", timeline: timeline)))
        pipeline = DictationPipeline(
            capture: capture, speech: speech, cleaner: cleaner,
            context: FakeContextEngine(context: .fixture()), inserter: FakeTextInserter(), clock: clock,
            windowing: windowing, earlyPoll: .milliseconds(2))
    }

    var now: Duration { clock.now.offset }

    /// Waits, in real time, for exactly these stages to be running; a stage held back by another never shows.
    func expectRunning(
        _ names: Set<String>, sourceLocation: SourceLocation = #_sourceLocation
    ) async {
        let limit = ContinuousClock.now.advanced(by: .seconds(10))
        while timeline.running != names, ContinuousClock.now < limit {
            try? await Task.sleep(for: .milliseconds(1))
        }
        #expect(timeline.running == names, sourceLocation: sourceLocation)
    }

    /// Moves the virtual clock, waking every stage due by then.
    func advance(by duration: Duration) {
        clock.advance(by: duration)
    }

    func start(_ name: String) -> Duration? { timeline.run(name)?.start }
}

// MARK: - Tests

@Suite("Dictation pipeline: work ahead and overlap on a virtual clock", .timeLimit(.minutes(1)))
struct DictationPipelineTimelineTests {
    /// Works ahead through both paused pieces, ending with the second piece's tidy under way.
    private func workAheadThroughSecondRecognition(_ rig: Rig) async {
        await rig.capture.setCaptured(Take.threePieces)
        await rig.pipeline.startRecording()
        await rig.expectRunning(["recognise 1"])
        rig.advance(by: recognition)
        // While the key is held the next recognition waits for this tidy (#5046).
        await rig.expectRunning(["tidy 1"])
        rig.advance(by: tidy)
        await rig.expectRunning(["recognise 2"])
        #expect(rig.start("recognise 2") == recognition + tidy)
        rig.advance(by: recognition)
        await rig.expectRunning(["tidy 2"])
    }

    @Test("while the key is held, the next recognition runs beside the last piece's tidy")
    func keyHeldRecognitionOverlapsTheTidy() async throws {
        let rig = Rig()
        await rig.capture.setCaptured(Take.threePieces)
        await rig.pipeline.startRecording()
        await rig.expectRunning(["recognise 1"])
        rig.advance(by: recognition)
        await withKnownIssue("#5046: the next recognition waits for the tidy") {
            await rig.expectRunning(["tidy 1", "recognise 2"])
        }
        await rig.pipeline.cancel()
        rig.advance(by: recognition + tidy)
    }

    @Test("with the work done ahead, the wait after key-up is the final piece's recognition and tidy only")
    func waitAfterKeyUpIsTheFinalPiece() async throws {
        let rig = Rig()
        await workAheadThroughSecondRecognition(rig)
        rig.advance(by: tidy)
        await rig.expectRunning([])

        let keyUp = rig.now
        let finishing = Task { await rig.pipeline.finishRecording() }
        await rig.expectRunning(["recognise 3"])
        #expect(rig.start("recognise 3") == keyUp)
        rig.advance(by: recognition)
        await rig.expectRunning(["tidy 3"])
        rig.advance(by: tidy)
        await finishing.value

        #expect(rig.now - keyUp == recognition + tidy, "no earlier piece adds to the wait")
        #expect(await rig.speech.transcribeCalls.events.count == 3)
    }

    @Test("a key-up mid-tidy starts the last recognition beside that tidy rather than after it")
    func keyUpMidTidyDoesNotWaitForIt() async throws {
        let rig = Rig()
        await workAheadThroughSecondRecognition(rig)

        let keyUp = rig.now
        let finishing = Task { await rig.pipeline.finishRecording() }
        // Waiting on the early tidy at hand-off would keep the last recognition from starting here.
        await rig.expectRunning(["tidy 2", "recognise 3"])
        #expect(rig.start("recognise 3") == keyUp)
        rig.advance(by: tidy)
        await rig.expectRunning(["recognise 3"])
        rig.advance(by: recognition - tidy)
        await rig.expectRunning(["tidy 3"])
        rig.advance(by: tidy)
        await finishing.value

        #expect(rig.now - keyUp == recognition + tidy)
        #expect(await rig.speech.transcribeCalls.events.count == 3)
    }

    @Test("a key-up mid-recognition finishes that piece, then tidies it beside the last recognition")
    func keyUpMidRecognitionOverlapsTheRest() async throws {
        let rig = Rig()
        await rig.capture.setCaptured(Take.threePieces)
        await rig.pipeline.startRecording()
        await rig.expectRunning(["recognise 1"])
        rig.advance(by: recognition)
        await rig.expectRunning(["tidy 1"])
        rig.advance(by: tidy)
        await rig.expectRunning(["recognise 2"])

        let keyUp = rig.now
        let finishing = Task { await rig.pipeline.finishRecording() }
        rig.advance(by: recognition)
        // The drained piece's tidy and the last recognition start together, not one after the other.
        await rig.expectRunning(["tidy 2", "recognise 3"])
        #expect(rig.start("tidy 2") == keyUp + recognition)
        #expect(rig.start("recognise 3") == keyUp + recognition)
        rig.advance(by: tidy)
        await rig.expectRunning(["recognise 3"])
        rig.advance(by: recognition - tidy)
        await rig.expectRunning(["tidy 3"])
        rig.advance(by: tidy)
        await finishing.value

        #expect(rig.now - keyUp == recognition + recognition + tidy)
        #expect(await rig.speech.transcribeCalls.events.count == 3)
    }

    @Test("a failed early piece leaves the next one to work ahead and is recognised again at key-up")
    func failedEarlyPieceKeepsWorkingAhead() async throws {
        let rig = Rig(
            heard: ScriptedSequence(
                .failure(.transcriptionFailed(description: "scripted")),
                then: [
                    .success(.fixture(text: "two")), .success(.fixture(text: "one")),
                    .success(.fixture(text: "three")),
                ]))
        await rig.capture.setCaptured(Take.threePieces)
        await rig.pipeline.startRecording()
        await rig.expectRunning(["recognise 1"])
        rig.advance(by: recognition)
        // Nothing to tidy, so the second piece is recognised straight after the failure.
        await rig.expectRunning(["recognise 2"])
        #expect(rig.start("recognise 2") == recognition)
        rig.advance(by: recognition)
        await rig.expectRunning(["tidy 1"])
        rig.advance(by: tidy)
        await rig.expectRunning([])

        let keyUp = rig.now
        let finishing = Task { await rig.pipeline.finishRecording() }
        // The failed piece is recognised again first.
        await rig.expectRunning(["recognise 3"])
        #expect(rig.start("recognise 3") == keyUp)
        while rig.timeline.run("tidy 3")?.end == nil {
            rig.advance(by: .milliseconds(100))
            try? await Task.sleep(for: .milliseconds(5))
        }
        await finishing.value

        #expect(rig.start("recognise 4") ?? .zero >= keyUp + recognition)
        withKnownIssue("#5046: the release pass recognises the last piece after the retried piece's tidy") {
            #expect(rig.start("recognise 4") == keyUp + recognition)
        }
        #expect(await rig.speech.transcribeCalls.events.count == 4)
    }

    @Test("ninety seconds with no pause is cut at thirty while the key is held")
    func pauseFreeInputIsCutAtTheWindowLimit() async throws {
        let audio = AudioSamples.canonical(Take.tone(90))
        let rig = Rig(audio: audio, windowing: .standard)
        await rig.capture.setCaptured(audio)
        await rig.pipeline.startRecording()
        for piece in 1...3 {
            await rig.expectRunning(["recognise \(piece)"])
            rig.advance(by: recognition)
            await rig.expectRunning(["tidy \(piece)"])
            rig.advance(by: tidy)
        }
        let seconds = await rig.speech.transcribeCalls.events.map {
            Double($0.audio.samples.count) / Double(AudioSamples.canonicalSampleRate)
        }
        // The first piece is cut early; every later one runs to the thirty-second limit.
        #expect(seconds.count == 3)
        #expect(seconds.allSatisfy { $0 <= 30 })
        #expect(seconds.dropFirst().allSatisfy { $0 > 29 })
        await rig.pipeline.cancel()
    }
}
