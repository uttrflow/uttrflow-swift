// Settings must reach what AI suggestions learned, through the store the app actually builds.

import Foundation
import Testing
import UttrflowClipboard
import UttrflowDictionary
import UttrflowHistory
import UttrflowPredict
import UttrflowPredictCapture
import UttrflowPredictStore
import UttrflowUX

@testable import Uttrflow

private let terminal = Surface(bundleIdentifier: "com.example.terminal", role: "AXTextArea")
private let notes = Surface(bundleIdentifier: "com.example.notes", role: "AXTextArea")
private let moment = Date(timeIntervalSince1970: 1_800_000_000)

/// A container of its own per test, removed when the test ends.
private struct Container: ~Copyable {
    let url = FileManager.default.temporaryDirectory
        .appending(path: "uttrflow-forgetting-\(UUID().uuidString)", directoryHint: .isDirectory)

    var corpusPath: String { PredictStore.defaultFile(in: url).path(percentEncoded: false) }

    var consent: CapturePreferencesFile {
        CapturePreferencesFile(
            path: CapturePreferencesFile.defaultFile(in: url).path(percentEncoded: false))
    }

    /// The personalisation store the settings window is given, over this container's files.
    func personalisation() -> FilePersonalisationStore {
        AppDelegate.personalisation(
            in: url,
            dictionary: PersonalDictionaryStore(file: PersonalDictionaryStore.defaultFile(in: url)),
            history: DictationHistoryStore(file: DictationHistoryStore.defaultFile(in: url)),
            clipboard: ClipboardStore(file: ClipboardStore.defaultFile(in: url)))
    }

    /// A corpus holding lines from two applications, and the consent that let them be learned.
    func learned() async throws -> PredictStore {
        let store = try PredictStore(path: corpusPath)
        try await store.record("git push", in: terminal, at: moment)
        try await store.record("git pull", in: terminal, at: moment)
        try await store.record("a note", in: notes, at: moment)
        var preferences = CapturePreferences()
        preferences.record(.allowed, for: terminal.bundleIdentifier)
        preferences.record(.allowed, for: notes.bundleIdentifier)
        try consent.save(preferences)
        return store
    }

    deinit { try? FileManager.default.removeItem(at: url) }
}

@Suite("Forgetting what AI suggestions learned")
struct SuggestionForgettingTests {
    private let promise = Retention(days: 30, now: moment)

    @Test("Settings counts what each application taught, so its forget row can appear.")
    func countsWhatEachApplicationTaught() async throws {
        let container = Container()
        _ = try await container.learned()
        let counted = await container.personalisation().personalisation(keeping: promise)
        #expect(counted.suggestions(from: terminal.bundleIdentifier) == 2)
        #expect(counted.suggestions(from: notes.bundleIdentifier) == 1)
    }

    @Test("Forgetting one application removes its lines and leaves every other application's.")
    func forgetsOneApplication() async throws {
        let container = Container()
        let store = try await container.learned()
        try await container.personalisation().carryOut(
            .suggestions(inApplication: terminal.bundleIdentifier))
        #expect(try await store.entryCountsByApplication() == [notes.bundleIdentifier: 1])
    }

    @Test("Reset personalisation removes every line and every application the loop has met.")
    func resetRemovesEverything() async throws {
        let container = Container()
        let store = try await container.learned()
        try await container.personalisation().carryOut(.everything)
        #expect(try await store.entryCount() == 0)
        #expect(container.consent.load() == CapturePreferences())
        let counted = await container.personalisation().personalisation(keeping: promise)
        #expect(counted.applicationsWithSuggestions.isEmpty)
    }

    @Test("With nothing ever learned, counting and forgetting create no corpus file.")
    func nothingLearnedCreatesNothing() async throws {
        let container = Container()
        let personalisation = container.personalisation()
        #expect(await PredictCorpus(container: container.url).learnedSuggestions().isEmpty)
        try await personalisation.carryOut(.suggestions(inApplication: terminal.bundleIdentifier))
        try await personalisation.carryOut(.everything)
        #expect(!FileManager.default.fileExists(atPath: container.corpusPath))
    }
}
