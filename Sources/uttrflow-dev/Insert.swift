// The `insert` command: puts text into the frontmost app.
import ArgumentParser
import Foundation
import UttrflowContext
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
    @Option(name: .long, help: "Force one strategy: accessibility, paste, typed or clipboard.")
    var via: String?

    @Flag(name: .long, help: "After inserting, press ⌘Z once and report how far it went.")
    var thenUndo = false

    /// Says what waiting for the words found out, which is the only place the paste lag is visible.
    @Sendable private static func report(_ outcome: PasteConfirmation.Outcome) {
        switch outcome {
        case .landed(let waited):
            print("  words reached the caret after \(String(format: "%.2f", waited.inSeconds))s")
        case .notReported:
            print("  the field will not say what it holds, so the paste is unconfirmed")
        case .gaveUp(let waited):
            print("  no sign of the words after \(String(format: "%.2f", waited.inSeconds))s")
        case .cancelled(let waited):
            print("  stopped looking for the words after \(String(format: "%.2f", waited.inSeconds))s")
        }
    }

    /// The strategy a `--via` name forces, or nil for the full route.
    static func method(named via: String?) -> TextInsertionMethod? {
        switch via {
        case "accessibility": .accessibility
        case "paste": .pasteboard
        case "clipboard": .clipboard
        case "typed": .typed
        default: nil
        }
    }

    /// Reads back the text left of the caret, so any edit the field makes to typed keys shows.
    static func readBack(_ text: String, from focus: some AccessibilityFocus) {
        guard let found = focus.precedingText(text.count) else {
            print("  read back: the field will not say what it holds")
            return
        }
        print("  read back: \(found.debugDescription)")
        print("  changed by the field: \(found != text)")
    }

    func validate() throws {
        guard !text.isEmpty else { throw ValidationError("Nothing to insert.") }
        guard (0...60).contains(delay) else { throw ValidationError("--delay must be 0 to 60.") }
        if let via, !["accessibility", "paste", "typed", "clipboard"].contains(via) {
            throw ValidationError("--via must be accessibility, paste, typed or clipboard.")
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

        // The app's own factory, so a forced strategy still reads the secure field; typing is built only when forced.
        let method = Self.method(named: via)
        let focus = AXAccessibilityFocus()
        let coordinator = TextInsertion.coordinator(
            focus: focus, reporting: Self.report, clipboardFallback: method != .typed, only: method)
        if thenUndo {
            await MainActor.run { CGEventKeystrokeSender.startObservingLayout() }
            try await measureUndo(coordinator)
            return
        }
        let clock = ContinuousClock()
        let start = clock.now
        do {
            let attempt = try await coordinator.insert(text)
            print("Inserted via \(attempt.method.rawValue), \(attempt.arrival.rawValue).")
            let destination = attempt.destination
            let name = destination?.applicationName ?? destination?.bundleIdentifier ?? "unknown"
            print("  destination: \(name)")
            print("  secure: \(attempt.intoSecureField)")
            print("  took \(String(format: "%.2f", start.duration(to: clock.now).inSeconds))s in all")
            if attempt.method == .typed { Self.readBack(text, from: focus) }
        } catch {
            print(error.userMessage)
            throw ExitCode.failure
        }
    }

    /// One insertion followed by one ⌘Z, read back through Accessibility, which fills an `Undo` cell.
    private func measureUndo(_ coordinator: TextInsertionCoordinator) async throws {
        let sender = CGEventKeystrokeSender()
        let report = try await UndoProbe.run(
            read: {
                guard let snapshot = await FocusedFieldReader.read(), let value = snapshot.value,
                    let selection = snapshot.selection
                else { return nil }
                return UndoFieldReading(
                    value: value, selectionLocation: selection.location, selectionLength: selection.length)
            },
            insert: {
                let attempt = try await coordinator.insert(text)
                print("Inserted via \(attempt.method.rawValue), \(attempt.arrival.rawValue).")
            },
            undo: { try sender.sendUndo() },
            settle: { try await Task.sleep(for: .milliseconds(500)) })
        print("Undo: \(report.steps.rawValue)")
        if let restored = report.selectionRestored { print("  selection restored: \(restored)") }
    }
}
