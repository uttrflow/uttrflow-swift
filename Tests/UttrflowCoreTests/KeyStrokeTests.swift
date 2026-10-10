import Testing

@testable import UttrflowCore

@Suite("Keystrokes as the window server reports them")
struct KeyStrokeTests {
    @Test(
        "Each key this feature cares about is recognised by its hardware code.",
        arguments: [
            (UInt16(48), Key.tab), (36, .return), (76, .return), (53, .escape),
            (124, .rightArrow), (125, .downArrow), (126, .upArrow),
        ])
    func keyCodesAreRecognised(keyCode: UInt16, key: Key) {
        #expect(Key(keyCode: keyCode) == key)
    }

    @Test("Every key this feature takes names the code that presses it again.")
    func keyCodesRoundTrip() {
        for key in Key.allCases where key != .other {
            #expect(key.keyCode.map(Key.init(keyCode:)) == key)
        }
        #expect(Key.other.keyCode == nil)
    }

    @Test("Every other key is one this feature has no opinion about.")
    func everythingElseIsOther() {
        #expect(Key(keyCode: 0) == .other)
        #expect(Key(keyCode: 123) == .other, "the left arrow is not one of ours")
        #expect(Key(keyCode: 49) == .other, "nor is the space bar")
    }

    @Test("A stroke can be built from a code and a set of modifiers at once.")
    func builtFromACode() {
        #expect(KeyStroke(keyCode: 48, modifiers: .option) == KeyStroke(.tab, modifiers: .option))
    }

    @Test("A stroke with no modifiers is not the same stroke as one with.")
    func modifiersCount() {
        #expect(KeyStroke(.tab) != KeyStroke(.tab, modifiers: .option))
    }
}
