// The `relisten` command: two ways to listen again to one doubtful word, compared on synthetic clips.
import ArgumentParser
import CoreML
private import Foundation
private import UttrflowAudio
import UttrflowEval
private import UttrflowSpeech
import WhisperKit

/// Scores each homophone slot by forced decoding in the full window and by a cropped re-decode. See `Docs/relisten-probe.md`.
struct RelistenProbe: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "relisten",
        abstract: "Compare full-window forced scoring with a cropped re-decode of one doubtful word."
    )

    @Option(name: .long, help: "Where the generated clips are written.")
    var clipsPath = ".uttrflow-eval/relisten-clips"

    @Option(name: .long, parsing: .upToNextOption, help: "Synthetic voices that read the sentences.")
    var voices = ["Samantha", "Daniel", "Karen"]

    @Option(name: .long, parsing: .upToNextOption, help: "Speaking rates, in words per minute.")
    var rates = [175, 230]

    @Option(name: .long, help: "Audio kept either side of the word in the cropped decode, in seconds.")
    var padding: Float = 0.2

    @Option(name: .long, help: "Greedy tokens after the candidate that count towards its forced score.")
    var following = 3

    @Flag(name: .long, help: "Print each clip's scores.")
    var list = false

    @Option(name: .long, help: "Stop after this many pairs, for a reduced run.")
    var limit: Int?

    func run() async throws {
        let model = SpeechModel.default
        let folder = FileSystemSpeechModelStore.whisperKit().location(of: model)
        let kit = try await WhisperKit(
            WhisperKitConfig(
                model: model.variant, modelFolder: folder.path, tokenizerFolder: folder, verbose: false,
                logLevel: .error, load: true, download: false))
        let recorder = RecordingDecoder(wrapping: kit.textDecoder)
        kit.textDecoder = recorder
        guard let tokenizer = kit.tokenizer else {
            throw CleanExit.message("No tokenizer in \(folder.path).")
        }
        let directory = URL(fileURLWithPath: clipsPath)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let listener = Listener(
            kit: kit, recorder: recorder, tokenizer: tokenizer, following: following, list: list)

        let pairs = Array(
            (HomophoneConfidence.programmerPairs + HomophoneConfidence.ordinaryPairs).prefix(limit ?? .max))
        var outcomes: [RelistenOutcome] = []
        for pair in pairs {
            for voice in voices {
                for rate in rates {
                    let samples = try clip(pair.sentence, voice: voice, rate: rate, in: directory)
                    if let outcome = try await listener.outcome(of: pair, in: samples, padding: padding) {
                        outcomes.append(outcome)
                    }
                }
            }
        }
        print(RelistenReport(outcomes: outcomes).markdown)
    }

    /// The sentence read by `voice` at `rate`, synthesised at 16 kHz once and reused.
    private func clip(_ text: String, voice: String, rate: Int, in directory: URL) throws -> [Float] {
        let url = directory.appendingPathComponent(
            "\(voice)-\(rate)-\(String(text.hashValueStable, radix: 16)).wav")
        if !FileManager.default.fileExists(atPath: url.path) {
            let say = Process()
            say.executableURL = URL(fileURLWithPath: "/usr/bin/say")
            say.arguments = ["-v", voice, "-r", "\(rate)", "-o", url.path, "--data-format=LEF32@16000", text]
            try say.run()
            say.waitUntilExit()
            guard say.terminationStatus == 0 else {
                throw CleanExit.message("say failed for voice \(voice).")
            }
        }
        return try AudioFileReader.read(contentsOf: url).samples
    }
}

/// One slot: what the free decode wrote there, and what each re-listening shape chose and cost.
struct RelistenOutcome {
    let freeRight: Bool
    /// Forced log-likelihood of the meant word minus the other, over the candidate and the following tokens.
    let forcedDifference: Float
    /// Log-probability of the meant word's first token minus the other's, at the step that chooses it.
    let marginDifference: Float
    let croppedRight: Bool
    let forcedSeconds: Double
    let croppedSeconds: Double
}

/// Runs the free decode, the two forced decodes and the cropped decode for one clip.
struct Listener {
    let kit: WhisperKit
    let recorder: RecordingDecoder
    let tokenizer: any WhisperTokenizer
    let following: Int
    let list: Bool

    func outcome(of pair: HomophonePair, in samples: [Float], padding: Float) async throws -> RelistenOutcome?
    {
        let words = pair.sentence.split(separator: " ").map(String.init)
        guard let slot = words.firstIndex(of: pair.meant) else { return nil }
        let free = try await decode(samples, options: options(wordTimestamps: true))
        let heard = free.flatMap { $0.allWords }
        // Only a slot the free decode kept, at the same word index, can be cropped by its timing.
        guard heard.count == words.count else { return nil }
        let freeRight = normalised(heard[slot].word) == pair.meant

        let before = words[..<slot].joined(separator: " ")
        let after = words[(slot + 1)...].joined(separator: " ")
        let started = Date()
        let right = try await forcedScore(before: before, candidate: pair.meant, after: after)
        let wrong = try await forcedScore(before: before, candidate: pair.other, after: after)
        let forcedSeconds = Date().timeIntervalSince(started) / 2

        let rate = Float(WhisperKit.sampleRate)
        let start = max(0, Int((heard[slot].start - padding) * rate))
        let end = min(samples.count, Int((heard[slot].end + padding) * rate))
        let prompt = before.isEmpty ? nil : text(" " + before)
        let cropStarted = Date()
        let cropped = try await decode(Array(samples[start..<end]), options: options(prompt: prompt))
        let croppedSeconds = Date().timeIntervalSince(cropStarted)
        let croppedWords = cropped.map(\.text).joined(separator: " ").split(separator: " ").map {
            normalised(String($0))
        }

        if list {
            print(
                "\(pair.meant)/\(pair.other) free \(heard[slot].word) forced \(right.total - wrong.total) "
                    + "margin \(right.first - wrong.first) cropped \(croppedWords)")
        }
        return RelistenOutcome(
            freeRight: freeRight, forcedDifference: right.total - wrong.total,
            marginDifference: right.first - wrong.first, croppedRight: croppedWords.contains(pair.meant),
            forcedSeconds: forcedSeconds, croppedSeconds: croppedSeconds)
    }

    /// The forced log-likelihood of `candidate` and the next `following` tokens of the sentence, and of its first token.
    private func forcedScore(
        before: String, candidate: String, after: String
    ) async throws -> (total: Float, first: Float) {
        let lead = text(before.isEmpty ? "" : " " + before)
        let scored = text(" " + candidate)
        let tail = Array(text(" " + after).prefix(after.isEmpty ? 0 : following))
        let prefix = lead + scored + tail
        recorder.start()
        _ = try await decode(currentSamples, options: options(prefix: prefix))
        let steps = recorder.steps
        let promptCount = recorder.promptCount
        // Call k's logits predict prompt token k + 1, so the prefix's tokens are read one call earlier.
        let firstCall = promptCount - prefix.count - 1
        let scoredRange = (lead.count)..<(prefix.count)
        var total: Float = 0
        for offset in scoredRange {
            let call = firstCall + offset
            guard steps.indices.contains(call) else { continue }
            total += steps[call][prefix[offset]] ?? 0
        }
        let firstCallIndex = firstCall + lead.count
        let first = steps.indices.contains(firstCallIndex) ? steps[firstCallIndex][scored[0]] ?? 0 : 0
        return (total, first)
    }

    /// The text's tokens without the special tokens the tokenizer wraps them in, as WhisperKit trims a prompt.
    private func text(_ string: String) -> [Int] {
        tokenizer.encode(text: string).filter { $0 < tokenizer.specialTokens.specialTokenBegin }
    }

    private var currentSamples: [Float] { recorder.samples }

    private func decode(_ samples: [Float], options: DecodingOptions) async throws -> [TranscriptionResult] {
        recorder.samples = samples
        return try await kit.transcribe(audioArray: samples, decodeOptions: options)
    }

    private func options(
        prompt: [Int]? = nil, prefix: [Int]? = nil, wordTimestamps: Bool = false
    ) -> DecodingOptions {
        DecodingOptions(
            language: "en", temperatureFallbackCount: 0, detectLanguage: false,
            withoutTimestamps: !wordTimestamps, wordTimestamps: wordTimestamps, windowClipTime: 0,
            promptTokens: prompt, prefixTokens: prefix, firstTokenLogProbThreshold: nil,
            noSpeechThreshold: nil)
    }

    private func normalised(_ word: String) -> String {
        word.lowercased().filter { $0.isLetter || $0.isNumber }
    }
}

/// A decoder that hands each step's log-probabilities of the prompt tokens to the probe.
final class RecordingDecoder: TextDecoding {
    private var inner: any TextDecoding
    /// Per model call, the log-probability of every token that appears in the window's prompt.
    private(set) var steps: [[Int: Float]] = []
    private(set) var promptCount = 0
    /// The audio of the decode under way, kept so a forced decode reuses the clip it scores.
    var samples: [Float] = []

    init(wrapping inner: any TextDecoding) { self.inner = inner }

    /// Clears the record; only the next window decoded is recorded, so a second window cannot shift the steps.
    func start() {
        steps = []
        promptCount = 0
        isRecording = true
    }

    private var isRecording = false

    var tokenizer: (any WhisperTokenizer)? {
        get { inner.tokenizer }
        set { inner.tokenizer = newValue }
    }
    var isModelMultilingual: Bool {
        get { inner.isModelMultilingual }
        set { inner.isModelMultilingual = newValue }
    }
    var logitsFilters: [any LogitsFiltering]? {
        get { inner.logitsFilters }
        set { inner.logitsFilters = newValue }
    }
    var supportsWordTimestamps: Bool { inner.supportsWordTimestamps }
    var logitsSize: Int? { inner.logitsSize }
    var kvCacheEmbedDim: Int? { inner.kvCacheEmbedDim }
    var kvCacheMaxSequenceLength: Int? { inner.kvCacheMaxSequenceLength }
    var windowSize: Int? { inner.windowSize }
    var embedSize: Int? { inner.embedSize }

    func predictLogits(_ inputs: any TextDecoderInputType) async throws -> (any TextDecoderOutputType)? {
        try await inner.predictLogits(inputs)
    }

    func prepareDecoderInputs(withPrompt initialPrompt: [Int]) throws -> any DecodingInputsType {
        try inner.prepareDecoderInputs(withPrompt: initialPrompt)
    }

    func prefillDecoderInputs(
        _ decoderInputs: any DecodingInputsType, withOptions options: DecodingOptions?
    ) async throws -> any DecodingInputsType {
        try await inner.prefillDecoderInputs(decoderInputs, withOptions: options)
    }

    func decodeText(
        from encoderOutput: any AudioEncoderOutputType, using decoderInputs: any DecodingInputsType,
        sampler tokenSampler: any TokenSampling, options decoderOptions: DecodingOptions,
        callback: TranscriptionCallback?
    ) async throws -> DecodingResult {
        guard isRecording else {
            return try await inner.decodeText(
                from: encoderOutput, using: decoderInputs, sampler: tokenSampler, options: decoderOptions,
                callback: callback)
        }
        isRecording = false
        let prompt = (decoderInputs as? DecodingInputs)?.initialPrompt ?? []
        promptCount = prompt.count
        let recording = WatchedTokenSampler(wrapping: tokenSampler, watched: Set(prompt)) { [weak self] in
            self?.steps.append($0)
        }
        return try await inner.decodeText(
            from: encoderOutput, using: decoderInputs, sampler: recording, options: decoderOptions,
            callback: callback)
    }

    func detectLanguage(
        from encoderOutput: any AudioEncoderOutputType, using decoderInputs: any DecodingInputsType,
        sampler tokenSampler: any TokenSampling, options: DecodingOptions, temperature: FloatType
    ) async throws -> DecodingResult {
        try await inner.detectLanguage(
            from: encoderOutput, using: decoderInputs, sampler: tokenSampler, options: options,
            temperature: temperature)
    }
}

/// Passes each step through, first noting the log-probability of every watched token.
struct WatchedTokenSampler: TokenSampling {
    let inner: any TokenSampling
    let watched: Set<Int>
    let record: ([Int: Float]) -> Void

    init(wrapping inner: any TokenSampling, watched: Set<Int>, record: @escaping ([Int: Float]) -> Void) {
        self.inner = inner
        self.watched = watched
        self.record = record
    }

    func update(tokens: [Int], logits: MLMultiArray, logProbs: [Float]) async -> SamplingResult {
        let count = logits.count
        var scores = [Float](repeating: 0, count: count)
        for index in 0..<count { scores[index] = logits[index].floatValue }
        let top = scores.max() ?? 0
        let normaliser = top + log(scores.reduce(0) { $0 + exp($1 - top) })
        record(
            Dictionary(
                uniqueKeysWithValues: watched.filter { $0 < count }.map { ($0, scores[$0] - normaliser) }))
        return await inner.update(tokens: tokens, logits: logits, logProbs: logProbs)
    }

    func finalize(tokens: [Int], logProbs: [Float]) -> SamplingResult {
        inner.finalize(tokens: tokens, logProbs: logProbs)
    }
}

/// The table and decision the probe writes.
struct RelistenReport {
    let outcomes: [RelistenOutcome]

    var markdown: String {
        let forced = outcomes.map { $0.forcedDifference > 0 }
        let margin = outcomes.map { $0.marginDifference > 0 }
        let cropped = outcomes.map(\.croppedRight)
        let interval = Self.bootstrap(outcomes) {
            Self.share($0.map { $0.forcedDifference > 0 }) - Self.share($0.map { $0.marginDifference > 0 })
        }
        var lines = [
            "clips \(outcomes.count); free decode right \(Self.percent(Self.share(outcomes.map(\.freeRight))))",
            "",
            "| Shape | Picks the meant word | Recovers a free-decode error | Overrides a right free decode | Added ms p50 | p95 |",
            "|---|---|---|---|---|---|",
            row("forced, whole candidate", picks: forced, seconds: outcomes.map(\.forcedSeconds)),
            row("forced, first-token margin", picks: margin, seconds: outcomes.map(\.forcedSeconds)),
            row("cropped re-decode", picks: cropped, seconds: outcomes.map(\.croppedSeconds)),
            "",
            String(
                format: "forced minus margin, paired share: %+.3f, 95%% bootstrap interval [%+.3f, %+.3f]",
                interval.point, interval.low, interval.high),
        ]
        lines.append("")
        return lines.joined(separator: "\n")
    }

    private func row(_ name: String, picks: [Bool], seconds: [Double]) -> String {
        let wrongFree = zip(outcomes, picks).filter { !$0.0.freeRight }.map(\.1)
        let rightFree = zip(outcomes, picks).filter { $0.0.freeRight }.map { !$0.1 }
        let sorted = seconds.sorted()
        let p50 = sorted.isEmpty ? 0 : sorted[sorted.count / 2] * 1000
        let p95 = sorted.isEmpty ? 0 : sorted[min(sorted.count - 1, sorted.count * 95 / 100)] * 1000
        return
            "| \(name) | \(Self.percent(Self.share(picks))) | \(Self.percent(Self.share(wrongFree))) of \(wrongFree.count) "
            + "| \(Self.percent(Self.share(rightFree))) of \(rightFree.count) | \(Int(p50)) | \(Int(p95)) |"
    }

    static func share(_ flags: [Bool]) -> Double {
        flags.isEmpty ? 0 : Double(flags.filter { $0 }.count) / Double(flags.count)
    }

    static func percent(_ value: Double) -> String { String(format: "%.0f%%", value * 100) }

    /// A percentile bootstrap over clips, with a fixed seed so a rerun prints the same interval.
    static func bootstrap(
        _ outcomes: [RelistenOutcome], rounds: Int = 2_000, statistic: ([RelistenOutcome]) -> Double
    ) -> (point: Double, low: Double, high: Double) {
        guard !outcomes.isEmpty else { return (0, 0, 0) }
        var state: UInt64 = 0x9E37_79B9_7F4A_7C15
        func next() -> Int {
            state = state &* 6_364_136_223_846_793_005 &+ 1_442_695_040_888_963_407
            return Int((state >> 33) % UInt64(outcomes.count))
        }
        let values = (0..<rounds).map { _ in statistic((0..<outcomes.count).map { _ in outcomes[next()] }) }
            .sorted()
        return (statistic(outcomes), values[rounds * 25 / 1000], values[rounds * 975 / 1000])
    }
}
