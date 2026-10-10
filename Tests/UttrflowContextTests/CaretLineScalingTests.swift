import Foundation
import Testing
import UttrflowCore
import UttrflowPredict

@testable import UttrflowContext

@Suite("Reading the caret's line costs a bounded stretch, however long the line")
struct CaretLineScalingTests {
    /// A field holding one line, caret at its end, as Accessibility bridges it from an `NSString`.
    private static func snapshot(
        _ value: String, in bundleIdentifier: String = "com.example.editor", role: String = "AXTextArea"
    ) -> FocusedFieldSnapshot {
        let bridged = NSString(string: value) as String
        return FocusedFieldSnapshot(
            bundleIdentifier: bundleIdentifier, applicationName: "Editor", role: role, value: bridged,
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
        // The line and what precedes it each read the limit, and a prose line looks back once more for a sentence start.
        #expect(read <= 2 * (FocusedFieldSnapshot.lineReadLimit + TypedLine.maximumLength))
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

    @Test("A line with text after the caret is never learned, however long the pause or wherever focus goes.")
    func aLineEditedInsideIsNotLearned() {
        let paragraph = "We moved the quarterly review to the last week of the month."
        let caret = (paragraph as NSString).range(of: "la").location + 2
        let inside = FocusedFieldSnapshot(
            bundleIdentifier: "com.example.editor", applicationName: "Editor", role: "AXTextArea",
            value: paragraph + "\nNext line", selection: NSRange(location: caret, length: 0))
        #expect(inside.currentLine == "We moved the quarterly review to the la")
        #expect(inside.hasTextAfterCaret)
        #expect(inside.learnableLine.isEmpty)
        let atEnd = FocusedFieldSnapshot(
            bundleIdentifier: "com.example.editor", applicationName: "Editor", role: "AXTextArea",
            value: paragraph + "  \nNext line", selection: NSRange(location: paragraph.utf16.count, length: 0)
        )
        #expect(!atEnd.hasTextAfterCaret)
        #expect(atEnd.learnableLine == paragraph)
        let unknown = FocusedFieldSnapshot(
            bundleIdentifier: "com.example.editor", applicationName: "Editor", role: "AXTextArea",
            value: paragraph, selection: nil)
        #expect(unknown.learnableLine == paragraph)
    }

    @Test("A long document of short lines reads only the caret's own line.")
    func shortLinesCostTheirLength() {
        let value = String(repeating: "earlier text\n", count: 50_000) + "git c"
        let (snapshot, read) = Self.charactersRead(value)
        #expect(snapshot.currentLine == "git c")
        #expect(!snapshot.isLineCut)
        #expect(snapshot.learnableLine == "git c")
        #expect(read < 50)
    }

    @Test("A line longer than any completion but inside the limit is read whole, prompt and indentation off.")
    func linesInsideTheLimitAreWhole() {
        let long = String(repeating: "b", count: TypedLine.maximumLength + 40)
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

    /// A paragraph of about 300 characters with no line break, as a mail body wraps it.
    private static let paragraph =
        "Thanks for sending the quarterly numbers over this morning. I read through the summary on the train "
        + "and the growth in the second region looks better than we expected. Before the review on Friday I "
        + "would like to go through the cost lines with you, so could we find half an hour on"

    @Test("A prose paragraph too long to complete whole is continued from its earliest sentence within reach")
    func aLongParagraphIsContinuedFromASentence() {
        #expect(Self.paragraph.count > TypedLine.maximumLength)
        let reading = Self.snapshot("Hi Sam,\n\n" + Self.paragraph)
        #expect(reading.currentLine.hasPrefix("I read through the summary"))
        #expect(reading.currentLine.hasSuffix("half an hour on"))
        #expect(reading.currentLine.count <= TypedLine.maximumLength)
        #expect(!reading.isLineCut)
        #expect(
            reading.preceding(maxLength: 400)
                == "Hi Sam,\n\nThanks for sending the quarterly numbers over this morning.")
        var session = SuggestionSession()
        let surface = Surface(bundleIdentifier: "com.example.editor", role: "AXTextArea")
        let turn = session.turn(in: surface, at: PredictionContext(typed: reading.currentLine))
        if case .settled(let update) = turn.step { #expect(update != .quiet(because: .lineTooLong)) }
    }

    @Test("A terminal, a one-line field, or prose with no sentence end in reach keeps the whole line")
    func otherLinesKeepTheirLength() {
        #expect(
            Self.snapshot(Self.paragraph, in: "com.apple.Terminal").currentLine.count
                > TypedLine.maximumLength)
        #expect(Self.snapshot(Self.paragraph, role: "AXTextField").currentLine == Self.paragraph)
        let runOn = String(repeating: "word ", count: 70) + "end"
        #expect(Self.snapshot("Done. " + runOn).currentLine == "Done. " + runOn)
    }

    @Test("A sentence start just before the caret, or one inside an ellipsis, is not where the line begins")
    func sentenceStartsNeedTypingAfterThem() {
        let lead = String(repeating: "x", count: 100)
        let filler = String(repeating: "and more ", count: 20)
        #expect(Self.snapshot(lead + " " + filler + "stop. ").currentLine.hasPrefix("xxx"))
        #expect(Self.snapshot(lead + " Well... " + filler + "on").currentLine.hasPrefix("xxx"))
        #expect(Self.snapshot(lead + " Yes!) " + filler + "on").currentLine.hasPrefix("and more"))
        #expect(Self.snapshot(lead + " Done.  " + filler + "on").currentLine.hasPrefix("and more"))
    }
}
