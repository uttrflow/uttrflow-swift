// The `latency` command: times the microphone opening and its first audio on this Mac.
import ArgumentParser
private import Foundation
private import UttrflowAudio
private import UttrflowCore
private import UttrflowEval

/// Times the stages before a word exists, which `bench` and `dictate` cannot reach because they play files.
struct Latency: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        abstract: "Open the real microphone repeatedly and time the opening and its first audio."
    )

    @Option(name: .shortAndLong, help: "How many times to open and close the microphone.")
    var opens: Int = 20

    @Option(help: "UID of the input to open, from --list-devices; the default input when absent.")
    var device: String?

    @Option(help: "Seconds closed before each opening, to time a device that sleeps cold.")
    var idle: Int = 0

    @Flag(help: "Print the input devices present, with their UIDs, and exit.")
    var listDevices = false

    /// How often the probe looks for the first sample, which is the resolution of that figure.
    private static let poll = Duration.milliseconds(1)
    /// How long one opening may go without a sample before it is counted as a failure.
    private static let giveUp = Duration.seconds(5)

    func validate() throws {
        guard (1...500).contains(opens) else { throw ValidationError("--opens must be 1 to 500.") }
        guard (0...600).contains(idle) else { throw ValidationError("--idle must be 0 to 600.") }
    }

    func run() async throws {
        let catalog = SystemInputDeviceCatalog()
        if listDevices {
            for input in catalog.inputDevices() { print("\(input.uid)\t\(input.name)") }
            return
        }
        if let device, !catalog.inputDevices().contains(where: { $0.uid == device }) {
            throw ValidationError("No input device has UID \(device); run with --list-devices.")
        }
        try await requireMicrophoneAccess(announcing: "Asking for microphone access…")
        // One engine for every opening, as the app keeps one for its lifetime.
        let chosen = device
        let engine = AVAudioCaptureEngine(
            source: AVAudioEngineMicrophoneSource(preferredUID: { chosen }, catalog: catalog))
        let log = MeasurementLog()
        var firstAudio: [Duration] = []
        var silent = 0
        print("Opening \(device ?? "the default input") \(opens) times, \(idle) s closed before each…\n")
        for index in 1...opens {
            if idle > 0 { try await Task.sleep(for: .seconds(idle)) }
            let waited = try await openOnce(engine, recordingInto: log)
            if let waited { firstAudio.append(waited) } else { silent += 1 }
            let opened = await log.measurements.last?.duration ?? .zero
            print(
                "  \(String(index).leftPadded(to: 3))  open \(Self.milliseconds(opened))"
                    + "  first audio \(waited.map(Self.milliseconds) ?? "none")")
        }
        await report(log.measurements, firstAudio: firstAudio, silent: silent)
    }

    /// Opens, waits for the first sample, and closes; `nil` when no sample came before ``giveUp``.
    private func openOnce(
        _ engine: AVAudioCaptureEngine, recordingInto log: MeasurementLog
    ) async throws -> Duration? {
        let clock = ContinuousClock()
        let start = clock.now
        try await log.measuring(.microphoneOpen, clock: clock) { try await engine.start() }
        var heard: Duration?
        while start.duration(to: clock.now) < Self.giveUp {
            if await engine.capturedFrameCount > 0 {
                heard = start.duration(to: clock.now)
                break
            }
            try await Task.sleep(for: Self.poll)
        }
        await engine.cancel()
        return heard
    }

    private func report(_ measurements: [StageMeasurement], firstAudio: [Duration], silent: Int) async {
        print("")
        if let open = StageLatency.summarise(measurements, stage: .microphoneOpen) {
            print(
                "microphoneOpen       median \(Self.milliseconds(open.typical))"
                    + "  slowest \(Self.milliseconds(open.slowest))  samples \(open.samples)")
        }
        if let audio = DurationSummary.over(firstAudio, failures: silent) {
            print(
                "start to first audio median \(Self.milliseconds(audio.typical))"
                    + "  slowest \(Self.milliseconds(audio.slowest))  samples \(audio.samples)"
                    + "  silent \(audio.failures)")
        }
        let host = ProcessInfo.processInfo
        print(
            "\nhost: \(host.processorCount) cores, \(host.physicalMemory >> 30) GB,"
                + " macOS \(host.operatingSystemVersionString), poll \(Self.milliseconds(Self.poll))")
    }

    private static func milliseconds(_ duration: Duration) -> String {
        String(format: "%6.1f ms", duration.inSeconds * 1000)
    }
}

/// Every measurement in the order taken, so the probe summarises through the same ``StageLatency`` as the app.
private actor MeasurementLog: MetricsRecording {
    private(set) var measurements: [StageMeasurement] = []

    func record(_ measurement: StageMeasurement) {
        measurements.append(measurement)
    }
}
