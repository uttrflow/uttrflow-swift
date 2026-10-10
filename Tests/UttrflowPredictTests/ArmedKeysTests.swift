import Testing
import UttrflowCore

@testable import UttrflowPredict

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

    @Test("Option only claims the strokes that use it, and a bare arrow claims no slot at all.")
    func optionClaimsItsStrokes() {
        #expect(ArmedKeys.slot(of: KeyStroke(.downArrow, modifiers: .option)) == .optionDownArrow)
        #expect(ArmedKeys.slot(of: KeyStroke(.upArrow, modifiers: .option)) == .optionUpArrow)
        #expect(ArmedKeys.slot(of: KeyStroke(.downArrow)).isEmpty)
        #expect(ArmedKeys.slot(of: KeyStroke(.upArrow)).isEmpty)
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
