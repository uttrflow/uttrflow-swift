import ArgumentParser
import Foundation
import UttrflowAI
import UttrflowAudio
import UttrflowCore
import UttrflowEval
import UttrflowLocalModel
import UttrflowSpeech

/// Measures idle memory, each model loaded, and both at once. See `Docs/bakeoff-method.md`.
struct Footprint: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        abstract: "Report disk and memory cost, with both models loaded."
    )

    @Option(name: .shortAndLong, help: "Local model to measure alongside speech.")
    var model: String = LocalModel.gemma3.shortName

    @Option(name: .long, help: "Audio to transcribe. Skipped when absent.")
    var audio: String?

    func run() async throws {
        guard let local = LocalModel.named(model) else {
            throw ValidationError("Unknown model '\(model)'.")
        }

        report("nothing loaded")

        let store = FileSystemSpeechModelStore.whisperKit()
        let speechModel = SpeechModel.default
        guard store.isInstalled(speechModel) else {
            throw CleanExit.message("Speech model not installed. Run: uttrflow-dev models install")
        }

        let speech = SpeechEngineFactory.make(
            kind: .whisperKit, model: speechModel, modelFolder: store.location(of: speechModel))
        try await speech.prepare()
        let withSpeech = report("speech model loaded")

        let cleanup = MLXCleanupModel(model: local)
        try await cleanup.prepare()
        let withBoth = report("both models loaded")

        var peak = withBoth
        if let audio {
            let samples = try AudioFileReader.read(contentsOf: URL(fileURLWithPath: audio))
            let transcription = try await speech.transcribe(samples, options: .automatic)
            peak = max(peak, footprint())

            let transformer = GenerativeTextTransformer(kind: .localModel, model: cleanup)
            _ = try? await transformer.transform(
                TransformationRequest(transcription: transcription))
            peak = max(peak, footprint())
            print("  \("peak, dictating".padded(to: 26))\(gigabytes(peak))")
        }

        print("\nspeech model on disk        \(gigabytes(store.bytesOnDisk(speechModel) ?? 0))")
        print("language model on disk      \(gigabytes(local.downloadBytes))")
        print("speech model alone          \(gigabytes(withSpeech))")
        print("language model adds         \(gigabytes(withBoth - withSpeech))")
        print("\nA 16 GB Mac has room. An 8 GB Mac does not, with anything else open.")
    }

    @discardableResult
    private func report(_ label: String) -> Int64 {
        let bytes = footprint()
        print("  \(label.padded(to: 26))\(gigabytes(bytes))")
        return bytes
    }

    private func footprint() -> Int64 { MemoryFootprint.current() ?? 0 }

    private func gigabytes(_ bytes: Int64) -> String {
        String(format: "%.2f GB", Double(bytes) / 1e9)
    }
}
