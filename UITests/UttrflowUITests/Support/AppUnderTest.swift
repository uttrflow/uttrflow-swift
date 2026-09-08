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
    static func launch(file: StaticString = #filePath, line: UInt = #line) -> XCUIApplication {
        if !FileManager.default.fileExists(atPath: bundle.path(percentEncoded: false)) {
            XCTFail("dist/Uttrflow.app is not there. Run `make app` first.", file: file, line: line)
        }
        let app = XCUIApplication(url: bundle)
        app.launch()
        return app
    }
}
