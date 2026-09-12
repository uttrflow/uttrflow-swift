// A settings row that asks for something to happen must reach the app, not be saved and lost.

import Foundation
import Testing
import UttrflowCore
import UttrflowHistory
import UttrflowPredict
import UttrflowSettings
import UttrflowUX

@testable import Uttrflow

/// Settings held in memory, so the routing is tested without a file behind it.
private final class RecordingStore: SettingsStore, @unchecked Sendable {
    private(set) var saves = 0
    private var settings = Settings.default

    func load() -> Settings { settings }

    func save(_ settings: Settings) {
        self.settings = settings
        saves += 1
    }
}

/// Personalisation that has nothing to count and nothing to remove.
private struct EmptyPersonalisation: SettingsPersonalisationStore {
    func personalisation(keeping retention: Retention) async -> SettingsPersonalisation {
        SettingsPersonalisation(learnedWords: 0, addedWords: 0, transcripts: 0)
    }

    func carryOut(_ reset: SettingsReset) async throws(SettingsResetFailure) {}
}

@MainActor
@Suite("A settings row that asks for something to happen")
struct SettingsRequestWiringTests {
    /// Builds a model over the recording store, reporting what each callback was handed.
    private func model(
        _ store: RecordingStore,
        onChange: @escaping (Settings) -> Void = { _ in },
        onRequest: @escaping (SettingsChange) -> Void = { _ in }
    ) -> SettingsViewModel {
        SettingsViewModel(
            store: store, personalisation: EmptyPersonalisation(), capabilities: .everything,
            onChange: onChange, onRequest: onRequest)
    }

    @Test("Check Now reaches the app, which is the only thing that can ask the feed")
    func checkNowIsHandedOn() {
        var asked: [SettingsChange] = []
        let store = RecordingStore()
        let model = model(store, onRequest: { asked.append($0) })

        model.apply(.checkForUpdatesNow)

        #expect(asked == [.checkForUpdatesNow])
    }

    @Test("and is not saved, since it changes no setting")
    func checkNowSavesNothing() {
        var changed = 0
        let store = RecordingStore()
        let model = model(store, onChange: { _ in changed += 1 })

        model.apply(.checkForUpdatesNow)

        #expect(store.saves == 0)
        #expect(changed == 0)
    }

    @Test("an ordinary change still saves and still reports, and asks for nothing")
    func anOrdinaryChangeIsUnaffected() {
        var changed: [Settings] = []
        var asked: [SettingsChange] = []
        let store = RecordingStore()
        let model = model(store, onChange: { changed.append($0) }, onRequest: { asked.append($0) })

        model.apply(.toggle(.playsSoundWhenRecordingStarts, isOn: true))

        #expect(store.saves == 1)
        #expect(changed.count == 1)
        #expect(changed.first?.playsSoundWhenRecordingStarts == true)
        #expect(asked.isEmpty)
    }
}

// MARK: - Every change reaches something

/// Names a change; exhaustive on purpose, so a new case cannot be added without being named.
private func name(of change: SettingsChange) -> String {
    switch change {
    case .toggle: "toggle"
    case .activation: "activation"
    case .anchor: "anchor"
    case .shortcut: "shortcut"
    case .tidying: "tidying"
    case .transcription: "transcription"
    case .spokenLanguage: "spokenLanguage"
    case .retention: "retention"
    case .appearance: "appearance"
    case .cleaningStep: "cleaningStep"
    case .appDestination: "appDestination"
    case .forgetAppDestination: "forgetAppDestination"
    case .suggestionsHere: "suggestionsHere"
    case .suggestionAcceptKey: "suggestionAcceptKey"
    case .pauseSuggestions: "pauseSuggestions"
    case .checkForUpdatesNow: "checkForUpdatesNow"
    }
}

/// How many cases ``SettingsChange`` has, bumped deliberately when one is added.
private let settingsChangeCaseCount = 16

/// Applies a change, or answers the settings unchanged when the editor refused it.
private func applying(_ change: SettingsChange, to settings: Settings) -> Settings {
    (try? SettingsEditor.apply(change, to: settings, given: .everything)) ?? settings
}

/// What a change did. Only `inert` is a bug: a refusal is a sentence the user is shown.
private enum Outcome: Equatable {
    case changed
    case asks
    case refused
    case inert
}

/// What one sample did, which is the whole of what this suite asserts about.
private func outcome(of sample: Sample) -> Outcome {
    guard !sample.change.isRequestToAct else { return .asks }
    do {
        let after = try SettingsEditor.apply(sample.change, to: sample.from, given: .everything)
        return after == sample.from ? .inert : .changed
    } catch {
        return .refused
    }
}

/// One change, and settings it is guaranteed to mean something from.
private struct Sample {
    let change: SettingsChange
    let from: Settings

    init(_ change: SettingsChange, from: Settings = .default) {
        self.change = change
        self.from = from
    }
}

/// Suggestions on, since every suggestion control is refused while the master switch is off.
private var suggesting: Settings {
    var settings = Settings.default
    settings.suggestions.isEnabled = true
    return settings
}

private let knownApp = "com.example.thing"

/// One sample per case, each starting from settings the change actually alters.
private let samples: [Sample] = [
    Sample(.toggle(.showsFloatingButton, isOn: !Settings.default.showsFloatingButton)),
    Sample(.activation(.pressToToggle)),
    Sample(.anchor(.bottomLeft)),
    Sample(.shortcut(.dictate, .functionHold)),
    Sample(.tidying(.light), from: applying(.tidying(.standard), to: .default)),
    Sample(
        .transcription(.faster), from: applying(.transcription(.mostAccurate), to: .default)),
    Sample(.spokenLanguage(.hindi, isSpoken: true)),
    Sample(.retention(days: 3)),
    Sample(.appearance(.light)),
    Sample(.cleaningStep(.fillers, isOn: false)),
    Sample(.appDestination(bundleIdentifier: knownApp, name: "Thing", destination: .document)),
    Sample(
        .forgetAppDestination(bundleIdentifier: knownApp),
        from: applying(
            .appDestination(bundleIdentifier: knownApp, name: "Thing", destination: .document),
            to: .default)),
    Sample(.suggestionsHere(application: knownApp, isOn: false), from: suggesting),
    Sample(.suggestionAcceptKey(application: knownApp, key: .rightArrow), from: suggesting),
    Sample(.pauseSuggestions(isOn: true), from: suggesting),
    Sample(.checkForUpdatesNow),
]

/// Settings that start from whatever a sample needs, so a change is applied to ground it alters.
private final class SeededStore: SettingsStore, @unchecked Sendable {
    private var settings: Settings

    init(_ settings: Settings) { self.settings = settings }

    func load() -> Settings { settings }

    func save(_ settings: Settings) { self.settings = settings }
}

@MainActor
@Suite("Every settings control reaches something")
struct SettingsChangeWiringTests {
    @Test("every case has a sample, so a new one cannot be added without saying what it does")
    func everyCaseHasASample() {
        #expect(Set(samples.map { name(of: $0.change) }).count == settingsChangeCaseCount)
    }

    /// The shape of #123: a control that travelled, was saved, altered nothing, and was lost.
    @Test("no control is inert: each one changes a setting, asks the app to act, or is refused")
    func noControlIsInert() {
        for sample in samples {
            #expect(
                outcome(of: sample) != .inert,
                "\(name(of: sample.change)) changed nothing, asked nothing and refused nothing")
        }
    }

    /// The half a presenter test cannot see: that the window hands the change on at all.
    @Test("and the Settings window tells the app about every one of them")
    func theWindowHandsEveryChangeOn() {
        for sample in samples {
            var saved: Settings?
            var asked: SettingsChange?
            let store = SeededStore(sample.from)
            let model = SettingsViewModel(
                store: store, personalisation: EmptyPersonalisation(), capabilities: .everything,
                onChange: { saved = $0 }, onRequest: { asked = $0 })

            model.apply(sample.change)

            if sample.change.isRequestToAct {
                #expect(
                    asked == sample.change,
                    "\(name(of: sample.change)) is a request and never reached the app")
                #expect(saved == nil, "\(name(of: sample.change)) was saved as well as asked")
            } else {
                #expect(
                    saved != nil && saved != sample.from,
                    "\(name(of: sample.change)) reached the app unchanged, or not at all")
                #expect(asked == nil, "\(name(of: sample.change)) was asked as well as saved")
            }
        }
    }
}
