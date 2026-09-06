// Tests for a picture on a row: what it says, the file it draws, and a picture that has gone.
import Foundation
import UttrflowClipboard
import Testing

@testable import UttrflowUX

/// A picture clip has no text, so its row needs something to say, and a gone picture must say so.
@Suite("K4, B8 · a picture on a row")
struct PanelImageRowTests {
    /// Where the pictures live.
    static let folder = URL(filePath: "/tmp/uttrflow-pictures")
    /// A picture clip.
    static let picture = Clip(
        text: "", kind: .image, copiedAt: PanelFixture.now,
        image: ClipImage(file: "a.png", width: 1024, height: 768, bytes: 240_000))

    /// A panel over the picture, with the file present or missing.
    static func panel(missing: Bool = false) -> PanelSnapshot {
        var snapshot = PanelFixture.panel([picture])
        snapshot.imagesFolder = folder
        if missing { snapshot.missingImages = [picture.id] }
        return snapshot
    }

    /// The picture's row.
    static func row(missing: Bool = false) -> PanelRow {
        PanelPresenter.present(panel(missing: missing)).rows[0]
    }

    /// The application it came from, not the pixel dimensions: "which screenshot is this" is the question.
    @Test("a picture row says where it came from and what it weighs")
    func measurements() {
        let fromPreview = Clip(
            text: "", kind: .image, copiedAt: PanelFixture.now, source: "Preview",
            image: ClipImage(file: "a.png", width: 1024, height: 768, bytes: 240_000))
        var snapshot = PanelFixture.panel([fromPreview])
        snapshot.imagesFolder = Self.folder

        let row = PanelPresenter.present(snapshot).rows[0]

        #expect(row.measurements == "Preview · 240 KB")
        #expect(row.summary.isEmpty, "and there is nothing else for it to say")
    }

    /// Clips older than source recording still have to say something, and the numbers are what they have.
    @Test("and falls back to the numbers when it does not know where it came from")
    func measurementsWithoutASource() {
        #expect(Self.row().measurements == "1024 × 768 · 240 KB")
    }

    @Test("and names the file to draw, under the folder it was given")
    func namesTheFile() {
        #expect(Self.row().imageFile == Self.folder.appending(path: "a.png"))
    }

    /// The row stays: the clip is still a record of something copied, and removing it reads as losing it.
    @Test("B8 · a picture that has gone says so, and stays in the list")
    func missingSaysSo() {
        let row = Self.row(missing: true)

        #expect(row.isImageMissing)
        #expect(row.measurements == "The picture is no longer on this Mac")
        #expect(row.imageFile == nil, "there is nothing to draw")
        #expect(PanelPresenter.present(Self.panel(missing: true)).rows.count == 1)
    }

    /// The size of a file that is not there is not the useful half.
    @Test("the reason replaces the numbers rather than joining them")
    func reasonReplacesNumbers() {
        #expect(Self.row(missing: true).measurements?.contains("1024") == false)
    }

    /// A picture is not a string, and a paste that sent one as text would arrive as nothing.
    @Test("Return on a picture asks for a picture paste, not a text one")
    func picturesTakeTheirOwnPath() {
        let effect = Self.panel().applying(.return).outcome.effect

        guard case .closeAndInsertImage(let clip) = effect else {
            Issue.record("a picture was about to be pasted as text")
            return
        }
        #expect(clip.id == Self.picture.id)
    }

    /// "Nothing to paste" is a different answer from "could not be placed", and ⌘V would find nothing.
    @Test("B8 · Return on a missing picture says so rather than pretending")
    func missingIsRefused() {
        let effect = Self.panel(missing: true).applying(.return).outcome.effect

        guard case .say(let notice) = effect else {
            Issue.record("pasted a picture that is not there")
            return
        }
        #expect(notice.message.contains("no longer"))
    }

    /// Even where nothing could be placed anyway, the missing picture is the more specific answer.
    @Test("and says it even when the caret is elsewhere")
    func missingOutranksTheObstacle() {
        var panel = Self.panel(missing: true)
        panel.insertion = .clipboardOnly(.nothingFocused)

        if case .copyAndSay = panel.applying(.return).outcome.effect {
            Issue.record("offered ⌘V for a picture that is not on the clipboard")
        }
    }

    @Test("an ordinary clip is unaffected by any of this")
    func textIsUntouched() {
        let text = PanelFixture.clip("just words", minutesAgo: 1)
        let row = PanelPresenter.present(PanelFixture.panel([text])).rows[0]

        #expect(row.measurements == nil)
        #expect(row.imageFile == nil)
        #expect(!row.isImageMissing)
    }
}
