import Foundation
import Synchronization
import Testing

@testable import UttrflowCore
import UttrflowPredict
@testable import UttrflowSettings

/// A key-value store in memory: the settings store's real behaviour is what is under
/// test, and a defaults domain would outlive the test that wrote to it.
private final class InMemoryKeyValueStore: KeyValueStore {
    private let contents: Mutex<[String: Data]>

    init(_ initial: [String: Data] = [:]) {
        contents = Mutex(initial)
    }

    convenience init(json: String, forKey key: String = UserDefaultsSettingsStore.defaultKey) {
        self.init([key: Data(json.utf8)])
    }

    var keys: Set<String> {
        contents.withLock { Set($0.keys) }
    }

    func data(forKey key: String) -> Data? {
        contents.withLock { $0[key] }
    }

    func set(_ data: Data?, forKey key: String) {
        contents.withLock { $0[key] = data }
    }
}

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

    /// The upgrade case: a user who has been running the app for a year opens a build
    /// that added settings, and must find the ones they chose still chosen.
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

    /// Field-by-field recovery earns its keep here: one unreadable value must not cost
    /// the user the ten choices either side of it.
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

    /// A language subtag that cannot be parsed makes the whole profile undecodable;
    /// the rest of the settings must not go down with it.
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

    /// Honouring a zero would empty the user's history the moment the app launched,
    /// which is the one outcome a preferences file must never be able to cause.
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

    /// The downgrade case, and the reason a persisted key may be dropped at all: no
    /// audio was ever written to disk, so the period that claimed to govern it governed
    /// nothing. A user who set one is still a user with every other choice they made,
    /// and keyed decoding simply never asks for the key this build has no case for.
    @Test("loads a blob written before the recording period was dropped")
    func blobFromBeforeRecordingRetentionWentAway() throws {
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

    /// A dropped key is a door left open, and a hostile value must not come back in
    /// through it: the period it once set is gone, not defaulted to something else.
    @Test("ignores a hostile recording period an older blob still carries")
    func hostileRecordingRetentionIsIgnored() throws {
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

    /// Each of these is a perfectly well-formed ``HotkeyBinding`` and a shortcut macOS
    /// will never deliver. Honouring one leaves the user unable to start a dictation and,
    /// with no screen for choosing another, unable to put it right without deleting the
    /// preferences file from a terminal.
    @Test(
        "refuses a shortcut that decodes cleanly and could never fire",
        arguments: [
            // No modifier: would fire in the middle of an ordinary word.
            #"{"keyCode": 49, "modifiers": []}"#,
            // Beyond the 7-bit range a keyboard can send.
            #"{"keyCode": 999, "modifiers": ["command"]}"#,
            // Command held down on its own, which is not a shortcut.
            #"{"keyCode": 200, "modifiers": ["command"]}"#,
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

    /// Separate from the transcript period on purpose: someone who keeps dictation
    /// transcripts for a day has said something about what Uttrflow writes down, not
    /// about their own clipboard. One number for both would empty the panel on their
    /// behalf, having never asked.
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

    /// The dictation shortcut falls back to Option+Space when it cannot fire, because
    /// there has to be *some* way to dictate. The clipboard shortcut has no such
    /// obligation, so an unusable one is dropped rather than moved to a key the user
    /// never asked for and would meet by surprise in another app.
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

    /// Carbon registers both and then fires both, so one keypress would start a
    /// dictation and open the panel together.
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

    /// The three ways the field can arrive mean three different things, and two of them
    /// look identical to `decodeIfPresent`. Absent is a user who never chose; `null` is
    /// a user who chose to have none; unreadable is neither, and is treated as never
    /// chosen. Collapsing the first two is the bug this pins: a shortcut switched off
    /// would come back by itself on the next launch.
    @Test("tells an absent clipboard shortcut apart from one switched off")
    func clipboardHotkeyAbsenceIsNotEmptiness() throws {
        #expect(try decode("{}").clipboardHotkey == .shiftCommandV)
        #expect(try decode(#"{"clipboardHotkey": null}"#).clipboardHotkey == nil)
        // Unreadable: the user never expressed a preference this build can act on.
        #expect(try decode(#"{"clipboardHotkey": "shift-command-v"}"#).clipboardHotkey == .shiftCommandV)
    }

    /// These strings are on disk in every installation; renaming a case would silently
    /// reset that setting for everyone who had changed it.
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

    /// A user whose preferences file is unreadable still gets an app that opens, and a
    /// save from that session repairs it.
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

/// The one place that touches real preferences, in a domain of its own that it removes
/// afterwards. Thin as the adapter is, "bytes go in and come back" is the whole of what
/// it claims, and nothing else in this file would notice if it stopped being true.
@Suite("SystemUserDefaults")
struct SystemUserDefaultsTests {
    @Test("stores, returns and removes bytes in a real defaults domain")
    func roundTrip() {
        let suite = "com.uttrflow.tests.\(UUID().uuidString)"
        let defaults = SystemUserDefaults(suiteName: suite)
        defer { UserDefaults.standard.removePersistentDomain(forName: suite) }

        #expect(defaults.data(forKey: "settings") == nil)

        defaults.set(Data([1, 2, 3]), forKey: "settings")
        #expect(defaults.data(forKey: "settings") == Data([1, 2, 3]))

        defaults.set(nil, forKey: "settings")
        #expect(defaults.data(forKey: "settings") == nil)
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
