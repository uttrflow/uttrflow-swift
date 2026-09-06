import Foundation
import UttrflowSettings
import UttrflowUX
import Testing

@testable import Uttrflow

/// Three switches in Settings were stored, drawn, toggled — and read by nothing at all.
///
/// A control that reports success and changes nothing is worse than a missing one: the
/// user believes they have configured something, and only finds out they have not when
/// the behaviour they were promised does not happen. These tests exist so that a fourth
/// cannot be added the same way.
@MainActor
@Suite("Switches that have to reach something")
struct DeadSwitchTests {
    /// Every field of `Settings` that the user can toggle, and the thing outside the
    /// settings screens that reads it.
    ///
    /// Written out rather than derived, so adding a switch means answering the question
    /// this suite asks. A field named here with nothing behind it is the bug.
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

        // The settings screens read every field by definition — they draw it. What
        // matters is whether anything acts on it.
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

    /// The rebuilt tidier once left the dictionary out, so half-heard words stopped being offered the user's spellings.
    @Test("the tidier is built in one place, and that place hands it the personal dictionary")
    func everyCleanerCarriesTheDictionary() throws {
        let source = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appending(path: "Sources/Uttrflow/AppDelegate.swift")
        let text = try String(contentsOf: source, encoding: .utf8)
        let built = text.components(separatedBy: "TextTransformers.router(").count - 1
        #expect(built == 1, "a second place to build a tidier is a second place to forget the dictionary")
        #expect(text.contains("spellings: { [dictionary] in await dictionary.index() }"))
    }
}

/// A stand-in for macOS's login-item service, so the suite can watch what the app tells
/// it without the machine running the tests acquiring a login item.
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
    /// The defect this replaces: the preference was stored, drawn and toggled, and the
    /// system was never told, so the switch reported a change it had not made.
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

    /// `SMAppService` throws when asked for something it already has. Not a failure, but
    /// asking on every settings change and every launch would make it constant noise.
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
