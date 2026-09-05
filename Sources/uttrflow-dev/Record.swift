import ArgumentParser
private import Foundation
private import UttrflowAudio
private import UttrflowCore

/// Records from the microphone and reports what was captured.
struct Record: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        abstract: "Record the microphone and write a WAV file."
    )

    @Option(name: .shortAndLong, help: "How long to record.")
    var seconds: Double = 5

    @Option(name: .shortAndLong, help: "Where to write the WAV. Defaults to the working directory.")
    var output: String?

    func validate() throws {
        guard seconds > 0, seconds <= 600 else {
            throw ValidationError("--seconds must be between 0 and 600.")
        }
    }

    func run() async throws {
        try await requireMicrophoneAccess(announcing: "Asking for microphone access…")

        let engine = AVAudioCaptureEngine(source: AVAudioEngineMicrophoneSource())
        try await engine.start()
        print("Recording for \(format(seconds))s — speak now.\n")

        let tick = Duration.milliseconds(100)
        let deadline = ContinuousClock.now + .milliseconds(Int(seconds * 1000))
        while ContinuousClock.now < deadline {
            try await Task.sleep(for: tick)
            let level = await engine.peakLevel
            let elapsed = await Double(engine.capturedFrameCount) / Double(AudioSamples.canonicalSampleRate)
            Terminal.show("\r  \(meter(level))  \(format(elapsed))s ")
        }

        let audio = try await engine.stop()
        Terminal.clearLine()

        let url = URL(fileURLWithPath: output ?? defaultFilename())
        try WAVEncoder.encode(audio).write(to: url)

        let duration = audio.duration.inSeconds
        print("Captured \(audio.samples.count) samples — \(format(duration))s at \(audio.sampleRate) Hz")
        print("Loudest sample  \(String(format: "%.3f", loudestSample(in: audio)))")
        print("Written to      \(url.path)")
        if duration < seconds * 0.9 {
            print("\nNote: that is shorter than requested — the input may have dropped out.")
        }
        if audio.samples.allSatisfy({ $0 == 0 }) {
            print("\nEvery sample is silent. Check the input device is not muted.")
        }
    }

    private func loudestSample(in audio: AudioSamples) -> Float {
        audio.samples.reduce(0) { Swift.max($0, Swift.abs($1)) }
    }

    private func defaultFilename() -> String {
        let stamp = Date().formatted(.iso8601.dateSeparator(.omitted).timeSeparator(.omitted))
        return "uttrflow-\(stamp).wav"
    }

    private func format(_ value: Double) -> String {
        String(format: "%.1f", value)
    }

    /// A 24-cell bar. Peak level is already normalised to `0...1`.
    private func meter(_ level: Float) -> String {
        let width = 24
        let filled = Int((Double(level) * Double(width)).rounded())
        return "[" + String(repeating: "▇", count: filled)
            + String(repeating: " ", count: width - filled) + "]"
    }
}
