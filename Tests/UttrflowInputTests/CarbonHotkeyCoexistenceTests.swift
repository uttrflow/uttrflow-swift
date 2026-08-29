import Foundation
import UttrflowCore
import Testing

@testable import UttrflowInput

/// Uttrflow registers more than one shortcut: dictation has one and the clipboard panel
/// has another. They must both work.
///
/// This is the test that was missing. `InstallEventHandler` refuses the same handler
/// function on the same Carbon target twice — `eventHandlerAlreadyInstalledErr`, −9866 —
/// and each monitor used to install its own. So the second monitor to start silently got
/// nothing at all, and which feature lost depended on the order the app happened to
/// register in. Dictation lost: ⌥Space stopped doing anything, with no error anywhere,
/// on a build where every other test was green.
///
/// Registering a real hot key with the window server is what makes this meaningful, so
/// it is deliberately not a substitute. The combinations below are ones nothing else is
/// plausibly holding, and both are released before the test returns.
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

    /// Restarting is how a changed shortcut takes effect, and it must not cost the other
    /// monitor its registration — the shared handler belongs to the process, so removing
    /// it on one monitor's behalf is the same bug from the other end.
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
