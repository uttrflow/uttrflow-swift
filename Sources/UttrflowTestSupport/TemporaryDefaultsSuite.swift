// A UserDefaults suite that lives for one test.
public import Foundation

/// A real `UserDefaults` domain that does not outlive the closure it is made for.
public struct TemporaryDefaultsSuite {
    /// The domain name, for adapters that take one rather than a `UserDefaults`.
    public let name: String

    /// The domain itself, resolved once so a nil suite fails loudly instead of writing to `.standard`.
    public let defaults: UserDefaults

    /// The prefix every domain from this helper shares, so a later run can recognise one.
    public static let namePrefix = "com.uttrflow.tests."

    /// Where `cfprefsd` keeps this domain.
    public var fileURL: URL { Self.domainFileURL(forName: name) }

    /// Resolves a domain's file through the library directory, so a sandboxed run finds its container.
    public static func domainFileURL(forName name: String) -> URL {
        let library =
            FileManager.default.urls(for: .libraryDirectory, in: .userDomainMask).first
            ?? URL.homeDirectory.appending(path: "Library", directoryHint: .isDirectory)
        return library.appending(path: "Preferences/\(name).plist")
    }

    /// Removes domain files abandoned by runs that have finished. See `Docs/preferences-suites.md`.
    public static func sweepStaleSuites(olderThan age: TimeInterval = 600) {
        let directory = domainFileURL(forName: "unused").deletingLastPathComponent()
        let manager = FileManager.default
        guard let entries = try? manager.contentsOfDirectory(atPath: directory.path) else { return }
        // A suite in use is seconds old, so an age threshold keeps a concurrent run's domain safe.
        let cutoff = Date().addingTimeInterval(-age)
        for entry in entries
        where entry.hasPrefix(namePrefix) && entry.hasSuffix(".plist") {
            let url = directory.appending(path: entry)
            let modified = try? url.resourceValues(forKeys: [.contentModificationDateKey])
                .contentModificationDate
            guard let modified, modified < cutoff else { continue }
            preferencesDaemonForget(String(entry.dropLast(".plist".count)))
            try? manager.removeItem(at: url)
        }
    }

    /// Empties the domain, has `cfprefsd` forget it, then deletes the file, in that order.
    func remove() {
        defaults.removePersistentDomain(forName: name)
        // Flushes this process's own pending write before the daemon is asked to drop the domain.
        defaults.synchronize()
        defaults.removeSuite(named: name)
        UserDefaults.standard.removeSuite(named: name)
        Self.preferencesDaemonForget(name)
        try? FileManager.default.removeItem(at: fileURL)
    }

    /// Asks `cfprefsd` from outside this process to drop the domain, which nothing in-process does.
    static func preferencesDaemonForget(_ name: String) {
        let tool = Process()
        tool.executableURL = URL(filePath: "/usr/bin/defaults")
        tool.arguments = ["delete", name]
        tool.standardOutput = FileHandle.nullDevice
        tool.standardError = FileHandle.nullDevice
        // `defaults delete` exits non-zero for a domain that is already gone, which is the good case.
        try? tool.run()
        tool.waitUntilExit()
    }
}

/// Sweeps suites abandoned by earlier runs, once per test process.
private let sweptStaleSuites: Void = TemporaryDefaultsSuite.sweepStaleSuites()

/// Runs `body` against a defaults domain that is emptied and removed whether it returns or throws.
public func withTemporaryDefaultsSuite<T>(_ body: (TemporaryDefaultsSuite) throws -> T) rethrows -> T {
    _ = sweptStaleSuites
    let name = TemporaryDefaultsSuite.namePrefix + UUID().uuidString
    guard let defaults = UserDefaults(suiteName: name) else {
        // `init(suiteName:)` refuses only a nil name, the main bundle's identifier and the global domain.
        fatalError("UserDefaults refused the suite name \(name)")
    }
    let suite = TemporaryDefaultsSuite(name: name, defaults: defaults)
    defer { suite.remove() }
    return try body(suite)
}
