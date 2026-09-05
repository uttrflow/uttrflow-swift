// Tests that every Settings switch reaches something.

import Foundation
import UttrflowSettings
import UttrflowUX
import Testing

@testable import Uttrflow

/// Three switches in Settings were once read by nothing; these exist so a fourth cannot be.
@MainActor
@Suite("Switches that have to reach something")
struct DeadSwitchTests {
    /// Every toggle in `Settings` and the thing outside the settings screens that reads it, written out.
    @Test(
        "every toggle in Settings is read by something other than the settings screens",
        arguments: [
            "showsFloatingButton", "floatingButtonAnchor", "shrinksToGripWhenIdle",
            "minimisesWhileDictating", "playsSoundWhenRecordingStarts", "opensAtLogin",
            "transcriptRetentionDays", "hotkey", "hotkeyActivation", "clipboardHotkey",
        ])
    func everyToggleReachesSomething(field: String) throws {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()  // UttrflowTests
            .deletingLastPathComponent()  // Tests
            .deletingLastPathComponent()  // package root
            .appending(path: "Sources")

        // The settings screens read every field by definition; what matters is whether anything acts.
        let drawsSettings = ["SettingsPresenter", "SettingsEditor", "SettingsSession", "Settings"]
        var readers: [String] = []
        let files = FileManager.default.enumerator(at: root, includingPropertiesForKeys: nil)
        while let url = files?.nextObject() as? URL {
            let name = url.deletingPathExtension().lastPathComponent
            guard url.pathExtension == "swift",
                !drawsSettings.contains(where: { name.hasPrefix($0) }),
                let text = try? String(contentsOf: url, encoding: .utf8),
                text.contains(".\(field)")
            else { continue }
            readers.append(name)
        }

        #expect(!readers.isEmpty, "nothing outside the settings screens reads \(field)")
    }
}

/// A stand-in for macOS's login-item service, so the test machine acquires no login item.
private final class RecordedLoginItem: @unchecked Sendable {
    private let lock = NSLock()
    private var enabled: Bool
    private(set) var registrations = 0
    private(set) var removals = 0

    init(startingEnabled: Bool) { enabled = startingEnabled }

    var service: LaunchAtLogin {
        LaunchAtLogin(
            readStatus: { [self] in
                lock.withLock { enabled ? .enabled : .disabled }
            },
            register: { [self] in
                lock.withLock {
                    registrations += 1
                    enabled = true
                }
            },
            unregister: { [self] in
                lock.withLock {
                    removals += 1
                    enabled = false
                }
            })
    }

    var isEnabled: Bool { lock.withLock { enabled } }
}

@MainActor
@Suite("Telling macOS to open Uttrflow at login")
struct LaunchAtLoginWiringTests {
    /// The preference must reach the system, or the switch reports a change it has not made.
    @Test("the app registers a login item at launch when the preference asks for one")
    func registersWhenAsked() {
        let system = RecordedLoginItem(startingEnabled: false)
        let app = AppDelegate(container: Sandbox().root, loginItem: system.service)
        app.settingsChanged(to: Settings(opensAtLogin: true))

        #expect(system.isEnabled)
        #expect(system.registrations == 1)
    }

    @Test("turning the preference off removes the login item")
    func removesWhenTurnedOff() {
        let system = RecordedLoginItem(startingEnabled: true)
        let app = AppDelegate(container: Sandbox().root, loginItem: system.service)
        app.settingsChanged(to: Settings(opensAtLogin: false))

        #expect(!system.isEnabled)
        #expect(system.removals == 1)
    }

    /// `SMAppService` throws when asked for what it already has, so a matching preference is not re-applied.
    @Test("a preference that already matches the system is not re-applied")
    func doesNotRepeatItself() {
        let system = RecordedLoginItem(startingEnabled: true)
        let app = AppDelegate(container: Sandbox().root, loginItem: system.service)
        app.settingsChanged(to: Settings(opensAtLogin: true))
        app.settingsChanged(to: Settings(opensAtLogin: true))

        #expect(system.registrations == 0)
        #expect(system.removals == 0)
    }
}
