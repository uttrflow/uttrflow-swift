// Logs the strokes the shortcut tap delivers and what the recogniser makes of them. See Docs/shortcuts.md.
import ArgumentParser
private import ApplicationServices
private import Foundation
private import Synchronization
private import UttrflowCore
private import UttrflowEval
private import UttrflowInput

/// Records the modifier sequence one gesture produces, so an accessibility setting's effect is read, not guessed.
struct ProbeModifiers: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "modifiers",
        abstract: "Log every stroke the shortcut tap sees and the default recogniser's verdict on each."
    )

    @Option(name: .long, help: "How long to watch for, in seconds.")
    var seconds: Int = 30

    @OptionGroup var log: ProbeLogOptions

    func validate() throws {
        guard seconds >= 1 else {
            throw ValidationError("--seconds must be 1 or greater.")
        }
    }

    func run() async throws {
        guard AXIsProcessTrusted() else {
            print("Accessibility is not granted to this binary; the shortcut tap cannot be created.")
            throw ExitCode.failure
        }
        let load = HostLoad.current()
        let binding = ShortcutSet.default.first(for: .dictate) ?? .controlOptionHold
        let recorder = StrokeRecorder(binding: binding)
        let keyboard = SystemKeyboard()
        do {
            try keyboard.start { recorder.receive($0) }
        } catch {
            print("The tap could not be created even though Accessibility is granted.")
            throw ExitCode.failure
        }
        print("Sticky Keys: \(StickyKeysSetting.describe())")
        print("Watching \(seconds)s for the dictation binding (key \(binding.keyCode)). Press it now.\n")
        print(StrokeRecorder.header)
        try await Task.sleep(for: .seconds(seconds))
        keyboard.stop()
        let summary = recorder.summary()
        print("\n\(summary)")
        log.printRow(result: "Sticky Keys \(StickyKeysSetting.describe()); \(summary)", loadBefore: load)
    }
}

/// Prints each stroke as it arrives, with the recogniser's event beside it.
private final class StrokeRecorder: Sendable {
    private struct State {
        var recogniser: HotkeyRecogniser
        var start: ContinuousClock.Instant?
        var strokes = 0
        var events: [HotkeyEvent] = []
    }

    private let state: Mutex<State>

    init(binding: HotkeyBinding) {
        state = Mutex(State(recogniser: HotkeyRecogniser(binding: binding)))
    }

    /// The column names the rows below line up under.
    static let header = "ms      phase             key  keyDown  modifiers              fn     event"

    /// Feeds one stroke through the recogniser and prints the row it makes.
    func receive(_ stroke: KeyEvent) {
        let now = ContinuousClock.now
        let row = state.withLock { current in
            let start = current.start ?? now
            current.start = start
            current.strokes += 1
            let event = current.recogniser.receive(stroke)
            if let event { current.events.append(event) }
            return Self.row(stroke, event: event, milliseconds: (now - start) / .milliseconds(1))
        }
        print(row)
    }

    /// One stroke as a fixed-width row, ready to paste into a replay fixture.
    static func row(_ stroke: KeyEvent, event: HotkeyEvent?, milliseconds: Double) -> String {
        let modifiers = HotkeyModifier.allCases.filter(stroke.modifiers.contains).map(\.rawValue)
        return [
            pad(String(Int(milliseconds)), 7), pad("\(stroke.phase)", 17), pad(String(stroke.keyCode), 4),
            pad(String(stroke.isKeyDown), 8), pad(modifiers.joined(separator: ","), 22),
            pad(String(stroke.isFunctionDown), 6), event.map { "\($0)" } ?? "-",
        ].joined(separator: " ")
    }

    /// How many strokes arrived and the events the recogniser reported, in order.
    func summary() -> String {
        let seen = state.withLock { ($0.strokes, $0.events) }
        let events = seen.1.map { "\($0)" }.joined(separator: " ")
        return "\(seen.0) strokes; events: \(events.isEmpty ? "none" : events)"
    }

    private static func pad(_ text: String, _ width: Int) -> String {
        text.padding(toLength: max(width, text.count), withPad: " ", startingAt: 0)
    }
}

/// Reads, never writes, whether Sticky Keys is on, so the log says which condition it was taken under.
private enum StickyKeysSetting {
    static func describe() -> String {
        guard let domain = UserDefaults(suiteName: "com.apple.universalaccess"),
            domain.object(forKey: "stickyKey") != nil
        else { return "unreadable" }
        return domain.bool(forKey: "stickyKey") ? "on" : "off"
    }
}
