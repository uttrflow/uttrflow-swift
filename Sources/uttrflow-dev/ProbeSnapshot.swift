import ArgumentParser
private import ApplicationServices
private import Foundation
private import UttrflowContext

/// Records the focused field of the app in front as a replayable fixture, every text in it invented.
struct ProbeSnapshot: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "snapshot",
        abstract: "Record the focused field as a redacted Accessibility fixture. See Docs/surface-probe.md."
    )

    @Option(name: .long, help: "The application family the fixture stands for, such as \"native text area\".")
    var family: String

    @Option(name: .long, help: "Seconds to wait before recording, to click into the field to record.")
    var delay: Int = 3

    @Option(name: .long, help: "Where to write the JSON fixture; printed when omitted.")
    var output: String?

    func validate() throws {
        guard !family.trimmingCharacters(in: .whitespaces).isEmpty else {
            throw ValidationError("--family must name the application family.")
        }
        guard delay >= 0 else {
            throw ValidationError("--delay must be 0 or greater.")
        }
    }

    func run() async throws {
        guard AXIsProcessTrusted() else {
            print("Accessibility is not granted to this binary, so every read would return nothing.")
            throw ExitCode.failure
        }
        print("Recording in \(delay)s. Click into the field to record.")
        try await Task.sleep(for: .seconds(delay))
        guard let app = await MainActor.run(body: { FocusedFieldReader.frontmostApp() }),
            let snapshot = SurfaceProbe.snapshot(of: app, family: family)
        else {
            print("No focused field in the app in front.")
            throw ExitCode.failure
        }
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        let json = String(decoding: try encoder.encode(snapshot), as: UTF8.self) + "\n"
        guard let output else {
            print(json)
            return
        }
        try json.write(toFile: output, atomically: true, encoding: .utf8)
        print("Written to \(output). Run `make snapshot-fixture-audit` before committing it.")
    }
}
