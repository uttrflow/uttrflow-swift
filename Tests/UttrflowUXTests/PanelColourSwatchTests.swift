import UttrflowClipboard
import Testing
@testable import UttrflowUX

@Suite("Colour swatches in panel rows", .bug(id: 4424))
struct PanelColourSwatchTests {
    @Test("a colour swatch uses text beyond the bounded preview")
    func colourSwatchUsesFullText() {
        let text = String(repeating: " ", count: Clip.previewCharacterLimit + 1) + "color: tomato;"
        let clip = Clip(text: text, kind: .colour, copiedAt: PanelFixture.now)
        let row = PanelFixture.page([clip]).rows[0]
        #expect(row.preview.contains("preview truncated"))
        #expect(row.swatch == ClipColour(red: 1, green: 99 / 255, blue: 71 / 255, alpha: 1))
    }
}
