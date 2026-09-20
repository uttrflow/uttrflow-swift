// Tests that a picture clip reaches the clipboard as a picture on every path, never as its empty text.
import Foundation
import Testing
import UttrflowClipboard

@testable import UttrflowUX

@Suite("A picture is copied as a picture")
struct PanelPictureCopyTests {
    /// A picture clip, whose text is empty because the picture lives in a file.
    static let picture = PanelImageRowTests.picture

    /// A panel over the picture, placing at the caret or only copying, with its file present or missing.
    static func panel(insertion: PanelInsertion = .atCaret, missing: Bool = false) -> PanelSnapshot {
        var snapshot = PanelImageRowTests.panel(missing: missing)
        snapshot.insertion = insertion
        return snapshot
    }

    /// Every way the panel can be asked to place a clip.
    static let insertions: [PanelInsertion] =
        [.atCaret] + PanelInsertionObstacle.allCases.map { .clipboardOnly($0) }

    @Test(
        "Return while the panel can only copy puts the picture on the clipboard",
        arguments: PanelInsertionObstacle.allCases)
    func copyOnlyCopiesThePicture(_ obstacle: PanelInsertionObstacle) {
        let effect = Self.panel(insertion: .clipboardOnly(obstacle)).applying(.return).outcome.effect

        #expect(effect == .copyImageAndSay(Self.picture, obstacle.notice))
    }

    @Test("the row's Copy on a picture copies the picture and closes")
    func rowCopyCopiesThePicture() {
        #expect(Self.panel().copying(Self.picture.id).outcome.effect == .closeAndCopyImage(Self.picture))
    }

    @Test("the row's Copy on a missing picture says it has gone")
    func rowCopyOnMissingPicture() {
        guard case .say(let notice) = Self.panel(missing: true).copying(Self.picture.id).outcome.effect else {
            Issue.record("copied a picture that is not there")
            return
        }
        #expect(notice.message.contains("no longer"))
    }

    @Test("the row's Copy on text copies the text with its formatting and closes")
    func rowCopyOnText() {
        let clip = Clip(
            text: "just words", kind: .text, copiedAt: PanelFixture.now, richText: "**just** words")
        let effect = PanelFixture.panel([clip]).copying(clip.id).outcome.effect

        #expect(effect == .closeAndCopy("just words", richText: "**just** words", used: clip.id))
    }

    @Test("the row's Copy on a clip no longer listed does nothing")
    func rowCopyOnUnknownClip() {
        #expect(Self.panel().copying(UUID()).outcome == .open)
    }

    @Test("⌘Return on a picture answers as Return does", arguments: insertions)
    func plainReturnIsReturn(_ insertion: PanelInsertion) {
        for missing in [false, true] {
            let panel = Self.panel(insertion: insertion, missing: missing)
            #expect(panel.applying(.returnPlain).outcome == panel.applying(.return).outcome)
        }
    }

    @Test("⌘Return on a missing picture says it has gone")
    func plainReturnOnMissingPicture() {
        guard case .say = Self.panel(missing: true).applying(.returnPlain).outcome.effect else {
            Issue.record("pasted a picture that is not there")
            return
        }
    }

    @Test("Make a note is not offered on a picture, and asking for it changes nothing")
    func noNoteFromAPicture() {
        let row = PanelPresenter.present(Self.panel()).rows[0]

        #expect(!row.actions.map(\.title).contains("Make a note"))
        #expect(Self.panel().applying(.makeNote(Self.picture.id)).outcome == .open)
    }

    @Test("no path for a picture carries its empty text to the clipboard or the caret")
    func neverAnEmptyString() {
        for insertion in Self.insertions {
            for missing in [false, true] {
                let panel = Self.panel(insertion: insertion, missing: missing)
                let effects = [
                    panel.applying(.return).outcome.effect, panel.applying(.returnPlain).outcome.effect,
                    panel.copying(Self.picture.id).outcome.effect,
                ]
                for effect in effects {
                    #expect(!Self.carriesText(effect), "\(insertion) missing=\(missing): \(effect)")
                }
            }
        }
    }

    /// Whether an effect writes a string, which for a picture would be its empty text.
    private static func carriesText(_ effect: PanelEffect) -> Bool {
        switch effect {
        case .closeAndInsert, .closeAndInsertFormatted, .copyAndSay, .closeAndCopy: true
        case .redraw, .close, .applyAndRedraw, .closeAndInsertImage, .say, .copyImageAndSay,
            .closeAndCopyImage:
            false
        }
    }
}
