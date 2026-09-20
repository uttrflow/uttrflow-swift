// Tests that no Accessibility timeout is set process-wide, so one caller cannot shorten another's (#887).

import Foundation
import Testing

@Suite("Accessibility messaging timeouts")
struct MessagingTimeoutScopeTests {
    @Test("No source sets a messaging timeout on the system-wide element")
    func noProcessWideTimeout() throws {
        let sources = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .appending(path: "Sources")
        let files = try #require(FileManager.default.enumerator(at: sources, includingPropertiesForKeys: nil))
        var offenders: [String] = []
        for case let file as URL in files where file.pathExtension == "swift" {
            let text = try String(contentsOf: file, encoding: .utf8)
            guard text.contains("AXUIElementCreateSystemWide") else { continue }
            let names = text.matches(of: /let (\w+) = AXUIElementCreateSystemWide\(\)/).map { String($0.1) }
            for target in names + ["AXUIElementCreateSystemWide()"]
            where text.contains("AXUIElementSetMessagingTimeout(\(target),") {
                offenders.append("\(file.lastPathComponent): \(target)")
            }
        }
        #expect(offenders.isEmpty, "\(offenders)")
    }
}
