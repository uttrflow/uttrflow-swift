// Tests that a file clip reaches the clipboard as its files on every path, and says when one has gone.
import Foundation
import Testing
import UttrflowClipboard

@testable import UttrflowUX

@Suite("A file clip is placed as files")
struct PanelFileClipTests {
    static let files = [
        ClipFileReference(path: "/tmp/uttrflow-one/report.pdf"),
        ClipFileReference(path: "/tmp/uttrflow-one/notes.txt"),
    ]
    static let clip = Clip(
        text: "report.pdf\nnotes.txt", kind: .file, copiedAt: PanelFixture.now, files: files)
    static let words = Clip(text: "report.pdf", kind: .text, copiedAt: PanelFixture.now)

    static func panel(
        insertion: PanelInsertion = .atCaret, gone: [String]? = nil
    ) -> PanelSnapshot {
        var snapshot = PanelFixture.panel([clip])
        snapshot.insertion = insertion
        if let gone { snapshot.missingFiles = [clip.id: gone] }
        return snapshot
    }

    @Test("Return at a caret pastes the files, not their names")
    func returnPastes() {
        let outcome = Self.panel().applying(.return).outcome

        #expect(outcome == .insertFiles(Self.clip))
        #expect(outcome.effect == .placeFiles(Self.clip, .paste))
    }

    @Test("⌘-Return pastes the files too, since there is no formatting to leave behind")
    func plainReturnPastes() {
        #expect(Self.panel().applying(.returnPlain).outcome == .insertFiles(Self.clip))
    }

    @Test(
        "Return while the panel can only copy puts the files on the clipboard",
        arguments: PanelInsertionObstacle.allCases)
    func copyOnly(_ obstacle: PanelInsertionObstacle) {
        let effect = Self.panel(insertion: .clipboardOnly(obstacle)).applying(.return).outcome.effect

        guard case .placeFiles(let clip, .copyAndSay(let notice)) = effect else {
            Issue.record("did not copy the files: \(String(describing: effect))")
            return
        }
        #expect(clip == Self.clip)
        #expect(notice.message == obstacle.copiedNotice.message)
    }

    @Test("the row's Copy puts the files on the clipboard and closes")
    func rowCopy() {
        #expect(Self.panel().copying(Self.clip.id).outcome.effect == .placeFiles(Self.clip, .copy))
    }

    @Test("one missing file refuses Return, names it and leaves the panel up")
    func returnRefusedForOne() {
        let outcome = Self.panel(gone: ["notes.txt"]).applying(.return).outcome

        #expect(outcome == .filesMissing(["notes.txt"]))
        guard case .say(let notice) = outcome.effect else {
            Issue.record("a missing file did not say so")
            return
        }
        #expect(notice.message == "notes.txt is no longer on this Mac")
        #expect(PanelNotice.filesMissing(["notes.txt"]).message == "notes.txt is no longer on this Mac")
    }

    @Test("several missing files are counted and named in one sentence")
    func severalNamed() {
        #expect(
            PanelNotice.filesMissing(["a.txt", "b.txt"]).message
                == "2 files are no longer on this Mac: a.txt, b.txt")
    }

    @Test("a missing file refuses the row's Copy and a click as well")
    func copyAndClickRefused() {
        let panel = Self.panel(gone: ["report.pdf"])

        #expect(panel.copying(Self.clip.id).outcome == .filesMissing(["report.pdf"]))
        #expect(panel.choosing(Self.clip.id).outcome == .filesMissing(["report.pdf"]))
    }

    @Test("a missing file refuses the copy-only path too")
    func copyOnlyRefused() {
        let panel = Self.panel(insertion: .clipboardOnly(.accessibilityNotGranted), gone: ["report.pdf"])

        #expect(panel.applying(.return).outcome == .filesMissing(["report.pdf"]))
    }

    @Test("plain text that names a file is still plain text")
    func textIsUnchanged() {
        let panel = PanelFixture.panel([Self.words])

        #expect(panel.applying(.return).outcome == .insert(Self.words))
        #expect(
            panel.copying(Self.words.id).outcome.effect
                == .closeAndCopy("report.pdf", richText: nil, used: Self.words.id))
    }

    @Test("the row names every file for VoiceOver and says nothing extra while all are there")
    func rowNamesFiles() {
        let row = PanelPresenter.present(Self.panel()).rows[0]

        #expect(row.fileNames == ["report.pdf", "notes.txt"])
        #expect(!row.isFileMissing)
        #expect(row.measurements == nil)
    }

    @Test("the row of a clip with a missing file says which, and stays in the list")
    func rowSaysWhichIsGone() {
        let presentation = PanelPresenter.present(Self.panel(gone: ["notes.txt"]))
        let row = presentation.rows[0]

        #expect(row.isFileMissing)
        #expect(row.measurements == "notes.txt is no longer on this Mac")
        #expect(presentation.rows.count == 1)
    }

    @Test("a file row offers no action that would change its words or call it a secret")
    func noTextActions() {
        let titles = PanelPresenter.present(Self.panel()).rows[0].actions.map(\.title)

        #expect(titles.contains("Insert"))
        #expect(titles.contains("Copy"))
        #expect(!titles.contains("Edit"))
        #expect(!titles.contains("Make a note"))
        #expect(!titles.contains("Treat as secret"))
    }

    @Test("a refused paste of files says they may be on the clipboard, and a copy says copied")
    func reports() throws {
        #expect(PanelPasteReport.after(.filesRefused) == PanelPasteReport.copied)
        #expect(PanelPasteReport.after(.copied(.files)) == PanelPasteReport.copied)
    }
}
