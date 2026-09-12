import Foundation
import Synchronization
import Testing
import UttrflowTestSupport

@testable import UttrflowCore
import UttrflowPredict
@testable import UttrflowSettings

// Covers the settings value, the store around it, and the one adapter that touches real defaults.
/// A key-value store in memory, so no test leaves a defaults domain behind it.
private final class InMemoryKeyValueStore: KeyValueStore {
    private let contents: Mutex<[String: Data]>

    /// Starts from `initial`, which is empty unless a test is standing in for an earlier launch.
    init(_ initial: [String: Data] = [:]) {
        contents = Mutex(initial)
    }

    /// Starts from one JSON blob under `key`, which is the store's own key unless a test says otherwise.
    convenience init(json: String, forKey key: String = UserDefaultsSettingsStore.defaultKey) {
        self.init([key: Data(json.utf8)])
    }

    /// Every key written so far.
    var keys: Set<String> {
        contents.withLock { Set($0.keys) }
    }

    /// The bytes under `key`, or `nil`.
    func data(forKey key: String) -> Data? {
        contents.withLock { $0[key] }
    }

    /// Stores `data` under `key`, or removes it when `nil`.
    func set(_ data: Data?, forKey key: String) {
        contents.withLock { $0[key] = data }
    }
}

/// The settings a stored blob decodes to.
private func decode(_ json: String) throws -> Settings {
    try JSONDecoder().decode(Settings.self, from: Data(json.utf8))
}

@Suite("Settings")
struct SettingsTests {
    @Test("ships the defaults the design promises")
    func defaults() {
        let settings = Settings.default

        #expect(settings.engines == .default)
        #expect(settings.profile == .default)
        #expect(settings.hotkeyActivation == .holdToTalk)
        #expect(settings.showsFloatingButton)
        #expect(settings.floatingButtonAnchor == .bottomRight)
        #expect(settings.shrinksToGripWhenIdle)
        #expect(settings.minimisesWhileDictating)
        #expect(settings.playsSoundWhenRecordingStarts)
        #expect(settings.opensAtLogin)
        #expect(settings.transcriptRetentionDays == 7)
        #expect(settings.cleaning == .default)
        #expect(settings.destinations == .none)
    }

    @Test("keeps a clean-up step switched off and an app treated as somewhere else")
    func keepsTheClearUpChoices() throws {
        var settings = Settings.default
        settings.cleaning = CleaningSteps.default.setting(.fillers, isOn: false)
        settings.destinations = DestinationOverrides.none.setting(
            .document, for: "com.example.App", named: "App")

        let restored = try JSONDecoder().decode(
            Settings.self, from: JSONEncoder().encode(settings))

        #expect(!restored.cleaning.runs(.fillers))
        #expect(restored.destinations.destination(forBundleIdentifier: "com.example.App") == .document)
    }

    @Test("a build that never had these fields gets everything on and no overrides")
    func payloadWithoutTheClearUpChoices() throws {
        let settings = try decode(#"{"opensAtLogin": false}"#)
        #expect(settings.cleaning == .default)
        #expect(settings.destinations == .none)
    }

    @Test("an unreadable clean-up choice costs only that choice")
    func corruptCleaningField() throws {
        let settings = try decode(
            #"{"cleaning": "nonsense", "destinations": 7, "transcriptRetentionDays": 21}"#)
        #expect(settings.cleaning == .default)
        #expect(settings.destinations == .none)
        #expect(settings.transcriptRetentionDays == 21)
    }

    @Test("keeps every field through an encode and a decode")
    func roundTrip() throws {
        let settings = Settings(
            engines: EngineConfiguration(speech: .appleSpeech, transformerPreference: [.rules]),
            profile: UserProfile(profession: "surgeon", preferredLanguages: [.hindi]),
            hotkeyActivation: .pressToToggle,
            showsFloatingButton: false,
            floatingButtonAnchor: .rightEdge,
            shrinksToGripWhenIdle: false,
            minimisesWhileDictating: false,
            playsSoundWhenRecordingStarts: false,
            opensAtLogin: false,
            transcriptRetentionDays: 90
        )

        let restored = try JSONDecoder().decode(
            Settings.self, from: JSONEncoder().encode(settings)
        )

        #expect(restored == settings)
    }

    /// Switching automatic updates off survives a save and a load.
    @Test("keeps automatic updates switched off across a save and a load")
    func automaticUpdatesStayOff() throws {
        let settings = Settings(installsUpdatesAutomatically: false)

        let restored = try JSONDecoder().decode(
            Settings.self, from: JSONEncoder().encode(settings)
        )

        #expect(!restored.installsUpdatesAutomatically)
    }

    /// The upgrade case: a build that added settings must still find the ones the user chose.
    @Test("keeps what an older build wrote and defaults what it never knew")
    func olderPayload() throws {
        let settings = try decode(
            """
            {"hotkeyActivation": "pressToToggle", "opensAtLogin": false}
            """
        )

        #expect(settings.hotkeyActivation == .pressToToggle)
        #expect(!settings.opensAtLogin)
        #expect(settings.floatingButtonAnchor == .bottomRight)
        #expect(settings.transcriptRetentionDays == 7)
        #expect(settings.engines == .default)
        #expect(settings.profile == .default)
    }

    @Test("defaults every field for an empty object")
    func emptyPayload() throws {
        #expect(try decode("{}") == .default)
    }

    /// One unreadable value must not cost the user the ten choices either side of it.
    @Test("keeps the readable fields when one of them is corrupt")
    func corruptField() throws {
        let settings = try decode(
            """
            {"showsFloatingButton": "yes please", "floatingButtonAnchor": "bottomLeft",
             "transcriptRetentionDays": 21}
            """
        )

        #expect(settings.showsFloatingButton)
        #expect(settings.floatingButtonAnchor == .bottomLeft)
        #expect(settings.transcriptRetentionDays == 21)
    }

    @Test("defaults an anchor this build has never heard of")
    func unknownAnchor() throws {
        #expect(try decode(#"{"floatingButtonAnchor": "topLeft"}"#).floatingButtonAnchor == .bottomRight)
    }

    /// An unparseable language subtag sinks the whole profile; the rest must not go down with it.
    @Test("defaults a profile whose contents cannot be read")
    func corruptProfile() throws {
        let settings = try decode(
            """
            {"profile": {"preferredLanguages": ["123"]}, "opensAtLogin": false}
            """
        )

        #expect(settings.profile == .default)
        #expect(!settings.opensAtLogin)
    }

    @Test("falls back to the defaults when the stored value is not an object")
    func nonObjectPayload() throws {
        #expect(try decode("[1, 2, 3]") == .default)
    }

    /// Honouring a zero would empty the user's history the moment the app launched.
    @Test(
        "refuses a retention that would delete the user's history at once",
        arguments: [0, -1, -3650]
    )
    func hostileRetention(days: Int) throws {
        let settings = try decode(
            """
            {"transcriptRetentionDays": \(days)}
            """
        )

        #expect(settings.transcriptRetentionDays == 7)
    }

    /// Keyed decoding never asks for a key this build has no case for. See `Docs/settings-decoding.md`.
    @Test("keeps every readable choice beside a key this build has no case for")
    func unknownKeyIsSkipped() throws {
        let settings = try decode(
            """
            {"recordingRetentionDays": 30, "transcriptRetentionDays": 21,
             "opensAtLogin": false, "floatingButtonAnchor": "bottomLeft"}
            """
        )

        #expect(settings.transcriptRetentionDays == 21)
        #expect(!settings.opensAtLogin)
        #expect(settings.floatingButtonAnchor == .bottomLeft)
    }

    /// A dropped key is a door left open, and a hostile value must not come back in through it.
    @Test("ignores a hostile value stored under a key this build has no case for")
    func hostileUnknownKeyIsSkipped() throws {
        let settings = try decode(
            """
            {"recordingRetentionDays": 0, "opensAtLogin": false}
            """
        )

        #expect(settings == Settings(opensAtLogin: false))
    }

    @Test("keeps a retention the user actually chose", arguments: [1, 30, 365])
    func acceptedRetention(days: Int) {
        #expect(Settings.retention(days) == days)
    }

    /// Each of these decodes cleanly and could never fire, leaving nothing to press.
    @Test(
        "refuses a shortcut that decodes cleanly and could never fire",
        arguments: [
            // No modifier: would fire in the middle of an ordinary word.
            #"{"keyCode": 49, "modifiers": []}"#,
            // Beyond the 7-bit range a keyboard can send.
            #"{"keyCode": 999, "modifiers": ["command"]}"#,
            // Command held down on its own, which is not a shortcut.
            #"{"keyCode": 200, "modifiers": ["command"]}"#,
            // Option's key code carrying Command: the pair a recorder writes reading a key going up.
            #"{"keyCode": 58, "modifiers": ["command"]}"#,
            // Caps Lock, which sets no modifier flag and so can never be seen held.
            #"{"keyCode": 57, "modifiers": []}"#,
        ]
    )
    func hostileHotkey(hotkey: String) throws {
        let settings = try decode(#"{"hotkey": \#(hotkey), "opensAtLogin": false}"#)

        #expect(settings.hotkey == .optionSpace)
        // The rest of the file is still the user's: one bad field costs them one field.
        #expect(!settings.opensAtLogin)
    }

    @Test("keeps a shortcut the user could actually press")
    func customHotkey() throws {
        let settings = try decode(#"{"hotkey": {"keyCode": 8, "modifiers": ["command", "shift"]}}"#)

        #expect(settings.hotkey == HotkeyBinding(keyCode: 8, modifiers: [.command, .shift]))
    }

    @Test("defaults a shortcut that cannot be read at all")
    func corruptHotkey() throws {
        #expect(try decode(#"{"hotkey": "option-space"}"#).hotkey == .optionSpace)
    }

    @Test("ships Option+Space when nothing has been stored")
    func defaultHotkey() throws {
        #expect(Settings.default.hotkey == .optionSpace)
        #expect(try decode("{}").hotkey == .optionSpace)
    }

    /// One number for both would empty the panel on the user's behalf, having never asked.
    @Test("the clipboard keeps its own retention period, not the transcripts' one")
    func clipboardRetentionIsItsOwn() throws {
        let settings = try decode(#"{"transcriptRetentionDays": 1}"#)

        #expect(settings.transcriptRetentionDays == 1)
        #expect(settings.clipboardRetentionDays == Settings.defaultRetentionDays)
    }

    @Test("a clipboard retention that would empty the panel on launch is refused")
    func hostileClipboardRetention() throws {
        #expect(
            try decode(#"{"clipboardRetentionDays": 0}"#).clipboardRetentionDays
                == Settings.defaultRetentionDays)
        #expect(try decode(#"{"clipboardRetentionDays": 30}"#).clipboardRetentionDays == 30)
    }

    @Test("ships Shift+Command+V for the clipboard when nothing has been stored")
    func defaultClipboardHotkey() throws {
        #expect(Settings.default.clipboardHotkey == .shiftCommandV)
        #expect(try decode("{}").clipboardHotkey == .shiftCommandV)
    }

    /// The clipboard shortcut has no obligation to exist, so an unusable one is dropped, not moved.
    @Test(
        "drops an unusable clipboard shortcut rather than substituting one",
        arguments: [
            #"{"keyCode": 9, "modifiers": []}"#,
            #"{"keyCode": 999, "modifiers": ["command"]}"#,
            #"{"keyCode": 200, "modifiers": ["command"]}"#,
        ]
    )
    func hostileClipboardHotkey(hotkey: String) throws {
        let settings = try decode(#"{"clipboardHotkey": \#(hotkey)}"#)

        #expect(settings.clipboardHotkey == nil)
        #expect(settings.clipboardHotkey != .optionSpace)
    }

    /// Carbon registers both and then fires both, so one keypress would do two things.
    @Test("refuses a clipboard shortcut the dictation shortcut already owns")
    func collidingClipboardHotkey() throws {
        let both = #"{"keyCode": 9, "modifiers": ["command", "shift"]}"#
        let settings = try decode(#"{"hotkey": \#(both), "clipboardHotkey": \#(both)}"#)

        // Dictation keeps the key: it is the one with no second way in.
        #expect(settings.hotkey == .shiftCommandV)
        #expect(settings.clipboardHotkey == nil)
    }

    @Test("keeps a clipboard shortcut the user could actually press")
    func customClipboardHotkey() throws {
        let settings = try decode(
            #"{"clipboardHotkey": {"keyCode": 8, "modifiers": ["command", "option"]}}"#
        )

        #expect(settings.clipboardHotkey == HotkeyBinding(keyCode: 8, modifiers: [.command, .option]))
    }

    @Test("lets the user have no clipboard shortcut at all")
    func noClipboardHotkey() throws {
        #expect(try decode(#"{"clipboardHotkey": null}"#).clipboardHotkey == nil)
    }

    /// Absent, `null` and unreadable mean three things. See `Docs/settings-decoding.md`.
    @Test("tells an absent clipboard shortcut apart from one switched off")
    func clipboardHotkeyAbsenceIsNotEmptiness() throws {
        #expect(try decode("{}").clipboardHotkey == .shiftCommandV)
        #expect(try decode(#"{"clipboardHotkey": null}"#).clipboardHotkey == nil)
        // Unreadable: the user never expressed a preference this build can act on.
        #expect(try decode(#"{"clipboardHotkey": "shift-command-v"}"#).clipboardHotkey == .shiftCommandV)
    }

    /// A file written before shortcuts were a set still opens, with the same shortcuts in it.
    @Test("reads the two fields shortcuts replaced")
    func migratesTheOldShape() throws {
        let settings = try decode(
            #"{"hotkey": {"keyCode": 63, "modifiers": []}, "clipboardHotkey": {"keyCode": 9, "modifiers": ["control"]}}"#
        )

        #expect(settings.shortcuts.first(for: .dictate) == .functionHold)
        #expect(settings.shortcuts.first(for: .clipboard) == HotkeyBinding(keyCode: 9, modifiers: [.control]))
    }

    @Test("prefers the shortcuts it was given over the fields they replaced")
    func newShapeWins() throws {
        let settings = try decode(
            #"{"shortcuts": {"dictate": [{"keyCode": 49, "modifiers": ["option"]}]}, "hotkey": {"keyCode": 63, "modifiers": []}}"#
        )

        #expect(settings.shortcuts.first(for: .dictate) == .optionSpace)
    }

    @Test("keeps every way into an action through a round trip")
    func severalWaysSurvive() throws {
        var written = Settings.default
        written.shortcuts.add(.functionHold, to: .dictate)
        let restored = try JSONDecoder().decode(
            Settings.self, from: JSONEncoder().encode(written))

        #expect(restored.shortcuts.bindings(for: .dictate) == [.optionSpace, .functionHold])
    }

    /// These strings are on disk in every installation, so renaming a case resets it for everyone.
    @Test("spells the persisted choices the same way every release")
    func stableNames() throws {
        let encoded = try JSONEncoder().encode(Settings.default)
        let json = try #require(String(data: encoded, encoding: .utf8))

        #expect(json.contains(#""hotkeyActivation":"holdToTalk""#))
        #expect(json.contains(#""floatingButtonAnchor":"bottomRight""#))
        let names = ["bottomLeft", "bottomCentre", "bottomRight", "rightEdge"]
        #expect(DockAnchor.allCases.map(\.rawValue) == names)
    }
}

@Suite("UserDefaultsSettingsStore")
struct UserDefaultsSettingsStoreTests {
    @Test("hands back the defaults before anything has been saved")
    func firstLaunch() {
        let store = UserDefaultsSettingsStore(store: InMemoryKeyValueStore())
        #expect(store.load() == .default)
    }

    @Test("hands back what was saved")
    func roundTrip() {
        var settings = Settings.default
        settings.floatingButtonAnchor = .bottomLeft
        settings.transcriptRetentionDays = 30
        let store = UserDefaultsSettingsStore(store: InMemoryKeyValueStore())

        store.save(settings)

        #expect(store.load() == settings)
    }

    /// The point of the whole type: a choice made yesterday is still made today.
    @Test("keeps choices across a relaunch")
    func survivesRelaunch() {
        let defaults = InMemoryKeyValueStore()
        var settings = Settings.default
        settings.hotkeyActivation = .pressToToggle
        UserDefaultsSettingsStore(store: defaults).save(settings)

        #expect(UserDefaultsSettingsStore(store: defaults).load() == settings)
    }

    @Test("hands back the defaults for bytes that are not JSON at all")
    func garbageBytes() {
        let garbage = Data([0xFF, 0x00, 0x1B, 0x7F, 0xC3, 0x28, 0x00])
        let defaults = InMemoryKeyValueStore([UserDefaultsSettingsStore.defaultKey: garbage])

        #expect(UserDefaultsSettingsStore(store: defaults).load() == .default)
    }

    @Test("hands back the defaults for a blob cut off half way")
    func truncatedBlob() {
        let defaults = InMemoryKeyValueStore(json: #"{"opensAtLogin": fal"#)
        #expect(UserDefaultsSettingsStore(store: defaults).load() == .default)
    }

    /// An unreadable preferences file still opens the app, and the next save repairs it.
    @Test("writes over a corrupt blob rather than refusing to")
    func repairsCorruption() {
        let defaults = InMemoryKeyValueStore(json: "not json")
        let store = UserDefaultsSettingsStore(store: defaults)
        var settings = Settings.default
        settings.opensAtLogin = false

        store.save(settings)

        #expect(store.load() == settings)
    }

    @Test("writes under one key and touches no other")
    func singleKey() {
        let defaults = InMemoryKeyValueStore()
        UserDefaultsSettingsStore(store: defaults).save(.default)

        #expect(defaults.keys == [UserDefaultsSettingsStore.defaultKey])
    }

    @Test("reads and writes the key it was given")
    func customKey() {
        let defaults = InMemoryKeyValueStore()
        let store = UserDefaultsSettingsStore(store: defaults, key: "test.settings")

        store.save(.default)

        #expect(defaults.keys == ["test.settings"])
        #expect(defaults.data(forKey: UserDefaultsSettingsStore.defaultKey) == nil)
        #expect(store.load() == .default)
    }

    @Test("ignores a blob saved under somebody else's key")
    func otherKeysIgnored() {
        var settings = Settings.default
        settings.opensAtLogin = false
        let defaults = InMemoryKeyValueStore()
        UserDefaultsSettingsStore(store: defaults, key: "elsewhere").save(settings)

        #expect(UserDefaultsSettingsStore(store: defaults).load() == .default)
    }

    @Test("replaces the previous save rather than adding to it")
    func overwrites() {
        let defaults = InMemoryKeyValueStore()
        let store = UserDefaultsSettingsStore(store: defaults)
        var settings = Settings.default
        settings.transcriptRetentionDays = 30
        store.save(settings)

        settings.transcriptRetentionDays = 90
        store.save(settings)

        #expect(defaults.keys.count == 1)
        #expect(store.load().transcriptRetentionDays == 90)
    }
}

/// The one suite that touches real preferences, in a domain of its own that it removes afterwards.
@Suite("SystemUserDefaults")
struct SystemUserDefaultsTests {
    @Test("stores, returns and removes bytes in a real defaults domain")
    func roundTrip() {
        withTemporaryDefaultsSuite { suite in
            let defaults = SystemUserDefaults(suiteName: suite.name)

            #expect(defaults.data(forKey: "settings") == nil)

            defaults.set(Data([1, 2, 3]), forKey: "settings")
            #expect(defaults.data(forKey: "settings") == Data([1, 2, 3]))

            defaults.set(nil, forKey: "settings")
            #expect(defaults.data(forKey: "settings") == nil)
        }
    }

    /// Reads only, so the developer's own preferences come out of the test unchanged.
    @Test("falls back to the app's own domain when no suite is named")
    func standardDomain() {
        #expect(SystemUserDefaults().data(forKey: "com.uttrflow.absent.\(UUID().uuidString)") == nil)
    }
}

// MARK: - Tab-to-complete

@Suite("Suggestions inside the settings")
struct SettingsSuggestionsTests {
    @Test("ships tab-to-complete off, and off in the four editors")
    func shipsOff() {
        #expect(!Settings.default.suggestions.isEnabled)
        for editor in SuggestionApplications.offByDefault {
            #expect(
                Settings.default.suggestions.state(of: editor.bundleIdentifier) == .offByDefault)
        }
    }

    @Test("keeps every suggestion choice through an encode and a decode")
    func roundTrip() throws {
        let paused = Date(timeIntervalSince1970: 1_700_000_000)
        var settings = Settings.default
        settings.suggestions = SuggestionPreferences(
            isEnabled: true,
            turnedOff: ["com.apple.notes"],
            turnedOn: ["com.apple.dt.xcode"],
            chosenAcceptKeys: ["com.apple.dt.xcode": .rightArrow],
            isQuiet: true,
            pausedUntil: paused)

        let store = UserDefaultsSettingsStore(store: InMemoryKeyValueStore())
        store.save(settings)
        #expect(store.load().suggestions == settings.suggestions)
    }

    @Test("treats a blob written before suggestions existed as a user who never chose")
    func anOlderBlobDefaults() throws {
        let settings = try decode(#"{"opensAtLogin": false}"#)
        #expect(settings.suggestions == .default)
        #expect(!settings.opensAtLogin)
    }

    @Test("keeps every other choice when the suggestions field cannot be read")
    func anUnreadableFieldDefaults() throws {
        let settings = try decode(#"{"opensAtLogin": false, "suggestions": "on"}"#)
        #expect(settings.suggestions == .default)
        #expect(!settings.opensAtLogin)
    }
}
