import ArgumentParser
import Foundation
import UttrflowAI
import UttrflowCore

/// Cleans up text without recording anything, so the transformation can be judged on its own.
struct Clean: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        abstract: "Tidy a raw transcript, as if it had just been dictated."
    )

    @Argument(help: "The raw transcript. Reads standard input when omitted.")
    var text: String?

    @Option(name: .shortAndLong, help: "Force one transformer: foundationModels or rules.")
    var engine: String?

    // Context changes the output, so it has to be reachable from here without running the bake-off.
    @Option(name: .long, help: "Pretend the frontmost app is this one.")
    var app: String?

    @Option(name: .long, help: "Pretend the frontmost app has this bundle identifier.")
    var bundleID: String?

    @Option(name: .long, help: "Pretend the frontmost window is titled this.")
    var document: String?

    @Option(name: .long, help: "Pretend this text is selected on screen.")
    var selection: String?

    func run() async throws {
        let raw = try readInput()
        guard !raw.isEmpty else { throw CleanExit.message("Nothing to clean.") }

        var configuration = EngineConfiguration.default
        if let engine {
            guard let kind = TransformerKind(rawValue: engine), TransformerKind.selectable.contains(kind)
            else {
                throw ValidationError(
                    "Unknown transformer '\(engine)'. Known: "
                        + TransformerKind.selectable.map(\.rawValue).joined(separator: ", ")
                )
            }
            configuration.transformerPreference = [kind]
        }

        let router = TextTransformers.router(configuration: configuration)
        let clock = ContinuousClock()
        let start = clock.now
        let context = AppContext(
            applicationName: app, bundleIdentifier: bundleID,
            documentName: document, selectedText: selection
        )
        let result = try await router.transform(
            TransformationRequest(transcription: Transcription(text: raw), context: context)
        )
        let elapsed = start.duration(to: clock.now)

        print("  raw    \(raw)")
        // Printed from the context rather than the flags, so this is the line the model is given.
        if let described = AppContextDescriber.describe(context) {
            print("  seen   \(described)")
        }
        print("  clean  \(result.text)")
        print("  by     \(result.producedBy.rawValue) in \(format(elapsed))s")
    }

    private func readInput() throws -> String {
        if let text { return text.trimmingCharacters(in: .whitespacesAndNewlines) }
        let data = FileHandle.standardInput.readDataToEndOfFile()
        return String(decoding: data, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func format(_ duration: Duration) -> String {
        String(
            format: "%.2f",
            duration.inSeconds)
    }
}
