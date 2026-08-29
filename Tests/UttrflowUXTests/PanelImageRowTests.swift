import Foundation
import UttrflowClipboard
import Testing

@testable import UttrflowUX

/// K4 and B8 as the row shows them. A picture clip has no text, so without these its row
/// is a blank line with an icon — and a picture whose file has gone is a row that pastes
/// nothing while looking exactly like one that would.
@Suite("K4, B8 · a picture on a row")
struct PanelImageRowTests {
    static let folder = URL(filePath: "/tmp/uttrflow-pictures")
    static let picture = Clip(
        text: "", kind: .image, copiedAt: PanelFixture.now,
        image: ClipImage(file: "a.png", width: 1024, height: 768, bytes: 240_000))

    static func panel(missing: Bool = false) -> PanelSnapshot {
        var snapshot = PanelFixture.panel([picture])
        snapshot.imagesFolder = folder
        if missing { snapshot.missingImages = [picture.id] }
        return snapshot
    }

    static func row(missing: Bool = false) -> PanelRow {
        PanelPresenter.present(panel(missing: missing)).rows[0]
    }

    /// The application it came from, not the pixel dimensions.
    ///
    /// The question a picture row has to answer is "which screenshot is this", and
    /// 1024 × 768 does not answer it. A file name would answer it better and there is
    /// never one: a screenshot copied with the keyboard puts raw PNG on the pasteboard
    /// and nothing else, and an image file copied in Finder arrives as a path and
    /// becomes a file clip whose row already shows that path.
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

    /// Clips old enough to predate the source being recorded still have to say
    /// something, and the numbers are what they have.
    @Test("and falls back to the numbers when it does not know where it came from")
    func measurementsWithoutASource() {
        #expect(Self.row().measurements == "1024 × 768 · 240 KB")
    }

    @Test("and names the file to draw, under the folder it was given")
    func namesTheFile() {
        #expect(Self.row().imageFile == Self.folder.appending(path: "a.png"))
    }

    /// B8 — the row stays. The clip is still a real record of something copied, and
    /// removing it would look like the app had lost it rather than the file having gone.
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

    /// A picture is not a string, and a paste that sent one as text would arrive as
    /// nothing at all.
    @Test("Return on a picture asks for a picture paste, not a text one")
    func picturesTakeTheirOwnPath() {
        let effect = Self.panel().applying(.return).outcome.effect

        guard case .closeAndInsertImage(let clip) = effect else {
            Issue.record("a picture was about to be pasted as text")
            return
        }
        #expect(clip.id == Self.picture.id)
    }

    /// "There is nothing to paste" is a different answer from "it could not be placed",
    /// and the second would send the user to press ⌘V for something that is not on the
    /// clipboard either.
    @Test("B8 · Return on a missing picture says so rather than pretending")
    func missingIsRefused() {
        let effect = Self.panel(missing: true).applying(.return).outcome.effect

        guard case .say(let notice) = effect else {
            Issue.record("pasted a picture that is not there")
            return
        }
        #expect(notice.message.contains("no longer"))
    }

    /// Even on a machine where nothing could be placed anyway, the missing picture is the
    /// more specific answer and the one worth giving.
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
