import Testing

@testable import UttrflowClipboard

@Suite("Ordinary notes and prose are not code")
struct ProseNotCodeTests {
    @Test(arguments: [
        "# 1 priority for today is to finish the report",
        "My := plan",
        "Foo(bar)",
        "a | b\n--- | ---",
        "module.exports = 3",
    ])
    func noteIsText(_ text: String) {
        #expect(ClipKindDetector.kind(of: text) == .text)
    }
}
