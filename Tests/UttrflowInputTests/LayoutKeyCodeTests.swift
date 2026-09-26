import Testing

private import Carbon

@testable import UttrflowInput

/// Finds a key code from real layout tables; serialized because concurrent `TISCreateInputSourceList` calls crash HIToolbox.
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

    @Test("a character no key produces returns nil rather than a wrong key code")
    func unproducibleCharacterIsNil() throws {
        let data = try layoutData(id: "com.apple.keylayout.US")
        let controlCharacter = UniChar(0)
        #expect(LayoutKeyCode.code(for: controlCharacter, in: data) == nil)
    }
}
