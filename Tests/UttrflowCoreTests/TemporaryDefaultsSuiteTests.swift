// Tests for TemporaryDefaultsSuite.

import Foundation
import Testing
import UttrflowTestSupport

/// Covers the suite helper's cleanup and its sweep. See `Docs/preferences-suites.md`.
@Suite("TemporaryDefaultsSuite")
struct TemporaryDefaultsSuiteTests {
    /// Makes `cfprefsd` act on the domain now, so a leak is visible here rather than after exit.
    private func settlePreferencesDaemon(for name: String) {
        let tool = Process()
        tool.executableURL = URL(filePath: "/usr/bin/defaults")
        tool.arguments = ["read", name]
        tool.standardOutput = FileHandle.nullDevice
        tool.standardError = FileHandle.nullDevice
        try? tool.run()
        tool.waitUntilExit()
    }

    @Test("leaves no file behind, even once the preferences daemon has had its say")
    func leavesNothingBehind() throws {
        var observed: (name: String, fileURL: URL)?

        withTemporaryDefaultsSuite { suite in
            suite.defaults.set(Data([1, 2, 3]), forKey: "settings")
            suite.defaults.synchronize()
            observed = (suite.name, suite.fileURL)
            // Asserting the file is here first makes the assertion after the closure mean something.
            #expect(FileManager.default.fileExists(atPath: suite.fileURL.path))
        }

        let suite = try #require(observed)
        settlePreferencesDaemon(for: suite.name)
        #expect(!FileManager.default.fileExists(atPath: suite.fileURL.path))
    }

    /// The domain and not only its file, so a later test drawing the same name sees nothing.
    @Test("leaves nothing for a later reader of the same name")
    func leavesNoValuesBehind() throws {
        var observed: String?

        withTemporaryDefaultsSuite { suite in
            suite.defaults.set(Data([1, 2, 3]), forKey: "settings")
            suite.defaults.synchronize()
            observed = suite.name
        }

        let name = try #require(observed)
        // Read through `persistentDomain` so this does not register the domain a second time.
        #expect(UserDefaults.standard.persistentDomain(forName: name)?.isEmpty ?? true)
    }

    @Test("cleans up even when the body it wraps throws")
    func cleansUpOnFailure() throws {
        struct Failure: Error {}
        var observed: (name: String, fileURL: URL)?

        #expect(throws: Failure.self) {
            try withTemporaryDefaultsSuite { suite in
                suite.defaults.set(Data([1, 2, 3]), forKey: "settings")
                suite.defaults.synchronize()
                observed = (suite.name, suite.fileURL)
                throw Failure()
            }
        }

        let suite = try #require(observed)
        settlePreferencesDaemon(for: suite.name)
        #expect(!FileManager.default.fileExists(atPath: suite.fileURL.path))
    }

    /// The age threshold is what keeps a suite belonging to a concurrent test process safe.
    @Test("removes abandoned domain files and spares ones still in use")
    func sweepsOnlyStaleFiles() throws {
        let manager = FileManager.default
        let prefix = TemporaryDefaultsSuite.namePrefix
        let stale = TemporaryDefaultsSuite.domainFileURL(forName: prefix + UUID().uuidString)
        let fresh = TemporaryDefaultsSuite.domainFileURL(forName: prefix + UUID().uuidString)
        defer {
            try? manager.removeItem(at: stale)
            try? manager.removeItem(at: fresh)
        }

        #expect(manager.createFile(atPath: stale.path, contents: Data()))
        #expect(manager.createFile(atPath: fresh.path, contents: Data()))
        try manager.setAttributes(
            [.modificationDate: Date().addingTimeInterval(-3600)],
            ofItemAtPath: stale.path
        )

        TemporaryDefaultsSuite.sweepStaleSuites()

        #expect(!manager.fileExists(atPath: stale.path), "an abandoned file survived the sweep")
        #expect(manager.fileExists(atPath: fresh.path), "the sweep took a file that was still in use")
    }

    /// Enforces against the tree what the helper cannot enforce for a test that ignores it.
    @Test("no test names a defaults domain any other way")
    func everySuiteComesFromTheHelper() throws {
        let testsRoot = URL(filePath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()

        let enumerator = try #require(
            FileManager.default.enumerator(at: testsRoot, includingPropertiesForKeys: nil)
        )

        var scanned = 0
        var offenders: [String] = []
        for case let url as URL in enumerator where url.pathExtension == "swift" {
            scanned += 1
            let source = try String(contentsOf: url, encoding: .utf8)
            guard source.contains("suiteName:") else { continue }
            if !source.contains("withTemporaryDefaultsSuite") {
                offenders.append(url.lastPathComponent)
            }
        }

        // A scan that reaches nothing is a check that has stopped working.
        #expect(scanned > 0, "found no test sources under \(testsRoot.path)")
        #expect(
            offenders.isEmpty,
            "these name a UserDefaults suite without the helper: \(offenders.sorted())"
        )
    }
}
