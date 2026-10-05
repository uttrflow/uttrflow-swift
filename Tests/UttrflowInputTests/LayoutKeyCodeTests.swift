import Testing

private import Carbon

@testable import UttrflowInput

/// Finds a key code from real layout tables; on the main actor because `TISCreateInputSourceList` aborts off it.
@MainActor
@Suite("Finding the key that types a character under a layout", .serialized)
struct LayoutKeyCodeTests {
    /// `v`, the character every case below looks up.
    private let vCharacter = UniChar(UnicodeScalar("v").value)

    /// The raw layout table for an installed keyboard layout, by its Text Input Sources id.
    private func layoutData(id: String) throws -> Data {
        let filter = [kTISPropertyInputSourceID as String: id] as CFDictionary
        let list = try #require(
            TISCreateInputSourceList(filter, true)?.takeRetainedValue() as? [TISInputSource],
            "no input source list for \(id)")
        let source = try #require(list.first, "\(id) is not installed on this Mac")
        let property = try #require(
            TISGetInputSourceProperty(source, kTISPropertyUnicodeKeyLayoutData),
            "\(id) has no Unicode layout table")
        return Unmanaged<CFData>.fromOpaque(property).takeUnretainedValue() as Data
    }

    @Test("US QWERTY: V sits at key code 9")
    func qwerty() throws {
        let data = try layoutData(id: "com.apple.keylayout.US")
        #expect(LayoutKeyCode.code(for: vCharacter, in: data) == 9)
        #expect(
            LayoutKeyCode.stroke(for: UniChar(UnicodeScalar("A").value), in: data)
                == LayoutKeyCode.Stroke(code: 0, flags: .maskShift))
        #expect(
            LayoutKeyCode.stroke(for: UniChar(UnicodeScalar("!").value), in: data)
                == LayoutKeyCode.Stroke(code: 18, flags: .maskShift))
    }

    @Test("AZERTY: V still sits at key code 9, the position is shared with QWERTY")
    func azerty() throws {
        let data = try layoutData(id: "com.apple.keylayout.French")
        #expect(LayoutKeyCode.code(for: vCharacter, in: data) == 9)
    }

    @Test("Dvorak: V moves off key code 9, onto the position that types `.` on QWERTY")
    func dvorak() throws {
        let data = try layoutData(id: "com.apple.keylayout.Dvorak")
        let code = LayoutKeyCode.code(for: vCharacter, in: data)
        #expect(code != 9)
        #expect(code == 47)
    }

    @Test("Dvorak with a QWERTY ⌘ map: unmodified V still moves, the ⌘ map is a separate table")
    func dvorakWithCommandMap() throws {
        let data = try layoutData(id: "com.apple.keylayout.DVORAK-QWERTYCMD")
        #expect(LayoutKeyCode.code(for: vCharacter, in: data) != 9)
    }

    @Test("Dvorak with a QWERTY ⌘ map: with ⌘ held, V is back on key code 9")
    func dvorakWithCommandMapHeld() throws {
        let data = try layoutData(id: "com.apple.keylayout.DVORAK-QWERTYCMD")
        #expect(LayoutKeyCode.code(for: vCharacter, in: data, modifiers: LayoutKeyCode.commandHeld) == 9)
    }

    @Test("plain Dvorak: with ⌘ held, V stays on key code 47, since its ⌘ table is Dvorak too")
    func dvorakCommandHeld() throws {
        let data = try layoutData(id: "com.apple.keylayout.Dvorak")
        #expect(LayoutKeyCode.code(for: vCharacter, in: data, modifiers: LayoutKeyCode.commandHeld) == 47)
    }

    @Test("Russian: no key types V unmodified, and its ⌘ table puts V on key code 9")
    func russianCommandHeld() throws {
        let data = try layoutData(id: "com.apple.keylayout.Russian")
        #expect(LayoutKeyCode.code(for: vCharacter, in: data) == nil)
        #expect(LayoutKeyCode.code(for: vCharacter, in: data, modifiers: LayoutKeyCode.commandHeld) == 9)
    }

    @Test("a character no key produces returns nil rather than a wrong key code")
    func unproducibleCharacterIsNil() throws {
        let data = try layoutData(id: "com.apple.keylayout.US")
        let controlCharacter = UniChar(0)
        #expect(LayoutKeyCode.code(for: controlCharacter, in: data) == nil)
        #expect(LayoutKeyCode.stroke(for: controlCharacter, in: data) == nil)
    }

    /// The UTF-16 units a planned keypress carries, whichever kind it is.
    private func units(of keypresses: [LayoutKeyCode.Keypress]) -> [UniChar] {
        keypresses.flatMap { keypress -> [UniChar] in
            switch keypress {
            case .key(let unit, _): [unit]
            case .text(let units): units
            }
        }
    }

    @Test("US: accented letters and emoji go as Unicode strings while the rest keeps its keys")
    func usFallsBackPerCharacter() throws {
        let data = try layoutData(id: "com.apple.keylayout.US")
        let text = "caf\u{E9} Zo\u{EB} \u{1F600} \u{20B9}5"
        let plan = LayoutKeyCode.keypresses(for: text) { LayoutKeyCode.stroke(for: $0, in: data) }
        #expect(units(of: plan) == Array(text.utf16))
        let cKey = LayoutKeyCode.Stroke(code: 8, flags: [])
        #expect(plan.first == .key(UniChar(UnicodeScalar("c").value), cKey))
        #expect(plan[3] == .text([0xE9]))
        #expect(plan.contains(.text(Array("\u{1F600}".utf16))))
        #expect(plan.contains(.text([0x20B9])))
    }

    @Test("Russian and Devanagari: Latin dictation is still typed in full, as Unicode strings")
    func nonLatinLayoutTypesLatinText() throws {
        let text = "Hello, I am here at 5 pm."
        for id in ["com.apple.keylayout.Russian", "com.apple.keylayout.Devanagari-QWERTY"] {
            let data = try layoutData(id: id)
            let plan = LayoutKeyCode.keypresses(for: text) { LayoutKeyCode.stroke(for: $0, in: data) }
            #expect(units(of: plan) == Array(text.utf16), "\(id)")
            #expect(plan.first == .text([UniChar(UnicodeScalar("H").value)]), "\(id)")
        }
    }

    @Test("US QWERTY: Option-only symbols are planned as Option-flagged keys, the set a target probe types")
    func usOptionOnlySymbols() throws {
        let data = try layoutData(id: "com.apple.keylayout.US")
        let expected: [(String, CGKeyCode)] = [("¬", 37), ("√", 9), ("∑", 13), ("©", 5), ("π", 35)]
        for (symbol, code) in expected {
            let character = try #require(symbol.utf16.first)
            #expect(
                LayoutKeyCode.stroke(for: character, in: data)
                    == LayoutKeyCode.Stroke(code: code, flags: .maskAlternate), "\(symbol)")
        }
    }

    @Test("a multi-scalar cluster is one keypress, even where the layout keys its first scalar")
    func clusterIsOneKeypress() throws {
        let data = try layoutData(id: "com.apple.keylayout.US")
        let clusters = [
            "\u{1F468}\u{200D}\u{1F469}\u{200D}\u{1F467}", "\u{1F1EE}\u{1F1F3}", "e\u{301}\u{323}",
            "\u{915}\u{94D}\u{937}", "\u{1F44D}\u{1F3FD}",
        ]
        for cluster in clusters {
            let plan = LayoutKeyCode.keypresses(for: "a\(cluster)b") {
                LayoutKeyCode.stroke(for: $0, in: data)
            }
            #expect(plan.count == 3, "\(cluster.unicodeScalars.map(\.value))")
            #expect(plan[1] == .text(Array(cluster.utf16)))
        }
    }

    @Test("for random cluster-heavy text, keypresses rejoin to the input and each holds one whole cluster")
    func randomClusterTextSplitsOnlyBetweenClusters() throws {
        let data = try layoutData(id: "com.apple.keylayout.US")
        let alphabet: [String] = [
            "a", "Z", " ", "\u{E9}", "e", "\u{301}", "\u{323}", "\u{200D}", "\u{1F468}", "\u{1F469}",
            "\u{1F1EE}", "\u{1F1F3}", "\u{1F3FD}", "\u{FE0F}", "\u{915}", "\u{94D}", "\u{937}", "\r", "\n",
        ]
        var generator = SplitMix(seed: 0x4186)
        for _ in 0..<500 {
            let length = Int(generator.next() % 24)
            let text = (0..<length).map { _ in alphabet[Int(generator.next() % UInt64(alphabet.count))] }
                .joined()
            let plan = LayoutKeyCode.keypresses(for: text) { LayoutKeyCode.stroke(for: $0, in: data) }
            let pieces = plan.map { String(utf16CodeUnits: units(of: [$0]), count: units(of: [$0]).count) }
            #expect(pieces.joined() == text)
            #expect(pieces.allSatisfy { $0.count == 1 }, "\(text.unicodeScalars.map(\.value))")
        }
    }

    @Test("with no layout at all every cluster is sent as its string")
    func noLayoutSendsStrings() {
        let plan = LayoutKeyCode.keypresses(for: "ok\u{1F600}") { _ in nil }
        #expect(plan == [.text([0x6F]), .text([0x6B]), .text(Array("\u{1F600}".utf16))])
    }
}

/// A seeded generator, so a failing random case reproduces.
private struct SplitMix {
    var state: UInt64
    init(seed: UInt64) { state = seed }
    mutating func next() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }
}
