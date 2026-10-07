import Foundation
import Testing

import UttrflowCore

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
    /// A file written before the two stores agreed on a spelling holds both, and the refusal is the one to keep.
    @Test("A file holding one application under two spellings reads back as one refusal.")
    func bothSpellingsFoldOnLoad() throws {
        let scratch = Scratch()
        try scratch.write(
            """
            {"consent": {"com.example.terminal": "declined", "com.Example.Terminal": "allowed"},
             "hasImportedShellHistory": false}
            """, to: "capture.json")

        let preferences = CapturePreferencesFile(path: scratch.path("capture.json")).load()

        #expect(preferences.consent == ["com.example.terminal": .declined])
        #expect(preferences.state(of: "com.Example.Terminal") == .declined)
    }

    @Test("Dictation reads the answers typing capture keeps: a refusal stops it, no answer does not.")
    func dictationReadsTheSameAnswers() async throws {
        let scratch = Scratch()
        try scratch.write(
            """
            {"consent": {"com.example.terminal": "declined", "com.example.browser": "allowed"}}
            """, to: "capture.json")
        let file = CapturePreferencesFile(path: scratch.path("capture.json"))

        #expect(await file.mayLearn(from: "com.Example.Terminal") == false)
        #expect(await file.mayLearn(from: "com.example.browser"))
        #expect(await file.mayLearn(from: "com.example.notes"))
        #expect(await file.mayLearn(from: nil))
    }

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

    @Test("A corrupt file is set aside before a new answer is saved, so its bytes survive.")
    func corruptFileSurvivesSave() throws {
        let scratch = Scratch()
        try scratch.write("{", to: "capture.json")
        let file = CapturePreferencesFile(path: scratch.path("capture.json"))
        var preferences = file.load()
        #expect(preferences == CapturePreferences())
        preferences.record(.allowed, for: "com.example.terminal")
        try file.save(preferences)
        let names = try FileManager.default.contentsOfDirectory(atPath: scratch.directory)
        let setAside = try #require(names.first { $0.hasPrefix("capture.json.unreadable-") })
        #expect(try String(contentsOfFile: scratch.path(setAside), encoding: .utf8) == "{")
        #expect(file.load() == preferences)
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

    @Test("Removing the file forgets every answer, and removing it again is not an error.")
    func removedPreferencesAreGone() throws {
        let scratch = Scratch()
        let file = CapturePreferencesFile(path: scratch.preferencesPath)
        var preferences = CapturePreferences()
        preferences.record(.declined, for: "com.example.terminal")
        try file.save(preferences)
        try file.remove()
        #expect(!FileManager.default.fileExists(atPath: scratch.preferencesPath))
        #expect(file.load() == CapturePreferences())
        try file.remove()
    }
}

@Suite("Where the answers about each application live")
struct CapturePreferencesLocationTests {
    @Test("They sit beside the corpus they gate, versioned in the name.")
    func besideTheCorpus() {
        let file = CapturePreferencesFile.defaultFile(in: URL(filePath: "/tmp/support"))
        #expect(
            file.path(percentEncoded: false) == "/tmp/support/Uttrflow/predict-consent.v1.json")
    }
}

@Suite("Removing the answers")
struct CapturePreferencesFileRemovalTests {
    @Test("Removing deletes the file, and removing a file that is not there is not an error.")
    func removeDeletesTheFile() throws {
        let scratch = Scratch()
        let file = CapturePreferencesFile(path: scratch.preferencesPath)
        try file.save(CapturePreferences(consent: ["com.example.terminal": .allowed]))
        try file.remove()
        #expect(!FileManager.default.fileExists(atPath: scratch.preferencesPath))
        try file.remove()
    }
}
