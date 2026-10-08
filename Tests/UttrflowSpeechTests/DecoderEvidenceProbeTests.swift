// Measures what the pinned WhisperKit says about a doubtful token. See Docs/decoder-evidence.md.
import CoreML
import Foundation
import Synchronization
import Testing
import UttrflowCore
import WhisperKit

@testable import UttrflowSpeech

/// One decoder step as a logits filter saw it, with what reading it cost.
struct EvidenceStep: Sendable {
    /// How many tokens the decoder held when it asked for this step.
    let tokenCount: Int
    /// The `k` likeliest token ids with their log-probabilities over the whole vocabulary, likeliest first.
    let leaders: [(token: Int, logProb: Float)]
    /// The no-speech token's log-probability at this step.
    let noSpeechLogProb: Float
    /// Wall time spent reading the evidence, the cost a re-ranker would add per step.
    let cost: Duration
}

/// A logits filter that changes nothing and records the evidence every decoder step offers.
final class EvidenceRecorder: LogitsFiltering, Sendable {
    let k: Int
    let noSpeechToken: Int
    private let steps = Mutex<[EvidenceStep]>([])

    init(k: Int, noSpeechToken: Int) {
        self.k = k
        self.noSpeechToken = noSpeechToken
    }

    var recorded: [EvidenceStep] { steps.withLock { $0 } }

    func filterLogits(_ logits: MLMultiArray, withTokens tokens: [Int]) -> MLMultiArray {
        let clock = ContinuousClock()
        let started = clock.now
        let scores = TokenLeaders.scores(of: logits)
        let (leaders, noSpeech) = Self.evidence(in: scores, k: k, noSpeechToken: noSpeechToken)
        let step = EvidenceStep(
            tokenCount: tokens.count, leaders: leaders, noSpeechLogProb: noSpeech,
            cost: started.duration(to: clock.now))
        steps.withLock { $0.append(step) }
        return logits
    }

    /// The `k` leaders and the no-speech token, each as a log-probability under one log-sum-exp.
    static func evidence(
        in scores: [Float], k: Int, noSpeechToken: Int
    ) -> (leaders: [(token: Int, logProb: Float)], noSpeech: Float) {
        guard let normaliser = TokenLeaders.normaliser(of: scores) else { return ([], -.infinity) }
        let leaders = TokenLeaders.leaders(in: scores, k: k)
        let noSpeech = noSpeechToken < scores.count ? scores[noSpeechToken] - normaliser : -.infinity
        return (leaders, noSpeech)
    }
}

@Suite("Reading token evidence out of WhisperKit")
struct EvidenceRecorderTests {
    @Test("the leaders are the k largest scores, as log-probabilities over every finite score")
    func leadersAreTheLargest() throws {
        let scores: [Float] = [0, 2, -.infinity, 1, 3]
        let (leaders, noSpeech) = EvidenceRecorder.evidence(in: scores, k: 2, noSpeechToken: 3)
        let normaliser = log(exp(Float(0)) + exp(2) + exp(1) + exp(3))

        #expect(leaders.map(\.token) == [4, 1])
        #expect(abs(leaders[0].logProb - (3 - normaliser)) < 1e-5)
        #expect(abs(noSpeech - (1 - normaliser)) < 1e-5)
    }

    @Test("a filter that only records hands the decoder back the logits it was given")
    func recordingChangesNothing() throws {
        let logits = try MLMultiArray(shape: [1, 1, 4], dataType: .float32)
        for index in 0..<4 { logits[index] = NSNumber(value: Float(index)) }
        let recorder = EvidenceRecorder(k: 2, noSpeechToken: 0)

        let returned = recorder.filterLogits(logits, withTokens: [7, 8])

        #expect(returned === logits)
        #expect(recorder.recorded.map(\.tokenCount) == [2])
        #expect(recorder.recorded.first?.leaders.map(\.token) == [3, 2])
    }
}

/// Where the probe reads its clips and its model from.
enum ProbeInputs {
    static let audioPaths =
        ProcessInfo.processInfo.environment["UTTRFLOW_PROBE_AUDIO"]?
        .split(separator: ",").map(String.init) ?? []
    static let modelFolder = FileSystemSpeechModelStore(
        root: FileSystemSpeechModelStore.defaultRoot(), download: { _, _, _, _ in }
    ).location(of: .default)
    static var isRunnable: Bool {
        !audioPaths.isEmpty && FileManager.default.fileExists(atPath: modelFolder.path)
    }
}

/// The real model on real audio, run only when `UTTRFLOW_PROBE_AUDIO` names files and the model is installed.
@Suite(
    "Probing WhisperKit's token evidence on the shipping model",
    .enabled(if: ProbeInputs.isRunnable, "set UTTRFLOW_PROBE_AUDIO and install the shipping model"))
struct DecoderEvidenceProbe {
    @Test("prints, per clip, the decode cost against the cost of reading top-k and no-speech at every step")
    func probe() async throws {
        let kit = try await WhisperKit(
            WhisperKitConfig(
                modelFolder: ProbeInputs.modelFolder.path, tokenizerFolder: ProbeInputs.modelFolder,
                verbose: false,
                logLevel: .error, prewarm: true, load: true, download: false))
        kit.textDecoder = LanguageHeldDecoder(wrapping: kit.textDecoder, languages: LanguageCode.transcribed)
        let tokenizer = try #require(kit.tokenizer)
        for path in ProbeInputs.audioPaths {
            let recorder = EvidenceRecorder(k: 5, noSpeechToken: tokenizer.specialTokens.noSpeechToken)
            kit.textDecoder.logitsFilters = [recorder]
            let samples = try AudioProcessor.loadAudioAsFloatArray(fromPath: path)
            let results = try await kit.transcribe(
                audioArray: samples, decodeOptions: VocabularyPrompt.decodingOptions(languageHint: .english))
            let segments = results.flatMap(\.segments)
            // WhisperKit writes a constant here, which is the fact the doc rests on.
            #expect(segments.allSatisfy { $0.noSpeechProb == 0 })
            // The chosen token and, through `EvidenceSampler`, up to its five leaders beside it.
            #expect(segments.allSatisfy { $0.tokenLogProbs.allSatisfy { (1...6).contains($0.count) } })
            Self.report(path: path, results: results, steps: recorder.recorded, tokenizer: tokenizer)
        }
    }

    /// Prints the costs, the first step's no-speech probability and the five lowest-margin steps.
    static func report(
        path: String, results: [TranscriptionResult], steps: [EvidenceStep], tokenizer: any WhisperTokenizer
    ) {
        let timings = results.first?.timings
        let predictions = timings?.decodingPredictions ?? 0
        let loops = max(timings?.totalDecodingLoops ?? 0, 1)
        let costs = steps.map { $0.cost / .milliseconds(1) }.sorted()
        let median = costs.isEmpty ? 0 : costs[costs.count / 2]
        let worst = costs.last ?? 0
        print("PROBE \(URL(fileURLWithPath: path).lastPathComponent): \(results.map(\.text).joined())")
        print(
            String(
                format: "PROBE steps %d, model %.2f ms/step, evidence median %.3f ms worst %.3f ms",
                steps.count, predictions * 1000 / loops, median, worst))
        if let first = steps.first {
            print(String(format: "PROBE first-step no-speech p=%.4f", exp(first.noSpeechLogProb)))
        }
        let doubtful = steps.filter { $0.leaders.count > 1 }
            .sorted { margin($0) < margin($1) }.prefix(5)
        for step in doubtful {
            let rivals = step.leaders.map {
                "\(tokenizer.decode(tokens: [$0.token]))=" + String(format: "%.2f", $0.logProb)
            }
            let gap = String(format: "%.2f", margin(step))
            print("PROBE margin \(gap) at \(step.tokenCount): \(rivals.joined(separator: " | "))")
        }
    }

    /// The log-probability gap between the leader and the runner-up.
    static func margin(_ step: EvidenceStep) -> Float {
        step.leaders[0].logProb - step.leaders[1].logProb
    }
}
