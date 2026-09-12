// The `insert` command: puts text into the frontmost app.
import ArgumentParser
import Foundation
import UttrflowCore
import UttrflowInput
import UttrflowPermissions

/// Puts text into whatever app is frontmost, so the last stage can be watched rather than inferred.
struct Insert: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        abstract: "Insert text into the frontmost app, after a countdown."
    )

    @Argument(help: "The text to insert.")
    var text: String

    @Option(name: .shortAndLong, help: "Seconds to wait so you can click into a text field.")
    var delay: Int = 4

    // The coordinator hides which strategy ran, so forcing one is how a broken paste is found.
    @Option(name: .long, help: "Force one strategy: accessibility, paste or clipboard.")
    var via: String?

    /// Says what waiting for the words found out, which is the only place the paste lag is visible.
    @Sendable private static func report(_ outcome: PasteConfirmation.Outcome) {
        switch outcome {
        case .landed(let waited):
            print("  words reached the caret after \(String(format: "%.2f", waited.inSeconds))s")
        case .notReported:
            print("  the field will not say what it holds, so the paste is unconfirmed")
        case .gaveUp(let waited):
            print("  no sign of the words after \(String(format: "%.2f", waited.inSeconds))s")
        }
    }

    func validate() throws {
        guard !text.isEmpty else { throw ValidationError("Nothing to insert.") }
        guard (0...60).contains(delay) else { throw ValidationError("--delay must be 0 to 60.") }
        if let via, !["accessibility", "paste", "clipboard"].contains(via) {
            throw ValidationError("--via must be accessibility, paste or clipboard.")
        }
    }

    func run() async throws {
        let gate = AccessibilityPermissionGate()
        if await gate.status() != .granted {
            print(PermissionError.accessibilityNotTrusted.userMessage)
            _ = await gate.request()
            throw CleanExit.message(
                "Grant access, then run this again. The terminal is what needs permission.")
        }

        print("Click into a text field. Inserting in \(delay)s…")
        for remaining in stride(from: delay, to: 0, by: -1) {
            Terminal.show("\r  \(remaining) ")
            try await Task.sleep(for: .seconds(1))
        }
        Terminal.clearLine()

        let coordinator =
            switch via {
            case "accessibility":
                TextInsertionCoordinator(strategies: [
                    AccessibilityTextInsertionEngine(focus: AXAccessibilityFocus())
                ])
            case "paste":
                TextInsertionCoordinator(strategies: [
                    PasteboardTextInsertionEngine(
                        focus: AXAccessibilityFocus(), pasteboard: SystemPasteboard(),
                        keystrokes: CGEventKeystrokeSender())
                ])
            case "clipboard":
                TextInsertionCoordinator(strategies: [
                    ClipboardTextInsertionEngine(pasteboard: SystemPasteboard())
                ])
            default:
                TextInsertion.coordinator(reporting: Self.report)
            }
        let clock = ContinuousClock()
        let start = clock.now
        do {
            let method = try await coordinator.insert(text)
            print("Inserted via \(method.rawValue).")
            print("  took \(String(format: "%.2f", start.duration(to: clock.now).inSeconds))s in all")
        } catch {
            print(error.userMessage)
            throw ExitCode.failure
        }
    }
}
