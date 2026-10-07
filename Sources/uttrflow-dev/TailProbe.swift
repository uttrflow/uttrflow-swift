// The `tail-probe` command: decodes a recording under the pause rule and under agreement commit, and scores both.
import ArgumentParser
import Foundation
import UttrflowAudio
import UttrflowCore
import UttrflowEval
import UttrflowSpeech

/// Compares the two ways of committing the open tail while the key is held. See `Docs/tail-commit.md`.
struct TailProbe: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "tail-probe",
        abstract: "Score the pause rule against agreement commit on recordings with a reference transcript.",
        discussion: """
            Each line of JOBS is tab-separated: id, WAV path, reference transcript. Output is one JSON line \
            per clip and policy, prefixed TAIL.
            """
    )

    @Argument(help: "The jobs file.")
    var jobs: String

    @Option(name: .customLong("model"), help: "Model variant. Defaults to the shipping model.")
    var modelVariant: String?

    @OptionGroup var modelsDirectory: ModelsDirectoryOptionGroup

    @Option(name: .long, help: "Seconds between re-decodes of the open piece under agreement commit.")
    var interval: Double = 1.5

    func validate() throws {
        guard interval.isFinite, interval >= 0.5, interval <= 10 else {
            throw ValidationError("--interval must be between 0.5 and 10 seconds.")
        }
    }

    func run() async throws {
        let model = try resolve(modelVariant)
        let store = try modelsDirectory.store()
        guard store.isInstalled(model) else { throw notInstalled(model, in: store) }
        let speech = SpeechEngineFactory.make(
            kind: .whisperKit, model: model, modelFolder: store.location(of: model))
        try await speech.prepare()
        let decoder = TailDecoder(speech: speech)
        for line in try String(contentsOfFile: jobs, encoding: .utf8).split(separator: "\n") {
            let fields = line.split(separator: "\t", omittingEmptySubsequences: false).map(String.init)
            guard fields.count >= 3 else { throw ValidationError("A job needs id, WAV path and reference.") }
            let audio = try AudioFileReader.read(contentsOf: URL(fileURLWithPath: fields[1]))
            let whole = try await decoder.decode(audio.samples)
            for outcome in [
                try await pauseRule(audio.samples, decoder: decoder),
                try await agreement(audio.samples, decoder: decoder),
            ] {
                emit(
                    id: fields[0], audio: audio.samples, outcome: outcome, whole: whole, reference: fields[2])
            }
        }
    }

    /// What one policy produced for one clip.
    struct Outcome {
        let policy: String
        let pieces: [String]
        let finalPieceSeconds: Double
        let tailWaitSeconds: Double
        let heldDecodeSeconds: Double
        let decodes: Int
    }

    /// The shipped windowing: every window but the last decodes while the key is held.
    private func pauseRule(_ samples: [Float], decoder: TailDecoder) async throws -> Outcome {
        let windows = SpeechWindowing.standard.windows(
            in: samples, sampleRate: AudioSamples.canonicalSampleRate)
        var pieces: [String] = []
        var held = 0.0
        var tail = 0.0
        for (index, window) in windows.enumerated() {
            let decoded = try await decoder.decode(Array(samples[window]))
            pieces.append(decoded.text)
            if index == windows.count - 1 { tail = decoded.seconds } else { held += decoded.seconds }
        }
        return Outcome(
            policy: "pause", pieces: pieces, finalPieceSeconds: seconds(windows.last?.count ?? 0),
            tailWaitSeconds: tail, heldDecodeSeconds: held, decodes: windows.count)
    }

    /// Re-decodes the open piece every `interval`, commits the words two passes agree on, and cuts after them.
    private func agreement(_ samples: [Float], decoder: TailDecoder) async throws -> Outcome {
        let rate = AudioSamples.canonicalSampleRate
        var cut = 0
        var previous: [AlignedWord] = []
        var pieces: [String] = []
        var held = 0.0
        var decodes = 0
        var now = interval
        while Int(now * Double(rate)) < samples.count {
            let end = Int(now * Double(rate))
            now += interval
            // Under a second of open audio is too little for a pass to agree with.
            guard end - cut >= rate else { continue }
            let decoded = try await decoder.decode(Array(samples[cut..<min(end, cut + 30 * rate)]))
            held += decoded.seconds
            decodes += 1
            let agreed = TailCommit.agreedPrefix(previous, decoded.words)
            guard agreed > 0 else {
                previous = decoded.words
                continue
            }
            let committed = decoded.words[..<agreed]
            pieces.append(committed.map(\.word).joined(separator: " "))
            let cutSeconds = committed.last?.end ?? 0
            cut += Int(cutSeconds * Double(rate))
            previous = decoded.words[agreed...].map {
                AlignedWord(word: $0.word, start: $0.start - cutSeconds, end: $0.end - cutSeconds)
            }
        }
        let tail = try await decoder.decode(Array(samples[min(cut, samples.count)...]))
        pieces.append(tail.text)
        return Outcome(
            policy: "agreement", pieces: pieces, finalPieceSeconds: seconds(samples.count - cut),
            tailWaitSeconds: tail.seconds, heldDecodeSeconds: held, decodes: decodes + 1)
    }

    private func seconds(_ samples: Int) -> Double {
        Double(samples) / Double(AudioSamples.canonicalSampleRate)
    }

    private func emit(id: String, audio: [Float], outcome: Outcome, whole: TailDecode, reference: String) {
        let joined = outcome.pieces.filter { !$0.isEmpty }.joined(separator: " ")
        let seams = TailCommit.seamArtefacts(
            pieces: outcome.pieces.filter { !$0.isEmpty }, reference: reference)
        let fields: [String: Any] = [
            "id": id, "policy": outcome.policy, "audio": seconds(audio.count),
            "finalPiece": outcome.finalPieceSeconds, "tailWait": outcome.tailWaitSeconds,
            "heldDecode": outcome.heldDecodeSeconds, "decodes": outcome.decodes,
            "wer": TailCommit.wordErrorRate(hypothesis: joined, reference: reference).rate ?? -1,
            "wholeWer": TailCommit.wordErrorRate(hypothesis: whole.text, reference: reference).rate ?? -1,
            "seams": seams.seams, "strayStops": seams.strayStops, "strayCapitals": seams.strayCapitals,
            "duplicated": seams.duplicatedWords, "dropped": seams.droppedWords, "text": joined,
        ]
        guard let data = try? JSONSerialization.data(withJSONObject: fields, options: [.sortedKeys]) else {
            return
        }
        print("TAIL " + String(decoding: data, as: UTF8.self))
    }
}

/// One decode's text, timed words and wall-clock cost.
struct TailDecode {
    let text: String
    let words: [AlignedWord]
    let seconds: Double
}

/// The recogniser as the probe calls it: English, unprompted, timed.
struct TailDecoder {
    let speech: any SpeechEngine

    func decode(_ samples: [Float]) async throws -> TailDecode {
        guard let audio = AudioSamples(samples: samples, sampleRate: AudioSamples.canonicalSampleRate) else {
            return TailDecode(text: "", words: [], seconds: 0)
        }
        let start = ContinuousClock.now
        let transcription = try await speech.transcribe(
            audio, options: TranscriptionOptions(languageHint: LanguageCode("en")))
        let elapsed = start.duration(to: .now)
        let words = transcription.segments.flatMap(\.words).map {
            AlignedWord(
                word: $0.text.trimmingCharacters(in: .whitespaces),
                start: ($0.start ?? .zero).inSeconds, end: ($0.end ?? .zero).inSeconds)
        }
        return TailDecode(text: transcription.text, words: words, seconds: elapsed.inSeconds)
    }
}
