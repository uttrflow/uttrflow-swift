// Tests that every Settings switch reaches something.

import AppKit
import Foundation
import Synchronization
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
            "dictationEnabled", "clipboardEnabled", "sharesUsageStatistics", "handsFreeEnabled",
            "learnsFromDictation",
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

@MainActor
@Suite("Shrinking the floating button to a grip")
struct GripSettingWiringTests {
    @Test("turning the grip off and on again reaches the running button without a relaunch")
    func gripFollowsTheSetting() {
        let sandbox = Sandbox()
        let app = AppDelegate(container: sandbox.root)

        app.settingsChanged(to: Settings(showsFloatingButton: false, shrinksToGripWhenIdle: false))
        #expect(!app.dockShrinksToGrip)

        app.settingsChanged(to: Settings(showsFloatingButton: false, shrinksToGripWhenIdle: true))
        #expect(app.dockShrinksToGrip)
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

    func setEnabledExternally(_ isEnabled: Bool) {
        lock.withLock { enabled = isEnabled }
    }
}

/// Settings persisted by the app, held in memory for the login-item synchronization test.
private final class LoginSettingsStore: KeyValueStore {
    private let values = Mutex<[String: Data]>([:])

    init(_ settings: Settings) {
        values.withLock { $0[UserDefaultsSettingsStore.defaultKey] = try? JSONEncoder().encode(settings) }
    }

    func data(forKey key: String) -> Data? { values.withLock { $0[key] } }

    func set(_ data: Data?, forKey key: String) { values.withLock { $0[key] = data } }
}

@MainActor
@Suite("Telling macOS to open Uttrflow at login")
struct LaunchAtLoginWiringTests {
    /// The preference must reach the system, or the switch reports a change it has not made.
    @Test("the app registers a login item at launch when the preference asks for one")
    func registersWhenAsked() {
        let system = RecordedLoginItem(startingEnabled: false)
        let sandbox = Sandbox()
        let app = AppDelegate(container: sandbox.root, loginItem: system.service)
        app.settingsChanged(to: Settings(opensAtLogin: true))

        #expect(system.isEnabled)
        #expect(system.registrations == 1)
    }

    @Test("turning the preference off removes the login item")
    func removesWhenTurnedOff() {
        let system = RecordedLoginItem(startingEnabled: true)
        let sandbox = Sandbox()
        let app = AppDelegate(container: sandbox.root, loginItem: system.service)
        app.settingsChanged(to: Settings(opensAtLogin: false))

        #expect(!system.isEnabled)
        #expect(system.removals == 1)
    }

    /// `SMAppService` throws when asked for what it already has, so a matching preference is not re-applied.
    @Test("a preference that already matches the system is not re-applied")
    func doesNotRepeatItself() {
        let system = RecordedLoginItem(startingEnabled: true)
        let sandbox = Sandbox()
        let app = AppDelegate(container: sandbox.root, loginItem: system.service)
        app.settingsChanged(to: Settings(opensAtLogin: true))
        app.settingsChanged(to: Settings(opensAtLogin: true))

        #expect(system.registrations == 0)
        #expect(system.removals == 0)
    }

    @Test("returning to the app adopts a login-item change made in System Settings")
    func adoptsExternalDisable() {
        let system = RecordedLoginItem(startingEnabled: true)
        let store = UserDefaultsSettingsStore(store: LoginSettingsStore(Settings(opensAtLogin: true)))
        let sandbox = Sandbox()
        let app = AppDelegate(
            container: sandbox.root, loginItem: system.service, settingsStore: store)
        app.settingsChanged(to: store.load())

        system.setEnabledExternally(false)
        app.applicationDidBecomeActive(Notification(name: NSApplication.didBecomeActiveNotification))

        #expect(store.load().opensAtLogin == false)
        #expect(!system.isEnabled)
        #expect(system.registrations == 0)
    }
}
