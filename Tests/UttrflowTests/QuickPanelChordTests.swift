// Tests that the quick panel takes its row chords ahead of the main menu, so ⌘M moves a clip.

import AppKit
import Testing
import UttrflowUX

private import Carbon

@testable import Uttrflow

/// A view that records the keys the window hands it.
private final class KeyRecorder: NSView {
    var keys: [String] = []
    override var acceptsFirstResponder: Bool { true }
    override func keyDown(with event: NSEvent) { keys.append(event.charactersIgnoringModifiers ?? "") }
}

/// A key-down for `characters` at `keyCode` with `modifiers` held, addressed to `window`.
@MainActor
private func key(
    _ characters: String, _ modifiers: NSEvent.ModifierFlags,
    keyCode: UInt16? = nil, in window: NSWindow? = nil
) throws -> NSEvent {
    let code = keyCode ?? characters.first.flatMap { PanelChord($0).keyCode } ?? 0
    return try #require(
        NSEvent.keyEvent(
            with: .keyDown, location: .zero, modifierFlags: modifiers, timestamp: 0,
            windowNumber: window?.windowNumber ?? 0, context: nil, characters: characters,
            charactersIgnoringModifiers: characters, isARepeat: false, keyCode: code))
}

/// Returns an installed Unicode keyboard table by its Text Input Source identifier.
@MainActor
private func keyboardLayout(_ id: String) throws -> Data {
    let filter = [kTISPropertyInputSourceID as String: id] as CFDictionary
    let list = try #require(
        TISCreateInputSourceList(filter, true)?.takeRetainedValue() as? [TISInputSource],
        "no input source list for \(id)")
    let source = try #require(list.first, "\(id) is not installed")
    let property = try #require(
        TISGetInputSourceProperty(source, kTISPropertyUnicodeKeyLayoutData),
        "\(id) has no Unicode layout table")
    return Unmanaged<CFData>.fromOpaque(property).takeUnretainedValue() as Data
}

/// Makes the key event that a layout uses to type one labelled chord character.
@MainActor
private func layoutKey(_ chord: PanelChord, in id: String) throws -> NSEvent {
    if chord.character == "\u{7F}" { return try key("\u{7F}", [.command, .shift], keyCode: 51) }
    let data = try keyboardLayout(id)
    let modifiers =
        UInt32((cmdKey >> 8) & 0xFF)
        | (chord.isShifted ? UInt32((shiftKey >> 8) & 0xFF) : 0)
    let translated: (UInt16, String)? = data.withUnsafeBytes { raw in
        guard let layout = raw.bindMemory(to: UCKeyboardLayout.self).baseAddress else { return nil }
        for code in UInt16(0)...UInt16(127) {
            var deadKeyState: UInt32 = 0
            var output = [UniChar](repeating: 0, count: 4)
            var length = 0
            let status = UCKeyTranslate(
                layout, code, UInt16(kUCKeyActionDown), modifiers, UInt32(LMGetKbdType()),
                UInt32(kUCKeyTranslateNoDeadKeysBit), &deadKeyState, output.count, &length, &output)
            guard status == noErr, length == 1, let scalar = UnicodeScalar(output[0]) else { continue }
            let produced = String(scalar)
            guard produced.lowercased().first == chord.character else { continue }
            return (code, produced)
        }
        return nil
    }
    let (code, produced) = try #require(translated, "\(id) cannot produce \(chord.label)")
    let flags: NSEvent.ModifierFlags = chord.isShifted ? [.command, .shift] : .command
    return try key(produced, flags, keyCode: code)
}

@MainActor
@Suite("The quick panel's row chords")
struct QuickPanelChordTests {
    @Test("every row chord is recognised, with ⇧ where the chord takes it")
    func recognisesRowChords() throws {
        let examples: [(PanelRowAction, String, UInt16)] = [
            (.reveal, "к", 15), (.copy, "с", 8), (.pin, "з", 35),
            (.alias, "т", 45), (.move, "ь", 46), (.format, "а", 3),
            (.reindent, "ш", 34), (.makeNote, "е", 17), (.secrecy, "ы", 1), (.delete, "\u{7F}", 51),
        ]
        for (action, producedCharacter, code) in examples {
            let event = try key(
                producedCharacter, action.chord.isShifted ? [.command, .shift] : .command,
                keyCode: code)
            #expect(QuickPanel.rowChord(event) == action.chord, Comment(rawValue: action.chord.label))
        }
    }

    @Test("Dvorak produced letters win over their US key positions for row chords and undo")
    func dvorakUsesProducedLetters() throws {
        try assertLayoutUsesProducedLetters("com.apple.keylayout.Dvorak")
    }

    @Test("QWERTZ produced letters win over their US key positions for row chords and undo")
    func qwertzUsesProducedLetters() throws {
        try assertLayoutUsesProducedLetters("com.apple.keylayout.German")
    }

    @Test("a Latin letter never falls back to the Backspace position and deletes a row")
    func producedLetterDoesNotFallBackToDelete() throws {
        let event = try key("a", [.command, .shift], keyCode: 51)
        #expect(QuickPanel.rowChord(event) == nil)
    }

    @Test("a layout without Latin output uses the physical position for row chords and undo")
    func cyrillicFallsBackToPhysicalPosition() throws {
        for action in PanelRowAction.allCases {
            let code = try #require(action.chord.keyCode)
            let flags: NSEvent.ModifierFlags = action.chord.isShifted ? [.command, .shift] : .command
            let event = try key("я", flags, keyCode: code)
            #expect(QuickPanel.rowChord(event) == action.chord, Comment(rawValue: action.chord.label))
        }
        let undo = try key("я", .command, keyCode: PanelChord("z").keyCode)
        #expect(QuickPanel.claimsUndo(undo, offersRestore: true, fieldCanUndo: false))
    }

    @Test("keys that are not row chords are left to the menu and the field")
    func leavesOtherKeysAlone() throws {
        #expect(!QuickPanel.isRowChord(try key("ь", [], keyCode: 46)))
        #expect(!QuickPanel.isRowChord(try key("w", .command)))
        #expect(!QuickPanel.isRowChord(try key("я", .command, keyCode: 6)))
        #expect(!QuickPanel.isRowChord(try key("с", .command, keyCode: 8)))
        #expect(!QuickPanel.isRowChord(try key("ь", [.command, .option], keyCode: 46)))
        #expect(!QuickPanel.isRowChord(try key("ь", [.command, .control], keyCode: 46)))
    }

    /// Window ▸ Minimise is ⌘M, and the menu swallows it even where it is disabled.
    @Test("Move's chord is one the Window menu also binds")
    func moveSharesMinimiseKey() throws {
        let minimise = try #require(MainMenu.window.items.first { $0.title == "Minimise" })
        #expect(minimise.keyEquivalent == String(PanelRowAction.move.chord.character))
        #expect(minimise.keyEquivalentModifierMask == .command)
        #expect(!PanelRowAction.move.chord.isShifted)
    }

    @Test("a Cyrillic-produced physical ⌘M reaches the row action before the menu")
    func commandMReachesThePanel() throws {
        let panel = QuickPanel(
            contentRect: CGRect(x: 0, y: 0, width: 200, height: 100),
            styleMask: [.nonactivatingPanel], backing: .buffered, defer: true)
        let recorder = KeyRecorder()
        panel.contentView = recorder
        panel.makeFirstResponder(recorder)
        var received: PanelChord?
        panel.onRowChord = {
            received = $0
            return true
        }

        #expect(panel.performKeyEquivalent(with: try key("ь", .command, keyCode: 46, in: panel)))
        #expect(received == PanelRowAction.move.chord)
        #expect(recorder.keys.isEmpty)
    }

    @Test("a key that is not a row chord is not claimed")
    func otherKeysAreNotClaimed() throws {
        let panel = QuickPanel(
            contentRect: CGRect(x: 0, y: 0, width: 200, height: 100),
            styleMask: [.nonactivatingPanel], backing: .buffered, defer: true)
        let recorder = KeyRecorder()
        panel.contentView = recorder
        panel.makeFirstResponder(recorder)

        #expect(!panel.performKeyEquivalent(with: try key("w", .command, in: panel)))
        #expect(recorder.keys.isEmpty)
    }

    @Test("⌘Z restores a clip while the offer shows, and otherwise only when the field has no typing to undo")
    func undoGoesToTheOfferThenTheField() throws {
        let undo = try key("я", .command, keyCode: 6)

        #expect(QuickPanel.claimsUndo(undo, offersRestore: true, fieldCanUndo: true))
        #expect(QuickPanel.claimsUndo(undo, offersRestore: true, fieldCanUndo: false))
        #expect(QuickPanel.claimsUndo(undo, offersRestore: false, fieldCanUndo: false))
        #expect(!QuickPanel.claimsUndo(undo, offersRestore: false, fieldCanUndo: true))
    }

    @Test("Redo and other chords are never taken as the restore")
    func redoIsLeftAlone() throws {
        #expect(
            !QuickPanel.claimsUndo(
                try key("Я", [.command, .shift], keyCode: 6),
                offersRestore: true, fieldCanUndo: false))
        #expect(
            !QuickPanel.claimsUndo(
                try key("я", [.command, .option], keyCode: 6),
                offersRestore: true, fieldCanUndo: false))
        #expect(
            !QuickPanel.claimsUndo(try key("я", [], keyCode: 6), offersRestore: true, fieldCanUndo: false))
        #expect(
            !QuickPanel.claimsUndo(
                try key("ч", .command, keyCode: 7), offersRestore: true, fieldCanUndo: false))
    }

    @Test("a Cyrillic-produced physical ⌘Z restores ahead of Edit › Undo")
    func commandZReachesThePanel() throws {
        let panel = QuickPanel(
            contentRect: CGRect(x: 0, y: 0, width: 200, height: 100),
            styleMask: [.nonactivatingPanel], backing: .buffered, defer: true)
        let recorder = KeyRecorder()
        panel.contentView = recorder
        panel.makeFirstResponder(recorder)
        panel.offersRestore = true
        var restored = false
        panel.onUndo = { restored = true }

        #expect(panel.performKeyEquivalent(with: try key("я", .command, keyCode: 6, in: panel)))
        #expect(restored)
        #expect(recorder.keys.isEmpty)
    }

    /// A row chord the controller declines must not be claimed by the panel, so the menu or the field sees it.
    @Test("a row chord the controller declines is not claimed")
    func declinedRowChordIsNotClaimed() throws {
        let panel = QuickPanel(
            contentRect: CGRect(x: 0, y: 0, width: 200, height: 100),
            styleMask: [.nonactivatingPanel], backing: .buffered, defer: true)
        let recorder = KeyRecorder()
        panel.contentView = recorder
        panel.makeFirstResponder(recorder)
        panel.onRowChord = { _ in false }

        #expect(!panel.performKeyEquivalent(with: try key("ь", .command, keyCode: 46, in: panel)))
    }

    /// A row chord the controller handles claims the key and the field never sees it.
    @Test("a row chord the controller handles is claimed and the field does not see it")
    func handledRowChordIsClaimed() throws {
        let panel = QuickPanel(
            contentRect: CGRect(x: 0, y: 0, width: 200, height: 100),
            styleMask: [.nonactivatingPanel], backing: .buffered, defer: true)
        let recorder = KeyRecorder()
        panel.contentView = recorder
        panel.makeFirstResponder(recorder)
        var received: PanelChord?
        panel.onRowChord = {
            received = $0
            return true
        }

        #expect(panel.performKeyEquivalent(with: try key("ь", .command, keyCode: 46, in: panel)))
        #expect(received == PanelRowAction.move.chord)
        #expect(recorder.keys.isEmpty)
    }

    /// A composing input method holds the chord's key for its candidate, so the row chord must not act. See `PanelComposition`.
    @Test("a row chord is passed on, not acted on, while the field editor holds marked text")
    func composingPassesRowChordOn() throws {
        let panel = QuickPanel(
            contentRect: CGRect(x: 0, y: 0, width: 200, height: 100),
            styleMask: [.nonactivatingPanel], backing: .buffered, defer: true)
        let field = NSTextView(frame: NSRect(x: 0, y: 0, width: 200, height: 100))
        panel.contentView = field
        panel.makeFirstResponder(field)
        field.setMarkedText(
            "かな", selectedRange: NSRange(location: 2, length: 0),
            replacementRange: NSRange(location: NSNotFound, length: 0))
        var received: PanelChord?
        panel.onRowChord = {
            received = $0
            return true
        }

        #expect(QuickPanel.isComposing(in: panel))
        #expect(!panel.performKeyEquivalent(with: try key("ь", .command, keyCode: 46, in: panel)))
        #expect(received == nil)
    }

    /// A row chord with no selected row finds no intent, so the controller passes the chord on, not consumes it.
    @Test("a row chord with no selected row is passed on, not consumed")
    func chordWithNoSelectedRowPassesOn() throws {
        let controller = QuickPanelController()
        var fired: [PanelIntent] = []
        controller.onIntent = { intent, _ in fired.append(intent) }

        // No selected row; the only row's action has no shortcut, so the chord matches no intent.
        let clip = UUID()
        let row = PanelRow(
            id: clip, summary: "a clip", kind: .text, symbolName: "doc", when: "just now",
            alias: nil, category: nil, isPinned: false, isMasked: false, isSelected: false,
            matched: nil, isMonospaced: false, actions: [])
        let presentation = PanelPresentation(
            rows: [row], filters: [], categories: [], query: "",
            searchPlaceholder: PanelPresenter.searchPlaceholder,
            emptyState: nil, hint: "")
        controller.update(presentation)

        let panel = try #require(
            Mirror(reflecting: controller).descendant("panel") as? QuickPanel)
        #expect(!panel.performKeyEquivalent(with: try key("ь", .command, keyCode: 46, in: panel)))
        #expect(fired.isEmpty)
    }

    private func assertLayoutUsesProducedLetters(_ layout: String) throws {
        for action in PanelRowAction.allCases {
            let event = try layoutKey(action.chord, in: layout)
            #expect(QuickPanel.rowChord(event) == action.chord, "\(layout): \(action.chord.label)")
        }
        let undo = try layoutKey(PanelChord("z"), in: layout)
        #expect(
            QuickPanel.claimsUndo(undo, offersRestore: true, fieldCanUndo: false),
            "\(layout): undo")
    }
}
