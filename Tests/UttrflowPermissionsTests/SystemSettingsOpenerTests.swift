import Foundation
import Synchronization
import Testing

@testable import UttrflowCore
@testable import UttrflowPermissions

@Suite("SystemSettingsOpener")
struct SystemSettingsOpenerTests {
    @Test(
        "opens the address belonging to each pane",
        arguments: [
            (SystemSettingsPane.microphone, "Privacy_Microphone"),
            (.accessibility, "Privacy_Accessibility"),
            (.appleIntelligence, "com.apple.Siri-Settings.extension"),
        ])
    func opensAddress(pane: SystemSettingsPane, suffix: String) {
        let opened = Mutex<URL?>(nil)
        let opener = SystemSettingsOpener(openURL: { url in opened.withLock { $0 = url } })

        opener.open(pane)

        #expect(opened.withLock { $0 }?.absoluteString.hasSuffix(suffix) == true)
    }
}
