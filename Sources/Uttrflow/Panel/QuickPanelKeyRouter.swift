// Routes the quick panel's keystrokes and intents to the controller.

import AppKit
import SwiftUI
import UttrflowClipboard
import UttrflowUX

extension QuickPanelView {
    func send(_ key: PanelKey) -> KeyPress.Result {
        // SwiftUI runs these before the field editor, so a composing input method would never see the key.
        guard PanelComposition.panelMayTake(key, whileComposing: isComposing) else { return .ignored }
        relayKey(key)
        return .handled
    }

    /// Whether the field editor holds marked text, which is the one thing a key handler cannot read from the key.
    @MainActor var isComposing: Bool { compositionStatus?() ?? QuickPanel.isComposing(in: NSApp.keyWindow) }

    /// One handler for the chords and the long moves; two `onKeyPress(phases:)` on one view do not compose.
    func keyPress(_ press: KeyPress) -> KeyPress.Result {
        keyPress(key: press.key, characters: press.characters, modifiers: press.modifiers)
    }

    func keyPress(key: KeyEquivalent, characters: String, modifiers: EventModifiers) -> KeyPress.Result {
        let jumped = jumpKey(key: key, modifiers: modifiers)
        guard jumped != .handled else { return jumped }
        let decision = PanelKeyHandling.decision(
            characters: characters,
            commandHeld: modifiers.contains(.command),
            shiftHeld: modifiers.contains(.shift),
            isReturn: key == .return,
            isEscape: key == .escape,
            rowMenuOpen: rowMenu.rowID != nil,
            presentation: presentation)
        guard PanelComposition.panelMayTake(decision, whileComposing: isComposing) else { return .ignored }
        switch decision {
        case .key(let key), .keyAfterClosingMenu(let key):
            return send(key)
        case .intent(let intent):
            perform(intent)
            return .handled
        case .closeMenu:
            return send(.escape)
        case .ignore:
            return .ignored
        }
    }

    /// The long moves through the list, which ↑↓ would take a thousand presses to make.
    func jumpKey(_ press: KeyPress) -> KeyPress.Result {
        jumpKey(key: press.key, modifiers: press.modifiers)
    }

    func jumpKey(key: KeyEquivalent, modifiers: EventModifiers) -> KeyPress.Result {
        guard !modifiers.contains(.command) else { return .ignored }
        switch key {
        case .pageUp: return send(.jump(.pageUp))
        case .pageDown: return send(.jump(.pageDown))
        case .home: return send(.jump(.top))
        case .end: return send(.jump(.bottom))
        default: return .ignored
        }
    }

    /// Sends a key to the controller, letting esc close an open menu before it closes the panel.
    func relayKey(_ key: PanelKey) {
        switch PanelKeyHandling.relayDecision(
            for: key, rowMenuOpen: rowMenu.rowID != nil, query: query,
            hasSheet: presentation.sheet != nil)
        {
        case .closeMenu:
            rowMenu.handle(.windowResignedKey)
        case .key(let key), .keyAfterClosingMenu(let key):
            rowMenu.handle(.windowResignedKey)
            // The field follows a cleared search without relaying it a second time.
            if key == .clearSearch {
                isSyncingQuery = true
                query = ""
                isSyncingQuery = false
            }
            onKey(key)
        case .intent, .ignore:
            break
        }
    }

    func perform(_ intent: PanelIntent) {
        // Anything the snapshot can answer goes through `intent.key`, so button and keystroke share a path.
        if let key = intent.key {
            relayKey(key)
            return
        }
        onIntent(intent)
    }
}
