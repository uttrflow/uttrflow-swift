// Tests which keys count as typing a ghost's next letters, which is the only kind that keeps it on screen.

import AppKit
import UttrflowPredict
import Testing

@testable import Uttrflow

@Suite("The text a key types, for typing through a ghost")
struct SuggestionTypedTextTests {
    @Test("a letter, a shifted letter and a space are text")
    func plainKeysAreText() {
        #expect(SuggestionCoordinator.typedText(characters: "a", modifiers: []) == "a")
        #expect(SuggestionCoordinator.typedText(characters: "A", modifiers: .shift) == "A")
        #expect(SuggestionCoordinator.typedText(characters: " ", modifiers: []) == " ")
    }

    @Test("a shortcut types nothing, whatever letter it carries")
    func shortcutsAreNotText() {
        #expect(SuggestionCoordinator.typedText(characters: "a", modifiers: .command) == nil)
        #expect(SuggestionCoordinator.typedText(characters: "a", modifiers: .control) == nil)
        #expect(SuggestionCoordinator.typedText(characters: "å", modifiers: .option) == nil)
    }

    @Test("Tab, Return, Delete, an arrow and a dead key type nothing")
    func controlKeysAreNotText() {
        #expect(SuggestionCoordinator.typedText(characters: "\t", modifiers: []) == nil)
        #expect(SuggestionCoordinator.typedText(characters: "\r", modifiers: []) == nil)
        #expect(SuggestionCoordinator.typedText(characters: "\u{7F}", modifiers: []) == nil)
        #expect(SuggestionCoordinator.typedText(characters: "\u{F701}", modifiers: .function) == nil)
        #expect(SuggestionCoordinator.typedText(characters: "\u{F701}", modifiers: []) == nil)
        #expect(SuggestionCoordinator.typedText(characters: "", modifiers: []) == nil)
        #expect(SuggestionCoordinator.typedText(characters: nil, modifiers: []) == nil)
    }

    @Test("Only fresh text keys advance the prose fluency clock")
    func fluencyClockIgnoresNavigationShortcutsAndRepeats() {
        let start = Date(timeIntervalSince1970: 1_800_000_000)
        let typing = SuggestionCoordinator.fluencyTimestamp(
            previous: .distantPast, typing: Self.typedText("a"), isARepeat: false, at: start)
        #expect(typing == start)
        #expect(Self.fluencyReason(since: typing, at: start.addingTimeInterval(0.1)) == .writingFluently)

        let arrow = SuggestionCoordinator.fluencyTimestamp(
            previous: typing, typing: Self.typedText("\u{F702}"), isARepeat: false,
            at: start.addingTimeInterval(0.1))
        let shortcut = SuggestionCoordinator.fluencyTimestamp(
            previous: arrow, typing: Self.typedText("c", modifiers: .command), isARepeat: false,
            at: start.addingTimeInterval(0.2))
        let heldKey = SuggestionCoordinator.fluencyTimestamp(
            previous: shortcut, typing: Self.typedText("a"), isARepeat: true,
            at: start.addingTimeInterval(0.3))

        #expect(arrow == typing)
        #expect(shortcut == typing)
        #expect(heldKey == typing)
        #expect(Self.fluencyReason(since: heldKey, at: start.addingTimeInterval(0.5)) == nil)
    }

    @Test("Navigation, shortcuts and autorepeat never start a prose fluency pause")
    func nonTypingKeysDoNotStartFluency() {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let arrow = SuggestionCoordinator.fluencyTimestamp(
            previous: .distantPast, typing: Self.typedText("\u{F702}"), isARepeat: false, at: now)
        let shortcut = SuggestionCoordinator.fluencyTimestamp(
            previous: .distantPast, typing: Self.typedText("c", modifiers: .command), isARepeat: false,
            at: now)
        let heldKey = SuggestionCoordinator.fluencyTimestamp(
            previous: .distantPast, typing: Self.typedText("a"), isARepeat: true, at: now)

        #expect(Self.fluencyReason(since: arrow, at: now) == nil)
        #expect(Self.fluencyReason(since: shortcut, at: now) == nil)
        #expect(Self.fluencyReason(since: heldKey, at: now) == nil)
    }

    private static func typedText(_ characters: String, modifiers: NSEvent.ModifierFlags = []) -> String? {
        SuggestionCoordinator.typedText(characters: characters, modifiers: modifiers)
    }

    private static func fluencyReason(since keystroke: Date, at moment: Date) -> Quieting.Reason? {
        let elapsed = Int(moment.timeIntervalSince(keystroke) * 1000)
        let context = PredictionContext(
            typed: "Thanks", isProse: true, millisecondsSinceKeystroke: elapsed)
        return Quieting.reason(context)
    }
}
