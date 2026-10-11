import Foundation
import Testing
import UttrflowCore

@testable import UttrflowClipboard

@Suite("Pasting a multi-line clip into a terminal")
struct MultilinePasteCheckTests {
    private let terminal = "com.apple.Terminal"

    private func question(for text: String, into bundleIdentifier: String?, isOn: Bool = true) -> String? {
        let situation = PasteQuestion.Situation(
            isConcealed: false, field: .nonSecure, bundleIdentifier: bundleIdentifier, text: text,
            confirmsHiddenClips: true, confirmsMultiline: isOn)
        guard case .ask(let reason) = PasteQuestion.decide(situation) else { return nil }
        return reason.title
    }

    @Test("asks about a clip with several lines, naming the count")
    func multiLine() {
        #expect(
            question(for: "ls\npwd\nwhoami", into: terminal)
                == "This clip has 3 lines. Paste anyway?")
    }

    @Test("asks about a single line that ends in a newline")
    func trailingNewline() {
        #expect(
            question(for: "rm -rf build\n", into: terminal)
                == "This clip ends with a new line. Paste anyway?")
        #expect(PasteQuestion.lineCount(of: "a\r\nb\r\n") == 2)
    }

    @Test("lets a single line through")
    func singleLine() {
        #expect(question(for: "ls -la", into: terminal) == nil)
    }

    @Test("lets any clip through in an app that is not a terminal")
    func notATerminal() {
        #expect(question(for: "a\nb\n", into: "com.apple.TextEdit") == nil)
        #expect(question(for: "a\nb\n", into: nil) == nil)
    }

    @Test("lets a multi-line clip through when the check is off")
    func switchedOff() {
        #expect(question(for: "a\nb", into: terminal, isOn: false) == nil)
    }

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
