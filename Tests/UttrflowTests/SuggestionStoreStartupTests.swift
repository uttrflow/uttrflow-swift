import AppKit
import CryptoKit
import Foundation
import Testing
import UttrflowCore
import UttrflowPredictCapture
import UttrflowPredict
import UttrflowSettings

@testable import Uttrflow
@testable import UttrflowPredictStore

private func isCurrentThreadMain() -> Bool { Thread.isMainThread }

private final class SuggestionStartupThreadObservation: @unchecked Sendable {
    private let lock = NSLock()
    private var mainThreadSamples: [Bool] = []

    func record() {
        lock.lock()
        defer { lock.unlock() }
        mainThreadSamples.append(Thread.isMainThread)
    }

    var samples: [Bool] {
        lock.lock()
        defer { lock.unlock() }
        return mainThreadSamples
    }
}

@MainActor
private final class SuggestionStartupUIHeartbeat {
    private(set) var pulses = 0
    var startupFinished = false

    func runUntilStartupFinishes() async {
        pulses += 1
        while !startupFinished && !Task.isCancelled {
            try? await Task.sleep(for: .milliseconds(10))
            guard !startupFinished && !Task.isCancelled else { break }
            pulses += 1
        }
    }
}

private struct SuggestionStartupKeys: StoreKeyProviding {
    let observation: SuggestionStartupThreadObservation
    let value = SymmetricKey(data: Data(repeating: 0x5A, count: 32))

    func key(createIfMissing _: Bool) throws -> SymmetricKey {
        observation.record()
        return value
    }
}

@MainActor
@Suite("Suggestion corpus startup")
struct SuggestionStoreStartupTests {
    @Test("corpus and learning-preference file work runs off the main thread")
    func startupFileWorkRunsOffMainThread() async throws {
        #expect(isCurrentThreadMain())
        let container = FileManager.default.temporaryDirectory
            .appending(path: "suggestion-startup-\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: container, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: container) }
        let storePath = PredictStore.defaultFile(in: container).path(percentEncoded: false)
        let preferencesPath =
            CapturePreferencesFile.defaultFile(in: container).path(percentEncoded: false)

        let openedOnMainThread = try await SuggestionCoordinator.startupFileWorkOffMain {
            let _ = try PredictStore(path: storePath)
            let _ = CapturePreferencesFile(path: preferencesPath).load()
            return Thread.isMainThread
        }

        #expect(!openedOnMainThread)
    }

    @Test("a 20,000-entry encrypted v1 corpus migrates off-main within its startup budget")
    func largeLegacyCorpusMigratesOffMainThreadWithinBudget() async throws {
        let root = FileManager.default.temporaryDirectory
            .appending(path: "suggestion-startup-benchmark-\(UUID().uuidString)", directoryHint: .isDirectory)
        let seedDirectory = root.appending(path: "seed", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: seedDirectory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }

        let seedStore = EncryptedStore(keys: SuggestionStartupKeys(observation: .init()))
        let seedPath = PredictStore.defaultFile(in: seedDirectory).path(percentEncoded: false)
        try Self.makeLegacyCorpus(path: seedPath, encryptedStore: seedStore)
        #expect(FileManager.default.fileExists(atPath: seedPath))
        let seedImage = try Data(contentsOf: URL(filePath: seedPath))
        #expect(EncryptedStore.isSealed(seedImage))

        let clock = ContinuousClock()
        var elapsedSamples: [Duration] = []
        for sample in 0..<3 {
            let directory = root.appending(path: "sample-\(sample)", directoryHint: .isDirectory)
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            let path = PredictStore.defaultFile(in: directory).path(percentEncoded: false)
            try FileManager.default.createDirectory(
                at: PredictStore.defaultFile(in: directory).deletingLastPathComponent(),
                withIntermediateDirectories: true)
            try FileManager.default.copyItem(
                at: URL(filePath: seedPath), to: URL(filePath: path))

            let observation = SuggestionStartupThreadObservation()
            let encryptedStore = EncryptedStore(keys: SuggestionStartupKeys(observation: observation))
            let heartbeat = SuggestionStartupUIHeartbeat()
            let heartbeatTask = Task { @MainActor in
                await heartbeat.runUntilStartupFinishes()
            }
            while heartbeat.pulses == 0 { await Task.yield() }

            let start = clock.now
            let startupTask = Task { @MainActor in
                defer { heartbeat.startupFinished = true }
                return try await SuggestionCoordinator(
                    container: directory,
                    preferences: SuggestionPreferences(),
                    encryptedStore: encryptedStore)
            }
            let coordinator = try await startupTask.value
            let elapsed = start.duration(to: clock.now)
            heartbeatTask.cancel()
            elapsedSamples.append(elapsed)
            let mainThreadSamples = observation.samples
            #expect(!mainThreadSamples.isEmpty)
            #expect(!mainThreadSamples.contains(true))
            #expect(
                heartbeat.pulses > 1 || elapsed <= .milliseconds(16),
                "The main-actor UI heartbeat did not run during a \(elapsed) startup")
            #expect(
                elapsed < .seconds(2),
                "A 20,000-entry encrypted v1 corpus took \(elapsed) to migrate off-main")
            coordinator.stop()
        }
        print("Suggestion startup, 20,000 encrypted v1 entries, samples: \(elapsedSamples)")
    }

    @Test("launch returns after its initial menu update within budget with a large legacy corpus")
    func launchReturnsAfterInitialMenuUpdateWithinBudget() async throws {
        let root = FileManager.default.temporaryDirectory
            .appending(path: "suggestion-launch-benchmark-\(UUID().uuidString)", directoryHint: .isDirectory)
        let seedDirectory = root.appending(path: "seed", directoryHint: .isDirectory)
        let launchDirectory = root.appending(path: "launch", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: seedDirectory, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: launchDirectory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }

        let seedStore = EncryptedStore(keys: SuggestionStartupKeys(observation: .init()))
        let seedPath = PredictStore.defaultFile(in: seedDirectory).path(percentEncoded: false)
        try Self.makeLegacyCorpus(path: seedPath, encryptedStore: seedStore)
        let launchPath = PredictStore.defaultFile(in: launchDirectory)
        try FileManager.default.createDirectory(
            at: launchPath.deletingLastPathComponent(), withIntermediateDirectories: true)
        try FileManager.default.copyItem(at: URL(filePath: seedPath), to: launchPath)

        let suite = "uttrflow-suggestion-startup-\(UUID().uuidString)"
        let settingsStore = UserDefaultsSettingsStore(store: SystemUserDefaults(suiteName: suite))
        settingsStore.save(Settings(suggestions: SuggestionPreferences(isEnabled: true)))
        defer { UserDefaults(suiteName: suite)?.removePersistentDomain(forName: suite) }
        let session = HeldSession(signedIn: true)
        let observation = SuggestionStartupThreadObservation()
        let encryptedStore = EncryptedStore(keys: SuggestionStartupKeys(observation: observation))
        let app = AppDelegate(
            container: launchDirectory, settingsStore: settingsStore,
            account: session.layer, prepareModel: { _ in }, encryptedStore: encryptedStore)
        app.drawsWindows = false

        let clock = ContinuousClock()
        let start = clock.now
        app.applicationDidFinishLaunching(Notification(name: NSApplication.didFinishLaunchingNotification))
        let elapsed = start.duration(to: clock.now)
        let initialPresentation = app.menuBarPresentation

        print(
            "Suggestion launch handler return after initial menu update, 20,000 encrypted v1 entries: \(elapsed)"
        )
        #expect(
            initialPresentation.commands.contains { $0.title.hasPrefix("AI Suggestions") },
            "The initial menu-bar model did not include the enabled suggestions feature")
        #expect(
            elapsed < .seconds(2),
            "Launch handler returned after \(elapsed) with a 20,000-entry encrypted v1 corpus")

        await app.suggestionStartup?.value
        await app.sweeping?.value
        await app.dictionaryMigrationWork?.value
        await app.modelPreparation?.value
        let keyAccessThreads = observation.samples
        #expect(!keyAccessThreads.isEmpty)
        #expect(!keyAccessThreads.contains(true), "Launch opened an encrypted store on the main thread")
        #expect(app.surfaces.completesWhatIsTyped, "The launch fixture must enable signed-in suggestions")
        #expect(settingsStore.load().suggestions.isEnabled)
        #expect(
            app.menuBarPresentation.commands.contains { $0.title.hasPrefix("AI Suggestions") },
            "The menu-bar response did not retain the enabled suggestions feature after startup")
        app.applicationWillTerminate(Notification(name: NSApplication.willTerminateNotification))
    }

    private static func makeLegacyCorpus(path: String, encryptedStore: EncryptedStore) throws {
        try FileManager.default.createDirectory(
            at: URL(filePath: path).deletingLastPathComponent(), withIntermediateDirectories: true)
        let database = try Database(path: path, encryptedStore: encryptedStore)
        try database.execute("CREATE TABLE schema_version (version INTEGER NOT NULL)")
        try database.execute(
            """
            CREATE TABLE surface (
              id INTEGER PRIMARY KEY, bundle_id TEXT NOT NULL, role TEXT NOT NULL,
              locator TEXT NOT NULL DEFAULT '', scope TEXT NOT NULL DEFAULT '',
              UNIQUE (bundle_id, role, locator, scope))
            """)
        try database.execute(
            """
            CREATE TABLE entry (
              id INTEGER PRIMARY KEY, surface_id INTEGER NOT NULL, text TEXT NOT NULL,
              count INTEGER NOT NULL DEFAULT 1, accepted INTEGER NOT NULL DEFAULT 0,
              rejected INTEGER NOT NULL DEFAULT 0, self_sourced INTEGER NOT NULL DEFAULT 0,
              last_used REAL NOT NULL, superseded_by TEXT, UNIQUE (surface_id, text))
            """)
        try database.execute("CREATE INDEX entry_prefix ON entry (surface_id, text)")
        try database.run("INSERT INTO schema_version (version) VALUES (1)") { _ in }
        try database.transaction { () throws(PredictStoreError) in
            for surface in 0..<10 {
                try database.run("INSERT INTO surface (bundle_id, role) VALUES (?, ?)") {
                    $0.bind(1, "com.example.editor.\(surface)")
                    $0.bind(2, "AXTextArea")
                }
            }
            for entry in 0..<20_000 {
                try database.run("INSERT INTO entry (surface_id, text, last_used) VALUES (?, ?, ?)") {
                    $0.bind(1, Int64(entry / 2_000 + 1))
                    $0.bind(2, "synthetic corpus line \(entry)")
                    $0.bind(3, Double(entry))
                }
            }
        }
        try database.finishOpening()
    }
}
