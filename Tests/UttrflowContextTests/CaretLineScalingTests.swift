import Foundation
import Testing
import UttrflowPredict

@testable import UttrflowContext

@Suite("Reading the caret's line costs a bounded stretch, however long the line")
struct CaretLineScalingTests {
    /// A field holding one line, caret at its end, as Accessibility bridges it from an `NSString`.
    private static func snapshot(
        _ value: String, in bundleIdentifier: String = "com.example.editor"
    ) -> FocusedFieldSnapshot {
        let bridged = NSString(string: value) as String
        return FocusedFieldSnapshot(
            bundleIdentifier: bundleIdentifier, applicationName: "Editor", role: "AXTextArea", value: bridged,
            selection: NSRange(location: bridged.utf16.count, length: 0))
    }

    /// The snapshot and how many characters reading its line and what precedes it visited.
    private static func charactersRead(_ value: String) -> (FocusedFieldSnapshot, Int) {
        let tally = CharacterTally()
        let snapshot = FocusedFieldSnapshot.$tally.withValue(tally) {
            let snapshot = Self.snapshot(value)
            _ = snapshot.preceding(maxLength: 400)
            return snapshot
        }
        return (snapshot, tally.count)
    }

    @Test(
        "A single line of a million units is refused as too long after reading only the limit.",
        arguments: ["a", "न"])
    func megabyteLinesCostTheLimit(letter: String) {
        let value = String(repeating: letter, count: 1_000_000 / letter.utf16.count)
        let (snapshot, read) = Self.charactersRead(value)
        #expect(read <= 2 * FocusedFieldSnapshot.lineReadLimit)
        #expect(snapshot.isLineCut)
        #expect(snapshot.learnableLine.isEmpty)
        #expect(snapshot.preceding(maxLength: 400) == nil)
        var session = SuggestionSession()
        let surface = Surface(bundleIdentifier: "com.example.editor", role: "AXTextArea")
        let turn = session.turn(in: surface, at: PredictionContext(typed: snapshot.currentLine))
        guard case .settled(let update) = turn.step else {
            Issue.record("a cut line was asked about")
            return
        }
        #expect(update == .quiet(because: .lineTooLong))
    }

    @Test("A long document of short lines reads only the caret's own line.")
    func shortLinesCostTheirLength() {
        let value = String(repeating: "earlier text\n", count: 50_000) + "git c"
        let (snapshot, read) = Self.charactersRead(value)
        #expect(snapshot.currentLine == "git c")
        #expect(!snapshot.isLineCut)
        #expect(snapshot.learnableLine == "git c")
        #expect(snapshot.holdsNewline)
        #expect(read < 50)
    }

    @Test("A line longer than any completion but inside the limit is read whole, prompt and indentation off.")
    func linesInsideTheLimitAreWhole() {
        let long = String(repeating: "b", count: SuggestionSession.maximumTypedLength + 40)
        let indented = Self.snapshot("first\n    " + long)
        #expect(indented.currentLine == long)
        #expect(!indented.isLineCut)
        #expect(indented.preceding(maxLength: 400) == "first")

        let prompt = String(repeating: "p", count: 300) + "$ "
        let terminal = Self.snapshot(prompt + "git c", in: "com.apple.Terminal")
        #expect(terminal.currentLine == "git c")
        #expect(!terminal.isLineCut)
    }

    @Test("A line one character past the limit is cut, and the cut is never shorter than the limit.")
    func theLimitIsExact() {
        let limit = FocusedFieldSnapshot.lineReadLimit
        let inside = Self.snapshot(String(repeating: "c", count: limit))
        let past = Self.snapshot(String(repeating: "c", count: limit + 1))
        #expect(!inside.isLineCut)
        #expect(inside.currentLine.count == limit)
        #expect(past.isLineCut)
        #expect(past.currentLine.count == limit)
    }

    @Test("Whether a value holds a newline is read from its units, for every kind of newline.")
    func newlinesAreFoundInUnits() {
        for newline in ["\n", "\r", "\r\n", "\u{0B}", "\u{0C}", "\u{85}", "\u{2028}", "\u{2029}"] {
            #expect(Self.snapshot("one" + newline + "two").holdsNewline, "\(newline.debugDescription)")
        }
        #expect(!Self.snapshot("one two").holdsNewline)
        #expect(
            !FocusedFieldSnapshot(
                bundleIdentifier: "com.example.editor", applicationName: "Editor", role: "AXTextArea"
            )
            .holdsNewline)
    }
}
