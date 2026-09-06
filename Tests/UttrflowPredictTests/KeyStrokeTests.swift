import Testing

@testable import UttrflowPredict

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

@Suite("The slots the tap arms")
struct ArmedKeysTests {
    @Test("Every slot the tap knows about maps back to the keystroke that fills it.")
    func everySlotRoundTrips() {
        for entry in ArmedKeys.slots {
            #expect(ArmedKeys.slot(of: entry.stroke) == entry.slot)
            #expect(ArmedKeys.stroke(of: entry.slot) == entry.stroke)
        }
    }

    @Test("Each slot is its own bit, so arming one never arms another.")
    func slotsDoNotOverlap() {
        let combined = ArmedKeys.slots.reduce(into: ArmedKeys()) { $0.insert($1.slot) }
        #expect(combined.rawValue.nonzeroBitCount == ArmedKeys.slots.count)
    }

    @Test("A key this feature has no opinion about occupies no slot at all.")
    func unclaimedKeysHaveNoSlot() {
        #expect(ArmedKeys.slot(of: KeyStroke(.other)).isEmpty)
        #expect(ArmedKeys.slot(of: KeyStroke(.other, modifiers: .option)).isEmpty)
    }

    @Test("A stroke carrying Command or Control is never ours, whatever the key is.")
    func commandAndControlAreNeverOurs() {
        #expect(ArmedKeys.slot(of: KeyStroke(.tab, modifiers: .command)).isEmpty)
        #expect(ArmedKeys.slot(of: KeyStroke(.return, modifiers: .control)).isEmpty)
        #expect(ArmedKeys.slot(of: KeyStroke(.escape, modifiers: [.option, .command])).isEmpty)
    }

    @Test("Shift-Tab is the application's own back-tab and occupies no slot.")
    func backTabIsNotOurs() {
        #expect(ArmedKeys.slot(of: KeyStroke(.tab, modifiers: .shift)).isEmpty)
    }

    @Test("Option only claims the two strokes that use it.")
    func optionClaimsTwoStrokes() {
        #expect(ArmedKeys.slot(of: KeyStroke(.downArrow, modifiers: .option)).isEmpty)
        #expect(ArmedKeys.slot(of: KeyStroke(.return, modifiers: .option)).isEmpty)
        #expect(ArmedKeys.slot(of: KeyStroke(.rightArrow, modifiers: .option)).isEmpty)
    }

    @Test("A raw value that stands for no single slot names no keystroke.")
    func unknownSlotsNameNothing() {
        #expect(ArmedKeys.stroke(of: ArmedKeys(rawValue: 0)) == nil)
        #expect(ArmedKeys.stroke(of: [.tab, .escape]) == nil, "two slots at once is not one key")
        #expect(ArmedKeys.stroke(of: ArmedKeys(rawValue: 1 << 20)) == nil)
    }
}
