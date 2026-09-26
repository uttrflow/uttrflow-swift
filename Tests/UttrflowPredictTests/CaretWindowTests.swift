import Foundation
import Testing

@testable import UttrflowPredict

/// A field's text read by UTF-16 range, counting how many units each read copies.
private final class RangedField: @unchecked Sendable {
    let text: String
    var unitsRead = 0
    var reads = 0

    init(_ text: String) { self.text = text }

    func read(_ range: Range<Int>) -> String? {
        guard range.lowerBound >= 0, range.upperBound <= text.utf16.count else { return nil }
        reads += 1
        unitsRead += range.count
        return (text as NSString).substring(with: NSRange(location: range.lowerBound, length: range.count))
    }
}

@Suite("Reading a bounded stretch of a field around its caret")
struct CaretWindowTests {
    @Test("reads a short field from its start, whole")
    func shortFieldFromStart() {
        let field = RangedField("Hello world")
        #expect(CaretWindow.before(11, characters: 96, ranged: field.read) == "Hello world")
    }

    @Test("reads a bounded window from a 1 MB field, ending in the text before the caret")
    func longFieldIsBounded() throws {
        let long = String(repeating: "a", count: 1_000_000) + "the end"
        let field = RangedField(long)
        let window = try #require(CaretWindow.before(long.utf16.count, characters: 96, ranged: field.read))
        #expect(window.hasSuffix(String(long.suffix(96))))
        #expect(window.count > 96)
        #expect(field.unitsRead < 1_000)
    }

    @Test("drops a character the range cut in half")
    func cutSurrogateIsDropped() throws {
        let text = String(repeating: "😀", count: 50)
        let field = RangedField(text)
        let window = try #require(CaretWindow.before(text.utf16.count, characters: 10, ranged: field.read))
        #expect(window.allSatisfy { $0 == "😀" })
        #expect(window.count >= 10)
    }

    @Test("asks for the whole value when the field will not read by range")
    func refusedRangeFallsBack() {
        #expect(CaretWindow.before(10, characters: 4, ranged: { _ in nil }) == nil)
        #expect(CaretWindow.before(-1, characters: 4, ranged: { _ in "" }) == nil)
        #expect(CaretWindow.before(10, characters: 4, ranged: { _ in "short" }) == nil)
    }

    @Test("asks for the whole value when the window holds too few whole characters")
    func tooFewCharactersFallsBack() {
        let text = String(repeating: "e\u{301}\u{301}\u{301}\u{301}\u{301}", count: 40)
        let field = RangedField(text)
        #expect(CaretWindow.before(text.utf16.count, characters: 10, ranged: field.read) == nil)
    }

    @Test("reads a bounded window after the selection, dropping a cut last character")
    func afterIsBounded() throws {
        let text = "start " + String(repeating: "b", count: 100_000)
        let field = RangedField(text)
        let window = try #require(
            CaretWindow.after(0, characters: 5, length: text.utf16.count, ranged: field.read))
        #expect(window.hasPrefix("start"))
        #expect(field.unitsRead < 100)
        #expect(CaretWindow.after(0, characters: 5, length: 3, ranged: RangedField("abc").read) == "abc")
        #expect(CaretWindow.after(4, characters: 5, length: 3, ranged: field.read) == nil)
        #expect(CaretWindow.after(0, characters: 5, length: 100, ranged: { _ in nil }) == nil)
        #expect(
            CaretWindow.after(
                0, characters: 5, length: 100,
                ranged: { String(repeating: "e\u{301}\u{301}\u{301}\u{301}\u{301}", count: $0.count / 6) })
                == nil)
    }

    @Test("reads only the start of a field for the mask check")
    func prefixIsBounded() {
        let field = RangedField(String(repeating: "•", count: 10_000))
        #expect(CaretWindow.prefix(length: 10_000, ranged: field.read)?.count == CaretWindow.maskPrefixUnits)
        #expect(CaretWindow.prefix(length: 3, ranged: RangedField("abc").read) == "abc")
        #expect(CaretWindow.prefix(length: nil, ranged: field.read) == nil)
        #expect(CaretWindow.prefix(length: 10, ranged: { _ in nil }) == nil)
    }
}
