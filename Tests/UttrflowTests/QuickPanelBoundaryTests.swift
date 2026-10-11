import AppKit
import SwiftUI
import Testing
import UttrflowUX

@testable import Uttrflow

@MainActor
@Suite("Private quick panel event boundaries")
struct QuickPanelBoundaryTests {
    private func panel(
        composing: Bool = false, onKey: @escaping (PanelKey) -> Void = { _ in },
        onIntent: @escaping (PanelIntent) -> Void = { _ in }
    ) -> QuickPanelView {
        QuickPanelView(
            presentation: PanelPresentation(
                rows: [], filters: [], categories: [], query: "", searchPlaceholder: "Search",
                emptyState: nil, hint: ""), onKey: onKey, onIntent: onIntent, compositionStatus: { composing }
        )
    }

    @Test("long moves route once and command-modified moves remain with the editor")
    func navigation() {
        var keys: [PanelKey] = []
        let view = panel(onKey: { keys.append($0) })
        for key: KeyEquivalent in [.pageUp, .pageDown, .home, .end] {
            #expect(view.jumpKey(key: key, modifiers: []) == .handled)
            #expect(view.jumpKey(key: key, modifiers: [.command]) == .ignored)
        }
        #expect(keys == [.jump(.pageUp), .jump(.pageDown), .jump(.top), .jump(.bottom)])
        #expect(view.jumpKey(key: "x", modifiers: []) == .ignored)
    }

    @Test("composition keeps Return and Escape with the input method")
    func composition() {
        var keys: [PanelKey] = []
        let view = panel(composing: true, onKey: { keys.append($0) })
        #expect(view.send(.escape) == .ignored)
        #expect(view.keyPress(key: .return, characters: "\r", modifiers: []) == .ignored)
        #expect(view.keyPress(key: .escape, characters: "", modifiers: []) == .ignored)
        #expect(keys.isEmpty)
    }

    @Test("plain Escape closes the panel and unbound characters stay in the search editor")
    func escapeAndSearch() {
        var keys: [PanelKey] = []
        let view = panel(onKey: { keys.append($0) })
        #expect(view.keyPress(key: .escape, characters: "", modifiers: []) == .handled)
        #expect(keys == [.escape])
        #expect(view.keyPress(key: "z", characters: "z", modifiers: []) == .ignored)
        view.relayKey(.clearSearch)
        #expect(keys.last == .clearSearch)
    }

    @Test("command undo reaches the app once while keyed row actions use the key route")
    func intents() {
        var keys: [PanelKey] = []
        var intents: [PanelIntent] = []
        let view = panel(onKey: { keys.append($0) }, onIntent: { intents.append($0) })
        #expect(view.keyPress(key: "z", characters: "z", modifiers: [.command]) == .handled)
        #expect(intents == [.undoDelete])
        let id = UUID()
        view.perform(.insert(id))
        #expect(keys == [.choose(id)])
        #expect(intents == [.undoDelete])
        #expect(view.keyPress(key: .return, characters: "\r", modifiers: []) == .handled)
        #expect(keys.last == .return)
        #expect(view.keyPress(key: .pageDown, characters: "", modifiers: []) == .handled)
        #expect(keys.last == .jump(.pageDown))
    }

    private func event(_ type: NSEvent.EventType, modifiers: NSEvent.ModifierFlags = []) throws -> NSEvent {
        try #require(
            NSEvent.mouseEvent(
                with: type, location: .zero, modifierFlags: modifiers, timestamp: 0, windowNumber: 0,
                context: nil, eventNumber: 0, clickCount: 1, pressure: 0))
    }

    @Test("only right and control clicks are claimed inside a row")
    func rightClickBoundary() throws {
        let parent = NSView(frame: NSRect(x: 0, y: 0, width: 100, height: 100))
        let catcher = RightClickWatch.Catcher(frame: parent.bounds)
        parent.addSubview(catcher)
        var clicks = 0
        catcher.clicked = { clicks += 1 }
        for type: NSEvent.EventType in [.rightMouseDown, .rightMouseUp, .rightMouseDragged] {
            let press = try event(type)
            catcher.currentEvent = { press }
            #expect(catcher.hitTest(NSPoint(x: 20, y: 20)) === catcher)
        }
        for type: NSEvent.EventType in [.leftMouseDown, .leftMouseUp] {
            let plain = try event(type)
            catcher.currentEvent = { plain }
            #expect(catcher.hitTest(NSPoint(x: 20, y: 20)) == nil)
            let control = try event(type, modifiers: [.control])
            catcher.currentEvent = { control }
            #expect(catcher.hitTest(NSPoint(x: 20, y: 20)) === catcher)
        }
        catcher.rightMouseDown(with: try event(.rightMouseDown))
        catcher.mouseDown(with: try event(.leftMouseDown, modifiers: [.control]))
        #expect(clicks == 2)
        catcher.currentEvent = { nil }
        #expect(catcher.hitTest(.zero) == nil)
        #expect(catcher.hitTest(NSPoint(x: 200, y: 200)) == nil)
        let moved = try event(.mouseMoved)
        catcher.currentEvent = { moved }
        #expect(catcher.hitTest(NSPoint(x: 20, y: 20)) == nil)
    }

    @Test("pointer tracking replaces old areas and passes every click through")
    func pointerBoundary() throws {
        let tracker = PointerWatch.Tracker(frame: NSRect(x: 0, y: 0, width: 80, height: 30))
        var changes: [Bool] = []
        tracker.changed = { changes.append($0) }
        tracker.updateTrackingAreas()
        tracker.updateTrackingAreas()
        #expect(tracker.trackingAreas.count == 1)
        let options = try #require(tracker.trackingAreas.first).options
        #expect(options.contains([.activeAlways, .inVisibleRect, .mouseEnteredAndExited]))
        tracker.mouseEntered(with: try event(.mouseMoved))
        tracker.mouseExited(with: try event(.mouseMoved))
        #expect(changes == [true, false])
        #expect(tracker.hitTest(NSPoint(x: 10, y: 10)) == nil)
    }
}
