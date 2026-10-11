import Foundation
import Testing

@testable import UttrflowClipboard

@Suite("The terminal paste switch in clipboard preferences")
struct ClipboardPreferencesMultilineTests {
    @Test("reads preferences saved before the check existed as having it on")
    func olderFile() throws {
        let old = Data(#"{"excludedBundleIdentifiers":["com.example.a"]}"#.utf8)
        let decoded = try JSONDecoder().decode(ClipboardPreferences.self, from: old)
        #expect(decoded.confirmsMultilinePaste)
        var off = decoded
        off.confirmsMultilinePaste = false
        let again = try JSONDecoder().decode(ClipboardPreferences.self, from: JSONEncoder().encode(off))
        #expect(!again.confirmsMultilinePaste)
    }
}
