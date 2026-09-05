// Tests the transcription runner and its metrics recorder.
import Foundation
import UttrflowCore
import Synchronization
import Testing

@testable import UttrflowEval

@Suite("Transcription runner")
struct TranscriptionRunnerTests {
    private func passage(
        _ id: String, language: TranscriptionCase.Language = .english,
        stressor: TranscriptionCase.Stressor = .everyday, text: String = "the build passed ship it"
    ) -> TranscriptionCase {
        TranscriptionCase(id: id, language: language, stressor: stressor, romanised: text)
    }

    private func recording(_ passage: TranscriptionCase) -> RecordedPassage {
        RecordedPassage(
            passage: passage, recordedAt: Date(timeIntervalSince1970: 0), durationSeconds: 4,
            sampleRate: 16_000)
    }

    private func timings(_ seconds: Double, succeeded: Bool = true) -> [StageMeasurement] {
        [.init(stage: .transcription, duration: .seconds(seconds), succeeded: succeeded)]
    }

    @Test("scores every recording in the order it was given")
    func runsTheCorpus() async {
        let recordings = [recording(passage("one")), recording(passage("two"))]
        let report = await TranscriptionRunner().run(label: "test", over: recordings) { recorded in
            .transcribed(recorded.passage.romanised, stages: timings(1))
        }
        #expect(report.scores.map(\.caseID) == ["one", "two"])
        #expect(report.overall.rate == 0)
        #expect(report.label == "test")
        #expect(report.failureCounts.isEmpty)
    }

    /// Each score is handed over the moment it exists, so a long unattended run is survivable.
    @Test("hands over each score as it finishes")
    func reportsProgress() async {
        let seen = Mutex<[String]>([])
        let recordings = [recording(passage("one")), recording(passage("two"))]
        _ = await TranscriptionRunner().run(
            label: "test", over: recordings,
            onScore: { score in seen.withLock { $0.append(score.caseID) } }
        ) { recorded in .transcribed(recorded.passage.romanised, stages: []) }
        #expect(seen.withLock { $0 } == ["one", "two"])
    }

    /// An engine that returns whitespace has not thrown, so nothing else would notice.
    @Test("treats an empty transcript as having recognised nothing")
    func blankTranscript() async {
        let report = await TranscriptionRunner().run(
            label: "test", over: [recording(passage("silent"))]
        ) { _ in .transcribed("   ", stages: timings(0.2)) }
        #expect(report.failureCounts == [.recognisedNothing: 1])
        #expect(report.overall.rate == 1)
        #expect(report.scored.count == 1)
    }

    @Test("keeps an unreadable recording out of the rate but in the failures")
    func unreadableAudio() async {
        let recordings = [recording(passage("good")), recording(passage("missing"))]
        let report = await TranscriptionRunner().run(label: "test", over: recordings) { recorded in
            recorded.id == "missing"
                ? .failed(.audioUnreadable("no file"), stages: [])
                : .transcribed(recorded.passage.romanised, stages: timings(1))
        }
        #expect(report.scored.map(\.caseID) == ["good"])
        #expect(report.overall.rate == 0)
        #expect(report.failureCounts == [.audioUnreadable: 1])
    }

    @Test("carries a failure's timings, because a slow failure is still a wait")
    func failuresAreTimed() async {
        let attempt = TranscriptionRunner.Attempt.failed(
            .engineFailed("boom"), stages: timings(9, succeeded: false))
        #expect(attempt.stages.count == 1)
        let report = await TranscriptionRunner().run(
            label: "test", over: [recording(passage("slow"))]
        ) { _ in attempt }
        #expect(report.latency(for: .transcription)?.failures == 1)
        #expect(report.latency(for: .transcription)?.slowest == .seconds(9))
    }

    @Test("measures per language and per stressor as well as overall")
    func breakdowns() async {
        let recordings = [
            recording(passage("en", language: .english, stressor: .digits, text: "one two three four")),
            recording(passage("hi", language: .hindi, stressor: .everyday, text: "ek do teen chaar")),
        ]
        let report = await TranscriptionRunner().run(label: "test", over: recordings) { recorded in
            // The English passage is transcribed perfectly; the Hindi one loses a word.
            recorded.id == "en"
                ? .transcribed(recorded.passage.romanised, stages: [])
                : .transcribed("ek do teen", stages: [])
        }
        #expect(report.wordErrorRate(in: .english)?.rate == 0)
        #expect(report.wordErrorRate(in: .hindi)?.rate == 0.25)
        #expect(report.wordErrorRate(in: .hinglish) == nil)
        #expect(report.wordErrorRate(stressing: .digits)?.rate == 0)
        #expect(report.wordErrorRate(stressing: .falseStarts) == nil)
        // Eight reference words, one deleted: the corpus rate is not the mean of 0 and 25%.
        #expect(report.overall.rate == 0.125)
    }

    /// Median and slowest, exactly as the diagnostics page reports them.
    @Test("summarises latency per stage")
    func latencyPerStage() async {
        let durations = [1.0, 5.0, 3.0]
        let recordings = durations.indices.map { recording(passage("p\($0)")) }
        let report = await TranscriptionRunner().run(label: "test", over: recordings) { recorded in
            let index = recordings.firstIndex { $0.id == recorded.id } ?? 0
            return .transcribed(recorded.passage.romanised, stages: timings(durations[index]))
        }
        let latency = report.latency(for: .transcription)
        #expect(latency?.typical == .seconds(3))
        #expect(latency?.slowest == .seconds(5))
        #expect(latency?.samples == 3)
        #expect(latency?.failures == 0)
        #expect(report.latencies.map(\.stage) == [.transcription])
    }

    /// This harness reads audio off disk, so capture is named as unmeasured rather than shown as zero.
    @Test("says which stages nothing measured")
    func unmeasuredStages() async {
        let report = await TranscriptionRunner().run(
            label: "test", over: [recording(passage("one"))]
        ) { recorded in .transcribed(recorded.passage.romanised, stages: timings(1)) }
        #expect(report.latency(for: .capture) == nil)
        #expect(
            report.unmeasuredStages == [
                .capture, .correction, .transformation, .expansion, .insertion,
            ])
    }

    @Test("counts what came back in Devanagari, and what had to be transliterated")
    func scriptReporting() async {
        let hinglish = TranscriptionCase(
            id: "hinglish", language: .hinglish, stressor: .everyday,
            romanised: "kal ka deploy ho gaya", devanagari: "कल का deploy हो गया")
        let recordings = [recording(hinglish), recording(passage("en"))]
        let report = await TranscriptionRunner().run(label: "test", over: recordings) { recorded in
            recorded.id == "hinglish"
                ? .transcribed("कल का deploy हो गया", stages: [])
                : .transcribed("नमस्ते", stages: [])
        }
        #expect(report.answeredInDevanagari.map(\.caseID) == ["hinglish", "en"])
        #expect(report.upperBounds.map(\.caseID) == ["en"])
    }

    @Test("reports passages that lost a required term")
    func lostTerms() async {
        let strict = TranscriptionCase(
            id: "strict", language: .english, stressor: .properNouns,
            romanised: "tell Priya about the deploy", mustKeep: ["Priya"])
        let report = await TranscriptionRunner().run(label: "test", over: [recording(strict)]) { _ in
            .transcribed("tell Sofia about the deploy", stages: [])
        }
        #expect(report.passagesLosingRequiredTerms.map(\.lost) == [["Priya"]])
    }

    @Test("reports the rules it measured under, and notices a mixture")
    func normalisationOnTheReport() async {
        let report = await TranscriptionRunner(normaliser: TextNormaliser(rules: [.caseFolding])).run(
            label: "test", over: [recording(passage("one"))]
        ) { recorded in .transcribed(recorded.passage.romanised, stages: []) }
        #expect(report.normalisation == [.caseFolding])
        #expect(!report.hasMixedNormalisation)

        let mixed = TranscriptionReport(
            label: "mixed",
            scores: report.scores + [
                TranscriptionScorer.score("x", against: passage("other"), normaliser: .standard)
            ])
        #expect(mixed.hasMixedNormalisation)
    }

    @Test("reports nothing measured as nothing, not as a perfect score")
    func emptyReport() {
        let empty = TranscriptionReport(label: "none", scores: [])
        #expect(empty.overall.rate == nil)
        #expect(empty.latencies.isEmpty)
        #expect(empty.normalisation.isEmpty)
        #expect(empty.unmeasuredStages == PipelineStage.allCases)
    }
}

@Suite("Collecting metrics recorder")
struct CollectingMetricsRecorderTests {
    @Test("hands back what it was given, once")
    func drains() async {
        let recorder = CollectingMetricsRecorder()
        await recorder.record(.init(stage: .transcription, duration: .seconds(1), succeeded: true))
        await recorder.record(.init(stage: .transformation, duration: .seconds(2), succeeded: false))
        let drained = await recorder.drain()
        #expect(drained.map(\.stage) == [.transcription, .transformation])
        #expect(await recorder.drain().isEmpty)
    }

    /// One recorder serves a whole run, so it drains rather than accumulates.
    @Test("times a stage through the shared measuring helper")
    func measuresAStage() async throws {
        let recorder = CollectingMetricsRecorder()
        let value = try await recorder.measuring(.transcription, clock: ContinuousClock()) {
            () async throws(SpeechEngineError) -> String in "done"
        }
        #expect(value == "done")
        let measurements = await recorder.drain()
        #expect(measurements.count == 1)
        #expect(measurements.first?.succeeded == true)
    }
}
