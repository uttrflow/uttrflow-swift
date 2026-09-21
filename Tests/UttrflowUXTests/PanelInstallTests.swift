// Tests that a clip list installed into an open panel carries what the machine said about it.
import Foundation
import Testing
import UttrflowClipboard

@testable import UttrflowUX

@Suite("Installing a new clip list into an open panel")
struct PanelInstallTests {
    static let python = Clip(
        text: "def a():\n  return 1", kind: .code, copiedAt: PanelFixture.now, language: .python)

    @Test("a code clip arriving while open is offered Format when its formatter is installed")
    func arrivingCodeIsFormattable() {
        var snapshot = PanelFixture.panel([PanelFixture.clip("words", minutesAgo: 1)])
        snapshot.install(
            [Self.python] + snapshot.clips, missingImages: [], formattableLanguages: [.python])
        let row = PanelPresenter.present(snapshot).rows[0]
        #expect(row.actions.map(\.title).contains("Format"))
    }

    @Test("a picture whose file went while open is refused with the missing-picture notice")
    func vanishedPictureIsRefused() {
        let picture = Clip(
            text: "", kind: .image, copiedAt: PanelFixture.now,
            image: ClipImage(file: "gone.png", width: 1, height: 1, bytes: 1, sha: "00"))
        var snapshot = PanelFixture.panel([picture])
        snapshot.install([picture], missingImages: [picture.id], formattableLanguages: [])
        guard case .say = snapshot.applying(.return).outcome.effect else {
            Issue.record("Return on a missing picture should say so, not insert")
            return
        }
    }
}
