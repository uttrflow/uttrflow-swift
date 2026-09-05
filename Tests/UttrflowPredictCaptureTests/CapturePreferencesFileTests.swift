import Foundation
import Testing

@testable import UttrflowPredictCapture

/// A preferences file of its own per test, removed when the test ends.
struct Scratch: ~Copyable {
    let directory: String

    init() {
        directory = NSTemporaryDirectory() + "uttrflow-capture-\(UUID().uuidString)"
    }

    var preferencesPath: String { directory + "/nested/capture.json" }

    func path(_ name: String) -> String { directory + "/" + name }

    /// Writes a file inside the scratch directory, creating the directory on the way.
    func write(_ contents: String, to name: String) throws {
        try FileManager.default.createDirectory(atPath: directory, withIntermediateDirectories: true)
        try contents.write(toFile: path(name), atomically: true, encoding: .utf8)
    }

    deinit { try? FileManager.default.removeItem(atPath: directory) }
}

@Suite("Keeping the answers between launches")
struct CapturePreferencesFileTests {
    @Test("A file that was never written reads back as nothing having been decided.")
    func missingFileIsEmpty() {
        let scratch = Scratch()
        let preferences = CapturePreferencesFile(path: scratch.preferencesPath).load()
        #expect(preferences == CapturePreferences())
    }

    @Test("A file holding something that is not preferences reads back as nothing, rather than throwing.")
    func unreadableFileIsEmpty() throws {
        let scratch = Scratch()
        try scratch.write("not json", to: "capture.json")
        #expect(CapturePreferencesFile(path: scratch.path("capture.json")).load() == CapturePreferences())
    }

    @Test("What was saved is what comes back, directories and all.")
    func savedPreferencesReturn() throws {
        let scratch = Scratch()
        let file = CapturePreferencesFile(path: scratch.preferencesPath)
        var preferences = CapturePreferences()
        preferences.record(.allowed, for: "com.example.terminal")
        preferences.hasImportedShellHistory = true
        try file.save(preferences)
        #expect(file.load() == preferences)
    }
}
