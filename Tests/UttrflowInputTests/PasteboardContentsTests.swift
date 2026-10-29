import AppKit
import Foundation
import Testing

@testable import UttrflowInput

@Suite("Pasteboard contents")
struct PasteboardContentsTests {
    @Test("a written snapshot reads back the same")
    func roundTrip() {
        let board = NSPasteboard(name: NSPasteboard.Name("uttrflow.test.\(UUID().uuidString)"))
        defer { board.releaseGlobally() }
        let snapshot = PasteboardSnapshot(items: [["public.utf8-plain-text": Data("kept".utf8)]])
        #expect(PasteboardContents.write(snapshot, to: board))
        #expect(PasteboardContents.capture(from: board) == snapshot)
    }

    @Test("an empty board captures as no items")
    func empty() {
        let board = NSPasteboard(name: NSPasteboard.Name("uttrflow.test.\(UUID().uuidString)"))
        defer { board.releaseGlobally() }
        board.clearContents()
        #expect(PasteboardContents.capture(from: board).items.isEmpty)
    }
}
