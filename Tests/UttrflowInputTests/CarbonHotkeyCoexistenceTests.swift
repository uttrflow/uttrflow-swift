import Foundation
import UttrflowCore
import Testing

@testable import UttrflowInput

/// Dictation and the clipboard panel each hold a real shortcut at once. See `Docs/shortcuts.md`.
@MainActor
@Suite("Two shortcuts at once")
struct CarbonHotkeyCoexistenceTests {
    @Test("a second monitor can register while the first still holds its shortcut")
    func twoMonitorsCoexist() throws {
        let first = CarbonHotkeyMonitor()
        let second = CarbonHotkeyMonitor()
        defer {
            first.stop()
            second.stop()
        }

        // F13 and F14 with three modifiers: nothing on a stock Mac claims either.
        let quiet: Set<HotkeyModifier> = [.control, .option, .shift]
        try first.start(binding: HotkeyBinding(keyCode: 105, modifiers: quiet))
        try second.start(binding: HotkeyBinding(keyCode: 107, modifiers: quiet))
    }

    /// The shared handler belongs to the process, so restarting one monitor must not disarm the other.
    @Test("restarting one monitor leaves the other registered")
    func restartingOneLeavesTheOther() throws {
        let first = CarbonHotkeyMonitor()
        let second = CarbonHotkeyMonitor()
        defer {
            first.stop()
            second.stop()
        }
        let quiet: Set<HotkeyModifier> = [.control, .option, .shift]

        try first.start(binding: HotkeyBinding(keyCode: 105, modifiers: quiet))
        try second.start(binding: HotkeyBinding(keyCode: 107, modifiers: quiet))
        first.stop()
        try first.start(binding: HotkeyBinding(keyCode: 109, modifiers: quiet))

        // The proof that `second` still holds its key: nobody else can take it.
        let intruder = CarbonHotkeyMonitor()
        defer { intruder.stop() }
        #expect(throws: HotkeyError.shortcutUnavailable) {
            try intruder.start(binding: HotkeyBinding(keyCode: 107, modifiers: quiet))
        }
    }
}
