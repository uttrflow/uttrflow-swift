import Foundation
import Testing
import UttrflowTestSupport

/// The suite helper is only worth having if it actually removes the file and if it is the
/// only way in. Both halves are asserted here, because the leak it fixes was invisible:
/// the old `defer` emptied the domain, every test passed, and the plists piled up on
/// developers' machines and CI runners for months without anything going red.
///
/// The awkward part is that the leak is not observable at the point it is caused.
/// `cfprefsd` writes a domain back *after* the owning process exits, so a test that
/// deletes the file and checks `fileExists` sees `false` and passes, and the plist
/// reappears once the run is over — which is precisely how the first attempt at this
/// helper shipped a fix that fixed nothing. `settlePreferencesDaemon(for:)` is what makes
/// the leak visible inside the test: asking the daemon about a domain it is still holding
/// makes it write the file back immediately instead of at exit.
@Suite("TemporaryDefaultsSuite")
struct TemporaryDefaultsSuiteTests {
    /// Forces `cfprefsd` to act on `name` now rather than after this process dies.
    ///
    /// Without this the assertions below pass against a helper that leaks, which is not a
    /// hypothetical: they did. Measured at 3/3 either way — a helper that leaves the
    /// domain with the daemon has its file back before this call returns, and one that
    /// does not never sees it again.
    private func settlePreferencesDaemon(for name: String) {
        let tool = Process()
        tool.executableURL = URL(filePath: "/usr/bin/defaults")
        tool.arguments = ["read", name]
        tool.standardOutput = FileHandle.nullDevice
        tool.standardError = FileHandle.nullDevice
        try? tool.run()
        tool.waitUntilExit()
    }

    /// The regression test proper. The `#expect` inside the closure is not decoration —
    /// it proves the file was really there, so the assertion after the closure is
    /// evidence of cleanup rather than of nothing having happened.
    @Test("leaves no file behind, even once the preferences daemon has had its say")
    func leavesNothingBehind() throws {
        var observed: (name: String, fileURL: URL)?

        withTemporaryDefaultsSuite { suite in
            suite.defaults.set(Data([1, 2, 3]), forKey: "settings")
            suite.defaults.synchronize()
            observed = (suite.name, suite.fileURL)
            #expect(FileManager.default.fileExists(atPath: suite.fileURL.path))
        }

        let suite = try #require(observed)
        settlePreferencesDaemon(for: suite.name)
        #expect(!FileManager.default.fileExists(atPath: suite.fileURL.path))
    }

    /// The domain, not only its file: a name that still resolved to live values would
    /// leak state into whichever test drew the same name next.
    ///
    /// Read through `persistentDomain(forName:)` rather than by opening the suite again.
    /// `UserDefaults(suiteName:)` would register the domain with `cfprefsd` a second time,
    /// and this test would then be the thing recreating the plist it exists to prove is
    /// gone. `nil` and empty both mean the same thing here, and which one comes back is
    /// not part of what is being asserted.
    @Test("leaves nothing for a later reader of the same name")
    func leavesNoValuesBehind() throws {
        var observed: String?

        withTemporaryDefaultsSuite { suite in
            suite.defaults.set(Data([1, 2, 3]), forKey: "settings")
            suite.defaults.synchronize()
            observed = suite.name
        }

        let name = try #require(observed)
        #expect(UserDefaults.standard.persistentDomain(forName: name)?.isEmpty ?? true)
    }

    /// A failing test has to clean up as thoroughly as a passing one, or the suites that
    /// survive are exactly the ones from the runs somebody was already debugging.
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

    /// The sweep is the half of this that does not depend on winning a race, so it needs
    /// its own evidence: an aged file goes, a fresh one stays.
    ///
    /// The second half matters more than it looks. Two checkouts running their tests at
    /// once is normal in this repository, and a sweep without an age threshold would
    /// delete a suite another process was in the middle of using.
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
        let longAgo = Date().addingTimeInterval(-3600)
        try manager.setAttributes([.modificationDate: longAgo], ofItemAtPath: stale.path)

        TemporaryDefaultsSuite.sweepStaleSuites()

        #expect(!manager.fileExists(atPath: stale.path), "an abandoned file survived the sweep")
        #expect(manager.fileExists(atPath: fresh.path), "the sweep took a file that was still in use")
    }

    /// The helper cannot stop a leak it is not asked about, and the previous version of
    /// this leak was written in perfectly reasonable-looking test code four times over.
    /// So the invariant is enforced against the tree rather than left to review: any test
    /// file that names a defaults domain must reach it through the helper.
    @Test("no test names a defaults domain any other way")
    func everySuiteComesFromTheHelper() throws {
        let testsRoot = URL(filePath: #filePath)
            .deletingLastPathComponent()  // UttrflowCoreTests
            .deletingLastPathComponent()  // Tests

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

        // A scan that reaches nothing is a check that has already stopped working, which
        // is how the original leak survived: silence read as success.
        #expect(scanned > 0, "found no test sources under \(testsRoot.path)")
        #expect(
            offenders.isEmpty,
            """
            These test files name a UserDefaults suite without withTemporaryDefaultsSuite, \
            so the domain they create outlives them as a plist in ~/Library/Preferences: \
            \(offenders.sorted().joined(separator: ", "))
            """
        )
    }
}
