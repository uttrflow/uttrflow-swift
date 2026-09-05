import Testing

@testable import UttrflowContext
@testable import UttrflowCore

@Suite("CaretText")
struct CaretTextTests {
    @Test("splits the field at an empty selection")
    func splitsAtCaret() {
        let sides = CaretText.around("hello world", selection: 5..<5)
        #expect(sides == CaretText.Sides(preceding: "hello", following: " world"))
    }

    @Test("leaves the selected text out of both sides")
    func skipsSelection() {
        let sides = CaretText.around("hello brave world", selection: 6..<11)
        #expect(sides == CaretText.Sides(preceding: "hello ", following: " world"))
    }

    @Test("knows nothing when the field reports no value or no selection")
    func nothingWithoutBoth() {
        #expect(CaretText.around(nil, selection: 0..<0) == nil)
        #expect(CaretText.around("hello", selection: nil) == nil)
    }

    @Test("an empty field is an empty start, not nothing")
    func emptyField() {
        #expect(CaretText.around("", selection: 0..<0) == CaretText.Sides(preceding: "", following: ""))
    }

    @Test("clamps a selection the field reported past its own ends")
    func clamps() {
        #expect(
            CaretText.around("hello", selection: 9..<12)
                == CaretText.Sides(preceding: "hello", following: ""))
        #expect(
            CaretText.around("hello", selection: -3..<2)
                == CaretText.Sides(preceding: "", following: "llo"))
        #expect(
            CaretText.around("hello", selection: -3..<(-1))
                == CaretText.Sides(preceding: "", following: "hello"))
    }

    @Test("cuts each side to the limit the insertion point keeps")
    func limits() {
        let long = String(repeating: "a", count: 500) + "|" + String(repeating: "b", count: 500)
        let sides = CaretText.around(long, selection: 500..<501)
        #expect(sides?.preceding.count == InsertionPoint.precedingLimit)
        #expect(sides?.following.count == InsertionPoint.followingLimit)
        #expect(sides?.preceding.allSatisfy { $0 == "a" } == true)
        #expect(sides?.following.allSatisfy { $0 == "b" } == true)
    }

    @Test("counts the selection in UTF-16 units, the way Accessibility reports it")
    func utf16Offsets() {
        let text = "😀 hello"
        #expect(
            CaretText.around(text, selection: 2..<2) == CaretText.Sides(preceding: "😀", following: " hello"))
        #expect(CaretText.around(text, selection: 1..<1)?.following.hasSuffix(" hello") == true)
    }
}
