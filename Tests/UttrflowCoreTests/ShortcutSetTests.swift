// Tests for holding several shortcuts, by what each one is for.

import Foundation
import Testing

@testable import UttrflowCore

/// Every shortcut as one value, which is what settings now stores.
@Suite("Holding every shortcut at once")
struct ShortcutSetTests {
    @Test("ships a dictation and a clipboard shortcut")
    func shipsBoth() {
        #expect(ShortcutSet.default.first(for: .dictate) == .optionSpace)
        #expect(ShortcutSet.default.first(for: .clipboard) == .shiftCommandV)
    }

    @Test("keeps every way into one action, in the order they were added")
    func severalWaysIn() {
        var set = ShortcutSet([.dictate: [.functionHold]])
        set.add(.optionSpace, to: .dictate)
        #expect(set.bindings(for: .dictate) == [.functionHold, .optionSpace])
        #expect(set.first(for: .dictate) == .functionHold)
    }

    @Test("ignores a way in it already answers to")
    func noDuplicates() {
        var set = ShortcutSet([.dictate: [.functionHold]])
        set.add(.functionHold, to: .dictate)
        #expect(set.bindings(for: .dictate) == [.functionHold])
    }

    @Test("refuses a binding nothing could ever deliver")
    func refusesUndeliverable() {
        // Option's key code carrying Command: a pair no keypress makes.
        var set = ShortcutSet([.dictate: [HotkeyBinding(keyCode: 58, modifiers: [.command])]])
        #expect(!set.isBound(.dictate))
        set.add(HotkeyBinding(keyCode: 57, modifiers: []), to: .dictate)
        #expect(!set.isBound(.dictate))
    }

    @Test("changing a row replaces that way in rather than adding one")
    func replaceInPlace() {
        var set = ShortcutSet([.dictate: [.functionHold, .optionSpace]])
        set.replace(at: 1, with: .shiftCommandV, for: .dictate)
        #expect(set.bindings(for: .dictate) == [.functionHold, .shiftCommandV])
    }

    @Test("changing a row an action does not have yet adds it")
    func replaceBeyondTheEndAdds() {
        var set = ShortcutSet()
        set.replace(at: 0, with: .functionHold, for: .dictate)
        #expect(set.bindings(for: .dictate) == [.functionHold])
    }

    @Test("an action may end up with no shortcut at all")
    func removingTheLastIsAllowed() {
        var set = ShortcutSet([.clipboard: [.shiftCommandV]])
        set.remove(at: 0, from: .clipboard)
        #expect(!set.isBound(.clipboard))
        #expect(set.first(for: .clipboard) == nil)
    }

    @Test("says which other action already answers to these keys")
    func namesTheClash() {
        let set = ShortcutSet([.dictate: [.functionHold], .clipboard: [.shiftCommandV]])
        #expect(set.action(holding: .shiftCommandV, besides: .dictate) == .clipboard)
        // Its own keys are not a clash with itself.
        #expect(set.action(holding: .functionHold, besides: .dictate) == nil)
    }

    @Test("survives a round trip through storage")
    func roundTrips() throws {
        let set = ShortcutSet([.dictate: [.functionHold, .optionSpace], .clipboard: [.shiftCommandV]])
        let restored = try JSONDecoder().decode(
            ShortcutSet.self, from: JSONEncoder().encode(set))
        #expect(restored == set)
    }

    @Test("drops an action a later build invented, rather than refusing the file")
    func unknownActionsAreDropped() throws {
        let json =
            #"{"dictate": [{"keyCode": 63, "modifiers": []}], "teleport": [{"keyCode": 49, "modifiers": ["option"]}]}"#
        let set = try JSONDecoder().decode(ShortcutSet.self, from: Data(json.utf8))
        #expect(set.bindings(for: .dictate) == [.functionHold])
        #expect(ShortcutAction.allCases.allSatisfy { $0 == .dictate || !set.isBound($0) })
    }
}
