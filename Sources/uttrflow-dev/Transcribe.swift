import ArgumentParser
import Foundation
import UttrflowAI
import UttrflowAudio
import UttrflowCore
import UttrflowEval
import UttrflowSpeech

/// Records or reads audio, then transcribes it.
struct Transcribe: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        abstract: "Turn speech into text. Records from the microphone unless given a file."
    )

    @Argument(help: "An audio file to transcribe. Omit to record from the microphone.")
    var file: String?

    @Option(name: .shortAndLong, help: "Seconds to record when no file is given.")
    var seconds: Double = 5

    @Option(name: .shortAndLong, help: "Recogniser to use: whisperKit or appleSpeech.")
    var engine: String = SpeechEngineKind.whisperKit.rawValue

    @Option(name: .shortAndLong, help: "Bias towards a language, e.g. en or hi. Omit to detect.")
    var language: String?

    @Option(name: .customLong("model"), help: "Model variant. Defaults to the shipping model.")
    var modelVariant: String?

    @Flag(name: .long, help: "Show the transcript as heard, without tidying it.")
    var raw = false

    func validate() throws {
        guard SpeechEngineKind(rawValue: engine) != nil else {
            throw ValidationError(
                "Unknown engine '\(engine)'. Known: "
                    + SpeechEngineKind.allCases.map(\.rawValue).joined(separator: ", ")
            )
        }
        if let language, LanguageCode(language) == nil {
            throw ValidationError("'\(language)' is not a language code.")
        }
    }

    // Biasing changes what the recogniser hears, so it has to be reachable from here:
    // the only honest way to tell whether a word made it into the prompt is to say the
    // word and look at the transcript.
    @Option(
        name: .long,
        help: "Words to bias the recogniser towards, comma separated.")
    var bias: String?

    // Correction only touches a word the recogniser was unsure of, so the scores are
    // the one thing that decides whether it can ever fire. Printing them is how you
    // find out, rather than inferring it from whether a correction happened.
    @Flag(name: .long, help: "Print what the recogniser thought of each word.")
    var confidence = false

    func run() async throws {
        guard let kind = SpeechEngineKind(rawValue: engine) else { return }
        let model = try resolve(modelVariant)
        let store = FileSystemSpeechModelStore.whisperKit()

        if kind == .whisperKit, !store.isInstalled(model) {
            throw CleanExit.message(
                "\(model.variant) is not installed. Run: uttrflow-dev models install"
            )
        }

        let audio = try await obtainAudio()
        guard !audio.isEmpty else { throw CleanExit.message("Nothing was captured.") }

        let biasWords =
            bias?.split(separator: ",").map { String($0).trimmingCharacters(in: .whitespaces) }.filter {
                !$0.isEmpty
            } ?? []
        let speech = SpeechEngineFactory.make(
            kind: kind, model: model, modelFolder: store.location(of: model),
            vocabulary: biasWords.isEmpty
                ? nil : FixedVocabulary(words: biasWords)
        )

        let clock = ContinuousClock()
        let idleMemory = MemoryFootprint.current()
        let loadStart = clock.now
        try await speech.prepare()
        let loaded = loadStart.duration(to: clock.now)
        let speechMemory = MemoryFootprint.current()

        let start = clock.now
        let transcription = try await speech.transcribe(
            audio, options: TranscriptionOptions(languageHint: language.flatMap(LanguageCode.init))
        )
        let elapsed = start.duration(to: clock.now)

        var cleaned: TransformationResult?
        var cleanupTime = Duration.zero
        if !raw, !transcription.isBlank {
            let cleanupStart = clock.now
            cleaned = try? await TextTransformers.router().transform(
                TransformationRequest(transcription: transcription)
            )
            cleanupTime = cleanupStart.duration(to: clock.now)
        }

        if transcription.isBlank {
            print("\n(nothing recognised)\n")
        } else if let cleaned {
            print("\n\(cleaned.text)\n")
            print("  as heard     \(transcription.text)")
        } else {
            print("\n\(transcription.text)\n")
        }
        print("  audio        \(seconds(audio.duration))s")
        print("  engine ready \(seconds(loaded))s")
        print(
            "  transcribed  \(seconds(elapsed))s  "
                + "(\(String(format: "%.1f", audio.duration / elapsed))× real time)")
        if let cleaned {
            print("  tidied by    \(cleaned.producedBy.rawValue) in \(seconds(cleanupTime))s")
        }
        if confidence {
            let scores = transcription.segments.flatMap(\.words)
            if scores.isEmpty {
                print("  scores     none — this recogniser does not report them")
            } else {
                let doubtful = scores.filter { $0.confidence < 0.5 }
                print("  scores     \(scores.count) words, \(doubtful.count) below 0.5")
                for word in scores.sorted(by: { $0.confidence < $1.confidence }).prefix(6) {
                    let name = word.text.padding(toLength: 16, withPad: " ", startingAt: 0)
                    print("    \(name) \(String(format: "%.2f", word.confidence))")
                }
            }
        }

        if let detected = transcription.detectedLanguage {
            let confidence = detected.confidence.map { String(format: " at %.0f%%", $0 * 100) } ?? ""
            print("  language     \(detected.code)\(confidence)")
        }
        if !transcription.segments.isEmpty {
            print("  segments     \(transcription.segments.count)")
        }
        // §20 asks for these. They are cheap to report and impossible to guess.
        if let idleMemory, let speechMemory, let peak = MemoryFootprint.current() {
            print(
                "  memory       \(gigabytes(idleMemory)) idle → "
                    + "\(gigabytes(speechMemory)) ready → \(gigabytes(peak)) peak")
        }
    }

    private func obtainAudio() async throws -> AudioSamples {
        if let file {
            return try AudioFileReader.read(contentsOf: URL(fileURLWithPath: file))
        }

        try await requireMicrophoneAccess()

        let capture = AVAudioCaptureEngine(source: AVAudioEngineMicrophoneSource())
        try await capture.start()
        print("Recording for \(String(format: "%.0f", self.seconds))s — speak now.")
        try await Task.sleep(for: .milliseconds(Int(self.seconds * 1000)))
        return try await capture.stop()
    }

    private func gigabytes(_ bytes: Int64) -> String {
        String(format: "%.2fGB", Double(bytes) / 1e9)
    }

    private func seconds(_ duration: Duration) -> String {
        String(
            format: "%.2f",
            duration.inSeconds)
    }
}

extension Duration {
    /// How many times faster than real time a stage ran.
    fileprivate static func / (lhs: Duration, rhs: Duration) -> Double {
        lhs.inSeconds / (rhs.inSeconds > 0 ? rhs.inSeconds : 1)
    }
}

/// A vocabulary given on the command line, so biasing can be tried without a dictionary.
private struct FixedVocabulary: VocabularySource {
    let words: [String]
    func vocabulary() async -> [String] { words }
}
