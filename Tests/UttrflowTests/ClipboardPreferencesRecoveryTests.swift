// An unreadable privacy list must stop capture until its saved copy is restored.

import Foundation
import UttrflowClipboard
import UttrflowUX
import Testing

@testable import Uttrflow

@MainActor
@Suite("Clipboard privacy recovery")
struct ClipboardPreferencesRecoveryTests {
    @Test("unreadable exclusions pause capture and can be restored from the saved copy")
    func unreadableExclusionsPauseCaptureUntilRestored() throws {
        let root = FileManager.default.temporaryDirectory
            .appending(path: "uttrflow-clipboard-recovery-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: root) }

        let preferencesURL = ClipboardPreferencesFile.defaultFile(in: root)
        try FileManager.default.createDirectory(
            at: preferencesURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data("{".utf8).write(to: preferencesURL)

        let app = AppDelegate(container: root)
        #expect(app.isClipboardPaused)
        #expect(app.actionNotice?.message.contains("Your exclusion list could not be read") == true)
        #expect(app.actionNotice?.action?.intent == .restoreClipboardPreferences)

        let savedPreferences = ClipboardPreferences(
            excludedBundleIdentifiers: ["com.example.private"])
        let savedCopy = try #require(
            FileManager.default.contentsOfDirectory(
                at: preferencesURL.deletingLastPathComponent(), includingPropertiesForKeys: nil
            ).first { $0.lastPathComponent.hasPrefix("\(preferencesURL.lastPathComponent).unreadable-") })
        try JSONEncoder().encode(savedPreferences).write(to: savedCopy)

        app.carryOut(.restoreClipboardPreferences)

        #expect(!app.isClipboardPaused)
        #expect(app.actionNotice == nil)
        #expect(ClipboardPreferencesFile(path: preferencesURL.path).load().value == savedPreferences)
    }
}
