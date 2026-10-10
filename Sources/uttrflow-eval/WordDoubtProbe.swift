// The `word-doubt` command: how well each word-level doubt feature flags a recognised word that differs from the reading.
import ArgumentParser
private import Foundation
private import UttrflowAI
private import UttrflowAudio
private import UttrflowCore
private import UttrflowEval
private import UttrflowSpeech

/// Decodes the English passages and the homophone carriers in synthetic voices, then scores every doubt feature as a calibrated flag.
struct WordDoubtProbe: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "word-doubt",
        abstract:
            "Measure each word-level doubt feature's AUROC, held-out precision and recall, and the candidate ceiling."
    )

    @Option(name: .long, help: "Where the generated clips are written.")
    var clipsPath = ".uttrflow-eval/word-doubt-clips"

    @Option(name: .customLong("model"), help: "Model variant. Defaults to the shipping model.")
    var modelVariant: String?

    @Option(name: .long, parsing: .upToNextOption, help: "Synthetic voices that read the sentences.")
    var voices = SpokenClips.accentVoices

    @Option(name: .long, parsing: .upToNextOption, help: "Signal-to-noise ratios in dB; 'inf' is clean.")
    var snrs: [Double] = [.infinity, 20, 10]

    @Option(name: .long, help: "Read only the first this many sentences, for a short run.")
    var limit: Int?

    @Option(name: .long, help: "The precision a flag must reach for recall to count.")
    var precision = 0.5

    @Option(name: .long, help: "The rate the clips are synthesised at.")
    var inputRate = 48_000.0

    func run() async throws {
        let model =
            try modelVariant.map { name in
                guard let found = SpeechModel.named(name) else {
                    throw ValidationError("Unknown model '\(name)'.")
                }
                return found
            } ?? .default
        let store = FileSystemSpeechModelStore.whisperKit()
        guard store.isInstalled(model) else {
            throw CleanExit.message("\(model.variant) is not installed. Run: uttrflow-dev models install")
        }
        let speech = SpeechEngineFactory.make(
            kind: .whisperKit, model: model, modelFolder: store.location(of: model))
        try await speech.prepare()
        let directory = URL(fileURLWithPath: clipsPath)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)

        let passages = TranscriptionCorpus.cases(in: .english).map(\.romanised)
        let carriers = HomophoneCarriers.all.map { $0.filled(with: $0.spelling) }
        let sentences = Array((passages + carriers).prefix(limit ?? .max))
        print(
            "whisperKit \(model.variant); \(sentences.count) sentences; voices \(voices.joined(separator: ", ")); "
                + "noise \(snrs.map(label).joined(separator: ", "))")
        var judged: [String: [Stratum: [DoubtDetector.Judged]]] = [:]
        var untokened = 0
        for (index, sentence) in sentences.enumerated() {
            Terminal.show("\r  sentence \(index + 1)/\(sentences.count)          ")
            let reference = TextNormaliser.standard.words(sentence)
            for voice in voices {
                let clean = try clip(sentence, voice: voice, in: directory)
                for snr in snrs {
                    let samples = snr.isInfinite ? clean : WhiteNoise.added(clean, snr: snr)
                    let transcription = try await speech.transcribe(
                        .canonical(samples), options: TranscriptionOptions(languageHint: nil, vocabulary: []))
                    let heard = transcription.segments.flatMap(\.words).flatMap { word in
                        TextNormaliser.standard.words(word.text).map { (word: $0, tokens: word.tokens) }
                    }
                    let read = WordDoubtAlignment.read(reference: reference, heard: heard.map(\.word))
                    var words: [(tokens: [TokenEvidence], isWrong: Bool, heardSurely: Bool, offered: Bool)] =
                        []
                    for (word, readWord) in zip(heard, read) {
                        guard !word.tokens.isEmpty else {
                            untokened += 1
                            continue
                        }
                        let isWrong = readWord != word.word
                        var offered = false
                        if isWrong, let readWord { offered = await offers(readWord, for: word.word) }
                        let mean = WordDoubtFeature.mean.certainty(of: word.tokens) ?? 0
                        words.append(
                            (word.tokens, isWrong, DoubtPolicy.isHeardSurely(mean), offered))
                    }
                    for feature in WordDoubtFeature.allCases {
                        let certainties = words.map { feature.certainty(of: $0.tokens) ?? 0 }
                        for (name, values) in [
                            (feature.rawValue, certainties),
                            ("\(feature.rawValue) relative", DoubtDetector.relativeToSentence(certainties)),
                        ] {
                            for (word, certainty) in zip(words, values) {
                                let item = DoubtDetector.Judged(
                                    scored: .init(
                                        certainty: certainty, isWrong: word.isWrong, cluster: voice),
                                    heardSurely: word.heardSurely, offered: word.offered)
                                for stratum in [Stratum.all, .noise(label(snr)), .voice(voice)] {
                                    judged[name, default: [:]][stratum, default: []].append(item)
                                }
                            }
                        }
                    }
                }
            }
        }
        Terminal.clearLine()
        if untokened > 0 { print("\(untokened) words carried no token evidence and were left out") }
        let strata =
            [Stratum.all] + snrs.map { Stratum.noise(label($0)) } + voices.map { Stratum.voice($0) }
        let detectors = WordDoubtFeature.allCases.flatMap { [$0.rawValue, "\($0.rawValue) relative"] }
        let required = "\(Int(precision * 100))%"
        print(
            "\n| Feature | Stratum | Words | Wrong | AUROC (95% CI) | Recall at \(required) precision (95% CI) |"
        )
        print("|---|---|---|---|---|---|")
        for detector in detectors {
            for stratum in strata {
                let words = (judged[detector]?[stratum] ?? []).map(\.scored)
                let auroc = WordDoubtEvaluation.clustered(words) { WordDoubtEvaluation.auroc($0) }
                let recall = WordDoubtEvaluation.clustered(words) {
                    WordDoubtEvaluation.recall($0, atPrecision: precision)
                }
                print(
                    "| \(detector) | \(stratum.name) | \(words.count) | \(words.count(where: \.isWrong)) | "
                        + "\(cell(auroc)) | \(cell(recall)) |")
            }
        }
        print(
            "\nFlag chosen at \(required) precision on all voices; recall and precision from flags chosen "
                + "without the word's own voice.")
        print(
            "\n| Feature | Stratum | Threshold | Recall | Precision | Confident errors flagged | Ceiling | Reachable |"
        )
        print("|---|---|---|---|---|---|---|---|")
        for detector in detectors {
            for stratum in [Stratum.all] + voices.map({ Stratum.voice($0) }) {
                let result = DoubtDetector.evaluate(judged[detector]?[stratum] ?? [], atPrecision: precision)
                print(
                    "| \(detector) | \(stratum.name) | \(result.threshold.map { String(format: "%.3f", $0) } ?? "–") | "
                        + "\(share(result.recall)) | \(share(result.precision)) | \(share(result.confidentRecall)) | "
                        + "\(share(result.ceiling)) | \(share(result.reachable)) |")
            }
        }
    }

    /// Whether the readings candidate generation offers for `heard`, as many as one span may carry, include `read`.
    private func offers(_ read: String, for heard: String) async -> Bool {
        let word = Draft.Word(text: heard, heard: heard, evidence: .score(0))
        var readings: [String] = []
        for source in DoubtfulWords.standard.sources {
            for reading in await source.candidates(for: word, in: .unknown) {
                let spelt = TextNormaliser.standard.words(reading.spelling).joined(separator: " ")
                if spelt != heard, !readings.contains(spelt) { readings.append(spelt) }
            }
        }
        return readings.prefix(DoubtfulWords.maximumCandidatesPerSpan).contains(read)
    }

    private func share(_ share: GroupCalibration.Share) -> String {
        guard share.total > 0 else { return "–" }
        let range = share.interval
        return String(
            format: "%d/%d (%.2f, %.2f–%.2f)", share.count, share.total, share.value, range.lowerBound,
            range.upperBound)
    }

    /// The rows a feature is reported in.
    enum Stratum: Hashable {
        case all
        case noise(String)
        case voice(String)

        var name: String {
            switch self {
            case .all: "all"
            case .noise(let level): level
            case .voice(let voice): voice
            }
        }
    }

    private func label(_ snr: Double) -> String { snr.isInfinite ? "clean" : "\(Int(snr)) dB" }

    private func cell(_ interval: WordDoubtEvaluation.Interval?) -> String {
        guard let interval else { return "–" }
        return String(format: "%.2f (%.2f–%.2f)", interval.value, interval.low, interval.high)
    }

    /// The sentence read by `voice`, synthesised once and reused.
    private func clip(_ text: String, voice: String, in directory: URL) throws -> [Float] {
        let key = text.utf8.reduce(UInt64(14_695_981_039_346_656_037)) {
            ($0 ^ UInt64($1)) &* 1_099_511_628_211
        }
        let url = directory.appendingPathComponent("\(voice)-\(String(key, radix: 16)).wav")
        if !FileManager.default.fileExists(atPath: url.path) {
            let say = Process()
            say.executableURL = URL(fileURLWithPath: "/usr/bin/say")
            say.arguments = ["-v", voice, "-o", url.path, "--data-format=LEF32@\(Int(inputRate))", text]
            try say.run()
            say.waitUntilExit()
            guard say.terminationStatus == 0 else {
                throw CleanExit.message("say failed for voice \(voice).")
            }
        }
        return try AudioFileReader.read(contentsOf: url).samples
    }
}
