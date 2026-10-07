import Foundation
import Testing

@testable import UttrflowContext

/// One recorded terminal snapshot, where the caret stands in it, and what the dictation read must give.
struct TerminalFixture: CustomTestStringConvertible, Sendable {
    let file: String
    /// The caret's UTF-16 offset; the end of the screen where nil.
    let caret: Int?
    /// The shell input before the caret; nil where the read must give no edges.
    let preceding: String?
    let following: String

    var testDescription: String { file }
}

/// Replays the six terminal snapshots of `Docs/terminal-probe.md` through the field read and the terminal reading.
@Suite("Terminal fixture replay")
struct TerminalFixtureReplayTests {
    private static let directory = URL(filePath: #filePath).deletingLastPathComponent()
        .deletingLastPathComponent().appending(path: "Fixtures/AccessibilitySnapshots")

    static let fixtures: [TerminalFixture] = [
        TerminalFixture(
            file: "terminal-local-default-prompt.json", caret: nil, preceding: "git st", following: ""),
        TerminalFixture(
            file: "terminal-two-line-right-prompt.json", caret: 29, preceding: "make te",
            following: "                                   10:42:07"),
        TerminalFixture(
            file: "terminal-multiplexer-pane.json", caret: 39, preceding: "npm run li", following: ""),
        TerminalFixture(
            file: "terminal-remote-shell.json", caret: nil, preceding: "tail -n 5 app.l", following: ""),
        TerminalFixture(file: "terminal-full-screen-editor.json", caret: 5, preceding: nil, following: ""),
        TerminalFixture(file: "terminal-here-document.json", caret: nil, preceding: nil, following: ""),
    ]

    @Test(
        "gives the dictation read only the shell input, never scrollback, a prompt or a status line",
        arguments: fixtures)
    func replay(_ fixture: TerminalFixture) throws {
        let file = Self.directory.appending(path: fixture.file)
        let snapshot = try AccessibilitySnapshot.decode(Data(contentsOf: file))
        let tree = WindowReplayTree(window: snapshot.focused)
        let screen = try #require(snapshot.focused.attributes["AXValue"]?.fieldAnswer.string)
        let caret = fixture.caret ?? screen.utf16.count
        let names = FocusedFieldRead.names(of: snapshot.focused, in: tree)
        let read = FocusedFieldRead.text(
            of: snapshot.focused, in: tree, names: names, at: NSRange(location: caret, length: 0))
        let selection = read.selection.flatMap { Range($0) }
        let sides = CaretText.inTerminal(read.value, selection: selection, windowTitle: snapshot.windowTitle)
        guard let preceding = fixture.preceding else {
            #expect(sides == nil)
            return
        }
        #expect(sides == CaretText.Sides(preceding: preceding, following: fixture.following))
    }
}
