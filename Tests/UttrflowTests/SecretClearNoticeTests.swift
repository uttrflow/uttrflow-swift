// Tests the clearing delay the app adds to its own notices for a copied secret.

import Testing
import UttrflowUX

@testable import Uttrflow

@Suite("What the app's own notices say about a copied secret")
struct SecretClearNoticeTests {
    @Test("the panel's notice for a copied secret says when it leaves the clipboard")
    func panelNoticeNamesTheDelay() {
        let plain = PanelInsertionObstacle.nothingFocused.copiedNotice
        let blocked = PanelInsertionObstacle.accessibilityNotGranted.copiedNotice

        #expect(
            plain.namingSecretClear(after: 30).message
                == "Copied — press ⌘V where you want it. It leaves the clipboard in 30 seconds")
        #expect(
            blocked.namingSecretClear(after: 1).message
                == "\(blocked.message) It leaves the clipboard in 1 second.")
        #expect(blocked.namingSecretClear(after: 1).action == blocked.action)
        #expect(plain.namingSecretClear(after: 0) == plain)
    }

    @Test("the main window's message gains the delay only when clearing is on")
    func mainWindowMessage() {
        let copied = "Copied — click where you want it, then press ⌘V"

        #expect(
            SecretClearNotice.appending(to: copied, after: 60)
                == "\(copied). It leaves the clipboard in 60 seconds")
        #expect(SecretClearNotice.appending(to: copied, after: 0) == copied)
    }
}
