public import Foundation

/// A real `UserDefaults` domain that cannot outlive the test that asked for it.
///
/// A few tests have to touch real preferences: the adapters over `UserDefaults` claim
/// only that bytes go in and come back, and nothing short of the real thing would notice
/// if that stopped being true. Each of those tests used to name its own suite and clean
/// up with `removePersistentDomain(forName:)` in a `defer`, which looks complete and is
/// not. Emptying a domain does not remove it: `cfprefsd` writes
/// `~/Library/Preferences/<suite>.plist` on the first write, and neither
/// `removePersistentDomain(forName:)` nor `removeSuite(named:)` — which only edits a
/// search list — takes the file away again. So every `make verify` left one empty plist
/// per test behind on whatever machine ran it, for ever: 466 of them on the first Mac
/// anybody counted, and the same accumulation on every CI runner.
///
/// Deleting the file is necessary and, on its own, still not enough — `remove()` carries
/// the surprising half of this, and is worth reading before changing any of it.
///
/// The fix is not a more careful `defer`, it is removing the choice. This is the only way
/// to get a suite, the cleanup sits on the far side of the closure where no test can
/// forget it, and `TemporaryDefaultsSuiteTests` fails if a test ever names one another
/// way.
public struct TemporaryDefaultsSuite {
    /// The domain name, for the adapters that take one rather than a `UserDefaults`.
    public let name: String

    /// The domain itself.
    ///
    /// Held as an instance, unlike `SystemUserDefaults` and `SystemDefaultsStorage`,
    /// which store a name and resolve it on each access to stay `Sendable`. Those are
    /// long-lived adapters in shipped code; this is a handle that exists only inside one
    /// synchronous closure. Resolving once is also what lets the failure be loud —
    /// falling back to `.standard` on a nil suite would write the test's data into the
    /// preferences of whoever ran it, which is the bug class this type exists to end.
    public let defaults: UserDefaults

    /// Where `cfprefsd` keeps this domain. Exposed so a test can assert the file is
    /// gone; deleting it is necessary to clean up but, on its own, not sufficient — see
    /// `remove()`.
    public var fileURL: URL { Self.fileURL(forName: name) }

    /// Resolved through the library directory rather than hard-coded under `$HOME`, so it
    /// stays correct if these tests are ever run from inside a sandbox, where the
    /// domain's file lives in the container instead.
    static func fileURL(forName name: String) -> URL {
        let library =
            FileManager.default.urls(for: .libraryDirectory, in: .userDomainMask).first
            ?? URL.homeDirectory.appending(path: "Library", directoryHint: .isDirectory)
        return library.appending(path: "Preferences/\(name).plist")
    }

    /// Empties the domain, has `cfprefsd` forget it, and only then deletes the file.
    ///
    /// Both the order and the trip through `/usr/bin/defaults` are load-bearing, for the
    /// reason that is the genuinely surprising part of this. `cfprefsd` keeps its own copy of every
    /// domain a process has opened and writes it back **after that process exits**. So a
    /// test can empty the domain, delete the file, watch `fileExists` return `false`,
    /// pass — and the plist is on disk again twenty seconds after the run finishes.
    /// That is what the first version of this helper did, and it leaked exactly as
    /// thoroughly as the `defer` it replaced.
    ///
    /// Nothing in-process dislodges the daemon's copy. `removePersistentDomain(forName:)`,
    /// `removeSuite(named:)` and `CFPreferencesSynchronize` were each measured against a
    /// thirty-second wait after exit, and all three leave the domain live. Asking the
    /// daemon from another process is the only thing that works, because the registration
    /// being flushed belongs to *this* process. Hence `/usr/bin/defaults delete`, which
    /// costs a few milliseconds a suite and is the difference between this helper working
    /// and merely looking as though it does.
    ///
    /// Deliberately not `public`. A test in another module can obtain a suite only from
    /// `withTemporaryDefaultsSuite(_:)`, so it cannot take the handle and skip this.
    func remove() {
        defaults.removePersistentDomain(forName: name)
        defaults.removeSuite(named: name)
        UserDefaults.standard.removeSuite(named: name)
        Self.preferencesDaemonForget(name)
        try? FileManager.default.removeItem(at: fileURL)
    }

    /// Hands the domain to `cfprefsd` for removal from outside this process. Failure is
    /// ignored on purpose: `defaults delete` exits non-zero for a domain that is already
    /// gone, which is the good case, and a test must not fail over its own tidying.
    private static func preferencesDaemonForget(_ name: String) {
        let tool = Process()
        tool.executableURL = URL(filePath: "/usr/bin/defaults")
        tool.arguments = ["delete", name]
        tool.standardOutput = FileHandle.nullDevice
        tool.standardError = FileHandle.nullDevice
        try? tool.run()
        tool.waitUntilExit()
    }
}

/// Runs `body` against a defaults domain that lasts exactly as long as the call.
///
/// The domain is emptied and its file deleted whether `body` returns or throws, so a
/// failing test cleans up as thoroughly as a passing one.
///
/// - Parameter body: Receives the suite. Its name goes to any adapter taking a
///   `suiteName:`; its `defaults` is the domain itself.
/// - Returns: Whatever `body` returns.
public func withTemporaryDefaultsSuite<T>(_ body: (TemporaryDefaultsSuite) throws -> T) rethrows -> T {
    let name = "com.uttrflow.tests.\(UUID().uuidString)"
    guard let defaults = UserDefaults(suiteName: name) else {
        // Unreachable. `init(suiteName:)` refuses only a nil name, the main bundle's own
        // identifier and the global domain, none of which a fresh UUID can collide with.
        // Trapping rather than falling back to `.standard`, which would quietly write
        // the test's data into the preferences of whoever is running it.
        fatalError("UserDefaults refused the suite name \(name)")
    }
    let suite = TemporaryDefaultsSuite(name: name, defaults: defaults)
    defer { suite.remove() }
    return try body(suite)
}
