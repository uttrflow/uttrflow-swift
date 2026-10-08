// The `load-priority` command: the speech model's load timed at the priority the app would give it.
import ArgumentParser
import Foundation
import UttrflowCore
import UttrflowEval
import UttrflowSpeech

/// Loads the recogniser repeatedly at two task priorities, alternating, and prints one line per load.
struct LoadPriority: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "load-priority",
        abstract: "Time the speech model's load at utility and at default priority, alternating.",
        discussion: """
            Each load builds a fresh recogniser, so every load after the first is warm. One LOAD line \
            per load gives the priority, the wall and processor seconds, and the one-minute load \
            average when it started. See Docs/startup.md.
            """
    )

    @Option(name: .customLong("model"), help: "Model variant. Defaults to the shipping model.")
    var modelVariant: String?

    @OptionGroup var modelsDirectory: ModelsDirectoryOptionGroup

    @Option(name: .long, help: "Loads per priority.")
    var runs = 5

    func run() async throws {
        let model = try resolve(modelVariant)
        let store = try modelsDirectory.store()
        guard store.isInstalled(model) else { throw notInstalled(model, in: store) }
        let priorities: [(name: String, priority: TaskPriority?)] = [("default", nil), ("utility", .utility)]
        // One load first, untimed, so a recompile is not charged to whichever priority comes first.
        try await load(model, from: store, at: nil)
        for _ in 0..<max(runs, 1) {
            for (name, priority) in priorities {
                var average = [Double](repeating: 0, count: 1)
                _ = getloadavg(&average, 1)
                let before = CPUFootprint.reading()
                let started = ContinuousClock.now
                try await load(model, from: store, at: priority)
                let wall = started.duration(to: .now).inSeconds
                let cpu = CPUCost.between(before, CPUFootprint.reading(), wallSeconds: wall)?.cpuSeconds ?? -1
                print(
                    "LOAD priority=\(name) wall=\(String(format: "%.2f", wall))s "
                        + "cpu=\(String(format: "%.2f", cpu))s loadavg=\(String(format: "%.1f", average[0]))")
            }
        }
    }

    private func load(
        _ model: SpeechModel, from store: FileSystemSpeechModelStore, at priority: TaskPriority?
    ) async throws {
        let engine = SpeechEngineFactory.make(
            kind: .whisperKit, model: model, modelFolder: store.location(of: model))
        try await Task(priority: priority) { try await engine.prepare() }.value
    }
}
