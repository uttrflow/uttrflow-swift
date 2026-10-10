// Tests the list of apps no table row names, which fell through to plain text, and the picker beside each.
import Foundation
@testable import UttrflowClipboard
import UttrflowCore
import UttrflowDictionary
import UttrflowHistory
import UttrflowSettings
import Testing

@testable import UttrflowUX

@Suite("Apps that fell through to plain text, in Settings")
struct SettingsPlainTextAppsTests {
    private let quince = SettingsApp(bundleIdentifier: "com.example.Quince", name: "Quince")

    private func record(_ bundle: String?, _ name: String?, _ when: Date) -> DictationRecord {
        DictationRecord(text: "words", when: when, applicationName: name, applicationIdentifier: bundle)
    }

    private func group(
        _ settings: Settings, _ apps: [PlainTextApp], lastApp: SettingsApp? = nil
    ) -> SettingsGroup? {
        SettingsPresenter.pane(
            for: .dictation, settings: settings,
            personalisation: SettingsPersonalisation(
                learnedWords: 0, addedWords: 0, transcripts: 0,
                recentDictationApps: lastApp.map { [$0] } ?? [],
                plainTextApps: apps)
        ).groups.first { $0.id == "plainTextApps" }
    }

    @Test("counts only apps no row names, most dictated first, with the latest name")
    func countsOnlyUnnamedApps() {
        let now = Date(timeIntervalSince1970: 1_000_000)
        let records = [
            record("com.example.Quince", "Quince old", now),
            record("com.example.quince", "Quince", now.addingTimeInterval(60)),
            record("com.example.Damson", "Damson", now),
            record("com.tinyspeck.slackmacgap", "Slack", now),
            record("com.apple.dt.Xcode", "Xcode", now),
            record(nil, nil, now),
            record("", "Nameless", now),
        ]
        let apps = FilePersonalisationStore.plainTextApps(in: records)
        #expect(apps.map(\.app.title) == ["Quince", "Damson"])
        #expect(apps.map(\.dictations) == [2, 1])
    }

    @Test("an app a row names as plain on purpose is not listed as one that fell through")
    func aPlainRowIsADecision() {
        let records = [record("com.raycast.macos", "Raycast", Date())]
        #expect(FilePersonalisationStore.plainTextApps(in: records).isEmpty)
    }

    @Test("with no app fallen through, there is no list")
    func nothingToList() {
        #expect(group(.default, []) == nil)
    }

    @Test("each app is offered every kind of place, written as the same override")
    func pickerWritesTheOverride() throws {
        let row = try #require(group(.default, [PlainTextApp(app: quince, dictations: 3)])?.rows.first)
        #expect(row.label == "Quince")
        #expect(row.icon == .application(bundleIdentifier: quince.bundleIdentifier, name: "Quince"))
        guard case .menu(let options, let selected) = row.control else {
            Issue.record("the row is not a pop-up")
            return
        }
        #expect(selected == SettingsDestinations.automaticID)
        #expect(options.count == UttrflowCore.Destination.allCases.count + 1)
        let document = try #require(options.first { $0.id == UttrflowCore.Destination.document.rawValue })
        let written = try SettingsEditor.apply(document.change, to: .default)
        let expected = DestinationOverrides.none.setting(
            .document, for: quince.bundleIdentifier, named: "Quince")
        #expect(written.destinations == expected)
    }

    @Test("VoiceOver hears the app, how often it fell through, and what to do")
    func accessibilityLabel() throws {
        let row = try #require(group(.default, [PlainTextApp(app: quince, dictations: 3)])?.rows.first)
        #expect(
            row.accessibilityLabel
                == "Quince. No rule names this app, so 3 dictations went in as plain text. "
                + "Choose what kind of place it is.")
    }

    @Test("an app already given a kind leaves the list, and at most ten are shown")
    func overriddenAppsLeaveAndTenAreShown() throws {
        var settings = Settings.default
        settings.destinations = DestinationOverrides.none.setting(
            .codeEditor, for: quince.bundleIdentifier, named: "Quince")
        let others = (1...11).map {
            PlainTextApp(
                app: SettingsApp(bundleIdentifier: "com.example.App\($0)", name: "App \($0)"),
                dictations: 20 - $0)
        }
        let rows = try #require(
            group(settings, [PlainTextApp(app: quince, dictations: 50)] + others)?.rows)
        #expect(rows.map(\.label) == (1...10).map { "App \($0)" })
    }

    @Test("the list resets with history, because it is read from history")
    func resetsWithHistory() async throws {
        let directory = URL.temporaryDirectory.appending(
            path: "uttrflow-plain-\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let now = Date()
        let history = DictationHistoryStore(file: directory.appending(path: "history.json"))
        try await history.append(
            record(quince.bundleIdentifier, "Quince", now), keeping: Retention(days: 7, now: now))
        let store = FilePersonalisationStore(
            dictionary: PersonalDictionaryStore(file: directory.appending(path: "dictionary.json")),
            history: history,
            clipboard: ClipboardStore(file: directory.appending(path: "clipboard.json")),
            ledger: NetworkActivityLedger(file: nil))

        let before = await store.personalisation(keeping: Retention(days: 7, now: now))
        #expect(before.plainTextApps == [PlainTextApp(app: quince, dictations: 1)])

        try await store.carryOut(.everything)
        let after = await store.personalisation(keeping: Retention(days: 7, now: now))
        #expect(after.plainTextApps.isEmpty)
    }

    @Test("the list never reaches the diagnostics export")
    func excludedFromDiagnostics() {
        // By declared type, since an empty array of anything casts to an empty array of these.
        let types = Mirror(reflecting: DiagnosticsSnapshot()).children.map {
            String(describing: type(of: $0.value))
        }
        #expect(!types.isEmpty)
        #expect(!types.contains { $0.contains("PlainTextApp") || $0.contains("SettingsPersonalisation") })
    }
}
