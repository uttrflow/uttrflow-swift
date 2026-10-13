// The bundle `make app` produced, driven as it ships rather than rebuilt by Xcode.

import XCTest

/// Launches `dist/Uttrflow.app`, so SwiftPM stays the build system and Xcode is only the runner.
enum AppUnderTest {
    /// The repository root, found from this file rather than from a working directory Xcode picks.
    static var repositoryRoot: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
    }

    /// The bundle under test, which `make app` writes and this target never builds.
    static var bundle: URL { repositoryRoot.appending(path: "dist/Uttrflow.app") }

    /// The app, launched and ready, or a failure naming the missing bundle rather than a timeout.
    @MainActor
    static func launch(file: StaticString = #filePath, line: UInt = #line) -> XCUIApplication {
        if !FileManager.default.fileExists(atPath: bundle.path(percentEncoded: false)) {
            XCTFail("dist/Uttrflow.app is not there. Run `make app` first.", file: file, line: line)
        }
        let container = FileManager.default.temporaryDirectory
            .appending(path: "uttrflow-ui-\(UUID().uuidString)", directoryHint: .isDirectory)
        do {
            try FileManager.default.createDirectory(at: container, withIntermediateDirectories: true)
        } catch {
            XCTFail("could not create isolated app container: \(error)", file: file, line: line)
        }
        let app = XCUIApplication(url: bundle)
        app.launchEnvironment["UTTRFLOW_TEST_CONTAINER"] = container.path(percentEncoded: false)
        app.launch()
        return app
    }

    /// The disposable folder whose stores and singleton locks belong to this launch.
    @MainActor
    static func container(for app: XCUIApplication) -> URL? {
        app.launchEnvironment["UTTRFLOW_TEST_CONTAINER"].map {
            URL(fileURLWithPath: $0, isDirectory: true)
        }
    }

    /// The defaults domain paired with a disposable container.
    static func defaultsSuite(for container: URL) -> String {
        "com.uttrflow.UITests.\(container.lastPathComponent)"
    }

    /// What the app saved under `key` in its suite, read from the file because the sandboxed runner's `UserDefaults` cannot see it.
    static func savedValue(forKey key: String, container: URL) -> Data? {
        guard let entry = getpwuid(getuid()), let home = entry.pointee.pw_dir else { return nil }
        let plist = URL(fileURLWithPath: String(cString: home), isDirectory: true)
            .appending(path: "Library/Preferences/\(defaultsSuite(for: container)).plist")
        guard let data = try? Data(contentsOf: plist),
            let list = try? PropertyListSerialization.propertyList(from: data, format: nil),
            let values = list as? [String: Any]
        else { return nil }
        return values[key] as? Data
    }

    /// Stops the app before removing the stores it used during this test.
    @MainActor
    static func terminate(_ app: XCUIApplication) {
        let container = container(for: app)
        app.terminate()
        guard app.wait(for: .notRunning, timeout: 20), let container else { return }
        UserDefaults(suiteName: defaultsSuite(for: container))?.removePersistentDomain(
            forName: defaultsSuite(for: container))
        try? FileManager.default.removeItem(at: container)
    }
}
