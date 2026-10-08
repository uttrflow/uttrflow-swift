// The `short-clip` command: what the silence padded onto a short clip costs, alone and as a dictation's last piece.
import ArgumentParser
private import Foundation
private import UttrflowAudio
private import UttrflowCore
private import UttrflowEval
private import UttrflowSpeech

/// Decodes synthetic short replies under each padding, and long dictations' short last pieces alone and merged.
struct ShortClipProbe: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "short-clip",
        abstract: "Measure the padding of short clips, and a short last piece decoded alone against merged."
    )

    /// Invented replies of one to three words, each under a second when spoken.
    static let replies = [
        "yes", "no", "ship it", "no wait", "thanks", "sounds good", "got it", "not yet", "sure",
        "call me", "on my way", "see you soon",
    ]

    /// Invented paragraphs, each read before a pause and one of ``replies``: a long dictation's lead.
    static let leads = [
        (
            "the quarterly numbers are in the shared folder. please check the second tab before the call. "
                + "the totals for march look lower than we expected. can you confirm them with finance",
            "ship it"
        ),
        (
            "i moved the team lunch to thursday at noon. the room on the fourth floor is booked. "
                + "bring the printed agenda if you can. let me know if anyone cannot make it",
            "thanks"
        ),
        (
            "the garden hose is leaking near the tap again. i put a bucket under it for now. "
                + "we should buy a new washer this weekend. the hardware shop opens at nine",
            "yes"
        ),
        (
            "the draft report needs one more pass on the summary. the charts on page six are blurry. "
                + "i will send the source files tonight. should we hold the release until monday",
            "no wait"
        ),
        (
            "our flight lands at half past six on friday. we will take the train into the city. "
                + "the hotel is two streets from the station. dinner is booked for eight",
            "sounds good"
        ),
        (
            "the new kettle arrived this morning but the lid is cracked. i asked the shop for a refund. "
                + "they said a courier will collect it tomorrow. i will leave it by the door",
            "see you soon"
        ),
    ]

    @Option(name: .long, help: "Where the synthesised clips are written.")
    var clipsPath = ".uttrflow-eval/short-clips"

    @Option(name: .long, parsing: .upToNextOption, help: "The `say` voices that read every clip.")
    var voices = SpokenClips.voices

    @Option(name: .long, help: "Seconds of silence between a long dictation's lead and its short reply.")
    var pause = 1.5

    func validate() throws {
        if voices.isEmpty { throw ValidationError("--voices needs at least one voice.") }
        if pause < 0 { throw ValidationError("--pause must not be negative.") }
    }

    func run() async throws {
        let store = FileSystemSpeechModelStore.whisperKit()
        guard store.isInstalled(.default) else {
            throw CleanExit.message(
                "\(SpeechModel.default.variant) is not installed. Run: uttrflow-dev models install")
        }
        let backend = WhisperKitBackend(model: .default, modelFolder: store.location(of: .default))
        try await backend.load()
        let decoder = Decoder(backend: backend)
        // One decode first, so the first measured clip does not carry the model's warm-up.
        _ = try await decoder.decode(Array(repeating: 0, count: 2 * AudioSamples.canonicalSampleRate))
        try await shortClips(decoder)
        try await lastPieces(decoder)
    }

    /// Arm A: each reply decoded alone, unpadded, padded as shipped, and under the two alternatives.
    private func shortClips(_ decoder: Decoder) async throws {
        var outcomes: [Padding: [Outcome]] = [:]
        var lengths: [Double] = []
        for voice in voices {
            for (index, reply) in Self.replies.enumerated() {
                Terminal.show("\r  short clip \(voice) \(index + 1)/\(Self.replies.count)")
                let audio = try synthesise(reply, voice: voice, name: "reply-\(voice)-\(index)")
                guard let speech = audio.speechOnly() else {
                    throw CleanExit.message("No speech in '\(reply)'.")
                }
                lengths.append(Double(speech.audio.samples.count) / Double(speech.audio.sampleRate))
                for padding in Padding.allCases {
                    let input = padding.applied(to: speech.audio, floor: decoder.backend.minimumDuration)
                    let (heard, seconds) = try await decoder.decode(input)
                    outcomes[padding, default: []].append(.scored(reply, heard, seconds: seconds))
                }
            }
        }
        Terminal.clearLine()
        print(
            String(
                format: "Arm A: %@, %.2f to %.2f s of speech after the trim",
                counted(lengths.count, "short clip"), lengths.min() ?? 0, lengths.max() ?? 0))
        for padding in Padding.allCases {
            print("  \(padding.rawValue.padded(to: 36))\(summary(outcomes[padding] ?? []))")
        }
        let shipped = outcomes[.shipped] ?? []
        // Two alternatives against one baseline, so each interval is widened to 97.5% (Bonferroni).
        for alternative in [Padding.toTwoSeconds, .leadingHalfSecond] {
            compare(
                shipped, outcomes[alternative] ?? [], label: "\(alternative.rawValue) minus shipped",
                confidence: 0.975)
        }
        for padding in Padding.allCases where padding != .unpadded {
            for outcome in outcomes[padding] ?? [] where outcome.errors > 0 {
                print("    \(padding.rawValue): '\(outcome.reference)' heard as '\(outcome.heard)'")
            }
        }
    }

    /// Arm B: each long dictation windowed as shipped, its short last piece decoded merged and alone.
    private func lastPieces(_ decoder: Decoder) async throws {
        var merged: [Outcome] = []
        var alone: [Outcome] = []
        let rate = AudioSamples.canonicalSampleRate
        let windowing = SpeechWindowing.standard
        for voice in voices {
            for (index, (lead, reply)) in Self.leads.enumerated() {
                Terminal.show("\r  last piece \(voice) \(index + 1)/\(Self.leads.count)")
                let replyIndex = Self.replies.firstIndex(of: reply) ?? 0
                let samples =
                    try synthesise(lead, voice: voice, name: "lead-\(voice)-\(index)").samples
                    + Array(repeating: 0, count: Int(pause * Double(rate)))
                    + synthesise(reply, voice: voice, name: "reply-\(voice)-\(replyIndex)").samples
                let windows = windowing.windows(in: samples, sampleRate: rate)
                // The cut the windowing withdrew when it joined the fragment to the window before it.
                guard let tail = windows.last,
                    let cut = windowing.nextCut(in: samples, sampleRate: rate, from: tail.lowerBound),
                    cut < tail.upperBound
                else { continue }
                var ahead: [String] = []
                for window in windows.dropLast() {
                    ahead.append(try await decoder.decodeWindow(Array(samples[window])).heard)
                }
                let whole = try await decoder.decodeWindow(Array(samples[tail]))
                let before = try await decoder.decodeWindow(Array(samples[tail.lowerBound..<cut]))
                let after = try await decoder.decodeWindow(Array(samples[cut..<tail.upperBound]))
                let reference = lead + " " + reply
                merged.append(
                    .scored(reference, (ahead + [whole.heard]).joined(separator: " "), seconds: whole.seconds)
                )
                alone.append(
                    .scored(
                        reference, (ahead + [before.heard, after.heard]).joined(separator: " "),
                        seconds: after.seconds))
            }
        }
        Terminal.clearLine()
        print(
            "\nArm B: \(merged.count) of \(voices.count * Self.leads.count) dictations end in a fragment "
                + "the windowing joins to the window before it; decode time is the last window's, after key-up"
        )
        print("  \("merged (shipped)".padded(to: 36))\(summary(merged))")
        print("  \("alone, padded".padded(to: 36))\(summary(alone))")
        compare(alone, merged, label: "merged minus alone", confidence: 0.95)
        for (one, other) in zip(merged, alone) where one.errors != other.errors {
            print(
                "    merged, \(one.errors) errors: '\(one.heard)'\n    alone, \(other.errors) errors: '\(other.heard)'"
            )
        }
    }

    /// The pooled WER change from `before` to `after` and the mean decode-time change, each with its paired interval.
    private func compare(_ before: [Outcome], _ after: [Outcome], label: String, confidence: Double) {
        let bootstrap = PairedBootstrap(confidence: confidence)
        let words = zip(before, after).map {
            PairedBootstrap.Pair(
                errorsBefore: $0.errors, wordsBefore: $0.words, errorsAfter: $1.errors, wordsAfter: $1.words)
        }
        // Milliseconds over one clip each, so the pooled rate is the mean decode time per clip.
        let time = zip(before, after).map {
            PairedBootstrap.Pair(
                errorsBefore: Int($0.seconds * 1000), wordsBefore: 1, errorsAfter: Int($1.seconds * 1000),
                wordsAfter: 1)
        }
        guard let wordInterval = bootstrap.estimate(words)?.interval,
            let timeInterval = bootstrap.estimate(time)?.interval
        else { return }
        let meanTime =
            (after.map(\.seconds).reduce(0, +) - before.map(\.seconds).reduce(0, +)) / Double(after.count)
        print(
            String(
                format: "  %@: WER %+.3f [%+.3f, %+.3f], decode %+.0f ms [%+.0f, %+.0f], %.1f%% intervals",
                label, rate(after) - rate(before), wordInterval.lowerBound, wordInterval.upperBound,
                meanTime * 1000, timeInterval.lowerBound, timeInterval.upperBound, confidence * 100))
    }

    private func rate(_ outcomes: [Outcome]) -> Double {
        let words = outcomes.map(\.words).reduce(0, +)
        return words == 0 ? 0 : Double(outcomes.map(\.errors).reduce(0, +)) / Double(words)
    }

    private func summary(_ outcomes: [Outcome]) -> String {
        let times = outcomes.map(\.seconds).sorted()
        return String(
            format: "WER %.3f over %d words, %d empty, median decode %.0f ms", rate(outcomes),
            outcomes.map(\.words).reduce(0, +), outcomes.filter { $0.heard.isEmpty }.count,
            (times.isEmpty ? 0 : times[times.count / 2]) * 1000)
    }

    /// `text` read by `voice` into a 16 kHz file, synthesised once and reused on later runs; never played.
    private func synthesise(_ text: String, voice: String, name: String) throws -> AudioSamples {
        let directory = URL(fileURLWithPath: clipsPath)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let url = directory.appendingPathComponent("\(name).wav")
        if !FileManager.default.fileExists(atPath: url.path) {
            let say = Process()
            say.executableURL = URL(fileURLWithPath: "/usr/bin/say")
            say.arguments = ["-v", voice, "-o", url.path, "--data-format=LEF32@16000", text]
            try say.run()
            say.waitUntilExit()
            guard say.terminationStatus == 0 else {
                throw CleanExit.message("say failed for voice \(voice).")
            }
        }
        return try AudioFileReader.read(contentsOf: url)
    }
}

/// How a short clip's speech is extended before it is decoded.
private enum Padding: String, CaseIterable {
    case unpadded = "unpadded"
    case shipped = "padded to the floor (shipped)"
    case toTwoSeconds = "padded to 2.0 s"
    case leadingHalfSecond = "0.5 s before, padded to the floor"

    func applied(to speech: AudioSamples, floor: Duration) -> [Float] {
        switch self {
        case .unpadded: speech.samples
        case .shipped: BackedSpeechEngine.padded(speech, to: floor)
        case .toTwoSeconds: BackedSpeechEngine.padded(speech, to: .seconds(2))
        case .leadingHalfSecond:
            BackedSpeechEngine.padded(
                .canonical(Array(repeating: 0, count: speech.sampleRate / 2) + speech.samples), to: floor)
        }
    }
}

/// One decode, scored against what was read.
private struct Outcome {
    let reference: String
    let heard: String
    let errors: Int
    let words: Int
    let seconds: Double

    static func scored(_ reference: String, _ heard: String, seconds: Double) -> Outcome {
        let rate = WordErrorRate.measure(
            reference: TextNormaliser.standard.words(reference),
            hypothesis: TextNormaliser.standard.words(heard))
        return Outcome(
            reference: reference, heard: heard, errors: rate.errors, words: rate.referenceWordCount,
            seconds: seconds)
    }
}

/// The recogniser, timed, with the engine's trim and padding in front of it for a window.
private struct Decoder {
    let backend: WhisperKitBackend

    /// The text heard in `input` exactly as given, and the seconds the decode took.
    func decode(_ input: [Float]) async throws -> (heard: String, seconds: Double) {
        guard !input.isEmpty else { return ("", 0) }
        let clock = ContinuousClock()
        let started = clock.now
        let heard = try await backend.transcribe(input, languageHint: nil).text
        let elapsed = started.duration(to: clock.now)
        return (heard.trimmingCharacters(in: .whitespacesAndNewlines), elapsed / .seconds(1))
    }

    /// A window trimmed and padded as `BackedSpeechEngine` does; its loop repair is left out, since nothing here repeats.
    func decodeWindow(_ samples: [Float]) async throws -> (heard: String, seconds: Double) {
        guard let speech = AudioSamples.canonical(samples).speechOnly() else { return ("", 0) }
        return try await decode(BackedSpeechEngine.padded(speech.audio, to: backend.minimumDuration))
    }
}
