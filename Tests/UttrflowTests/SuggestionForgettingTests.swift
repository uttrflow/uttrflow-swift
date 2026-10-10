// Settings must reach what AI suggestions learned, through the store the app actually builds.

import CryptoKit
import Foundation
import CryptoKit
import Testing
import UttrflowCore
import UttrflowClipboard
import UttrflowDictionary
import UttrflowHistory
import UttrflowPredict
import UttrflowPredictCapture
import UttrflowPredictStore
import UttrflowCore
import UttrflowUX

@testable import Uttrflow

private let terminal = Surface(bundleIdentifier: "com.example.terminal", role: "AXTextArea")
private let notes = Surface(bundleIdentifier: "com.example.notes", role: "AXTextArea")
private let moment = Date(timeIntervalSince1970: 1_800_000_000)

private struct SuggestionStoreKeys: StoreKeyProviding {
    let value = SymmetricKey(size: .bits256)
    func key(createIfMissing _: Bool) throws -> SymmetricKey { value }
}

/// A scorer with retained generated confidences, so Settings resets can be checked without loading MLX.
private actor ResettableScoring: CandidateScoring {
    private var confidences: [String: Double] = [:]
    private(set) var forgetCount = 0

    var isReady: Bool { true }
    func logLikelihood(of candidate: String, following context: String) async -> Double? { -1 }
    func confidence(ofGenerated line: String) async -> Double? { confidences[line] }
    func remember(_ line: String, confidence: Double) { confidences[line] = confidence }
    func forgetEverything() async {
        forgetCount += 1
        confidences.removeAll()
    }
}

/// A container of its own per test, removed when the test ends.
private struct FixedKey: StoreKeyProviding {
    let value = SymmetricKey(size: .bits256)
    func key(createIfMissing: Bool) throws -> SymmetricKey { value }
}

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

    @Test("Forgetting everything removes every set-aside copy of the corpus and its sidecars.")
    func forgettingRemovesSetAsideCopies() async throws {
        let container = Container()
        _ = try await container.learned()
        for suffix in ["", "-wal", "-shm"] {
            try Data("old lines".utf8).write(
                to: URL(filePath: container.corpusPath + suffix + ".unreadable-1"))
        }

        try await PredictCorpus(container: container.url).forgetEverySuggestion()

        let names = try FileManager.default.contentsOfDirectory(
            atPath: container.url.path(percentEncoded: false))
        #expect(!names.contains { $0.contains(".unreadable-") })
    }

    @Test("A corpus that cannot be authenticated is deleted unread, and consent goes only after it.")
    func unopenableCorpusIsStillForgotten() async throws {
        let container = Container()
        try FileManager.default.createDirectory(
            at: URL(filePath: container.corpusPath).deletingLastPathComponent(),
            withIntermediateDirectories: true)
        let otherInstallation = EncryptedStore(keys: FixedKey())
        let sealed = try otherInstallation.seal(Data("lines".utf8), for: "predict.v1.sqlite")
        try sealed.write(to: URL(filePath: container.corpusPath))
        var preferences = CapturePreferences()
        preferences.record(.allowed, for: terminal.bundleIdentifier)
        try container.consent.save(preferences)
        let corpus = PredictCorpus(container: container.url, encryptedStore: EncryptedStore(keys: FixedKey()))

        try await corpus.forgetEverySuggestion()

        #expect(!FileManager.default.fileExists(atPath: container.corpusPath))
        #expect(container.consent.load() == CapturePreferences())
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

    @Test("Settings counts use the open encrypted corpus", .bug(id: 5267))
    @MainActor
    func runningCorpusProvidesLearnedSuggestionCounts() async throws {
        let container = Container()
        try FileManager.default.createDirectory(at: container.url, withIntermediateDirectories: true)
        let encryptedStore = EncryptedStore(keys: SuggestionStoreKeys())
        let coordinator = try await SuggestionCoordinator(
            container: container.url, preferences: SuggestionPreferences(isEnabled: true),
            encryptedStore: encryptedStore)
        try await coordinator.store.record("remembered line", in: notes, at: moment)
        let corpus = PredictCorpus(
            container: container.url, running: { coordinator }, encryptedStore: encryptedStore)

        #expect(await corpus.learnedSuggestions() == [notes.bundleIdentifier: 1])
    }

    @Test("Forgetting through the running loop leaves no succession naming the forgotten line.")
    @MainActor
    func runningLoopDoesNotWriteAForgottenLineBack() async throws {
        let container = Container()
        try FileManager.default.createDirectory(at: container.url, withIntermediateDirectories: true)
        let coordinator = try await SuggestionCoordinator(
            container: container.url, preferences: SuggestionPreferences(isEnabled: true))
        let reading = FieldReading(bundleIdentifier: terminal.bundleIdentifier, role: "AXTextArea")
        let surface = try #require(reading.surface)
        try await coordinator.capture.record(.allowed, for: terminal.bundleIdentifier)
        _ = try await coordinator.capture.handle(.keystroke("forgotten line", at: moment), in: reading)
        _ = try await coordinator.capture.handle(.returnPressed(at: moment), in: reading)

        let corpus = PredictCorpus(container: container.url, running: { coordinator })
        try await corpus.forgetSuggestions(from: terminal.bundleIdentifier)
        _ = try await coordinator.capture.handle(.keystroke("next line", at: moment), in: reading)
        _ = try await coordinator.capture.handle(.returnPressed(at: moment), in: reading)

        let store = try PredictStore(path: container.corpusPath)
        #expect(try await store.successors(for: surface, after: "forgotten line").isEmpty)
        try await corpus.forgetEverySuggestion()
        #expect(await coordinator.capture.decisions() == CapturePreferences())
    }

    @Test("Forget drains a queued acceptance before clearing the corpus")
    @MainActor
    func forgetDrainsPendingAcceptance() async throws {
        let container = Container()
        try FileManager.default.createDirectory(at: container.url, withIntermediateDirectories: true)
        let coordinator = try await SuggestionCoordinator(
            container: container.url, preferences: SuggestionPreferences(isEnabled: true))
        let reading = FieldReading(bundleIdentifier: terminal.bundleIdentifier, role: "AXTextArea")
        try await coordinator.capture.record(.allowed, for: terminal.bundleIdentifier)

        let queued = coordinator.acceptances.enqueue { [capture = coordinator.capture] in
            _ = try? await capture.accepted("forgotten acceptance", in: reading, at: moment)
        }
        #expect(queued)
        try await coordinator.forgetEverySuggestion()
        await coordinator.finishWrites()

        let store = try PredictStore(path: container.corpusPath)
        #expect(try await store.entryCount() == 0)
    }

    @Test("Both Settings forget actions clear the running model scorer without a release")
    @MainActor
    func forgetActionsClearScorerMemory() async throws {
        let container = Container()
        try FileManager.default.createDirectory(at: container.url, withIntermediateDirectories: true)
        let scorer = ResettableScoring()
        let coordinator = try await SuggestionCoordinator(
            container: container.url, preferences: SuggestionPreferences(isEnabled: true), scoring: scorer)

        await scorer.remember("forgotten app line", confidence: -0.25)
        #expect(await scorer.confidence(ofGenerated: "forgotten app line") == -0.25)
        try await coordinator.forgetSuggestions(from: terminal.bundleIdentifier)
        #expect(await scorer.confidence(ofGenerated: "forgotten app line") == nil)

        await scorer.remember("forgotten history line", confidence: -0.5)
        #expect(await scorer.confidence(ofGenerated: "forgotten history line") == -0.5)
        try await coordinator.forgetEverySuggestion()
        #expect(await scorer.confidence(ofGenerated: "forgotten history line") == nil)
        #expect(await scorer.forgetCount == 2)
    }
}
