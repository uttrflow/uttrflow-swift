import ArgumentParser
import Foundation
import UttrflowContext
import UttrflowCore
import UttrflowPermissions

/// Shows what Uttrflow can see of the app you are working in, which is invisible in the text.
struct Context: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        abstract: "Report what Uttrflow can see of the frontmost app."
    )

    @Option(name: .shortAndLong, help: "Seconds to wait so you can bring another app forward.")
    var delay: Int = 3

    func run() async throws {
        if delay > 0 {
            print("Bring the app you want to inspect to the front. Reading in \(delay)s…")
            try await Task.sleep(for: .seconds(delay))
        }

        let clock = ContinuousClock()
        let start = clock.now
        let context = await MacContextEngine().currentContext()
        let elapsed = start.duration(to: clock.now)

        print("")
        print("  application   \(context.applicationName ?? "—")")
        print("  bundle id     \(context.bundleIdentifier ?? "—")")
        print("  window        \(context.documentName ?? "—")")
        print("  selected      \(context.selectedText.map(preview) ?? "—")")
        print("  read in       \(format(elapsed))s")

        let accessibility = await AccessibilityPermissionGate().status()
        if accessibility != .granted {
            print("\nWithout Accessibility access the window title and selection stay empty.")
            print("The application name does not need it.")
        }
    }

    private func preview(_ text: String) -> String {
        let collapsed = text.split(whereSeparator: \.isWhitespace).joined(separator: " ")
        return collapsed.count > 60 ? collapsed.prefix(60) + "…" : collapsed
    }

    private func format(_ duration: Duration) -> String {
        String(
            format: "%.3f",
            duration.inSeconds)
    }
}
