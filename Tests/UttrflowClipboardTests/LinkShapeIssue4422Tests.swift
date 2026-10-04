import Testing

@testable import UttrflowClipboard

@Suite("Copied link shapes")
struct LinkShapeIssue4422Tests {
    @Test(
        "recognizes common schemes and address wrappers",
        arguments: [
            "ftp://files.example.com/report.pdf",
            "ssh://git@example.com/project",
            "file:///Users/me/report.pdf",
            "mailto:hello@example.com",
            "tel:+14155550123",
            "slack://channel?id=123",
            "obsidian://open?vault=Notes",
            "vscode://file/Users/me/project",
            "zoommtg://zoom.us/join?confno=123",
            "ws://localhost:8080/socket",
            "wss://example.com/socket",
            "sftp://example.com/path",
            "chrome://settings",
            "git@example.com:project/repository.git",
            "https://example.com/report.pdf.",
            "https://example.com/path).",
            "https://en.wikipedia.org/wiki/Foo_(bar)",
            "<https://example.com/docs>",
            "(https://example.com/docs)",
            "[https://example.com/docs]",
            "\"https://example.com/docs\"",
        ])
    func commonAddresses(_ text: String) {
        #expect(ClipKindDetector.kind(of: text) == .link)
    }

    @Test(
        "recognizes markdown links and address lists",
        arguments: [
            "[the docs](https://example.com/docs)",
            "[the docs](mailto:hello@example.com)",
            "https://one.example\nhttps://two.example/path",
            "- https://one.example\n- https://two.example/path",
            "1. https://one.example\n2. ftp://two.example/file",
            "\n  https://example.com/docs\n  Product guide \n",
        ])
    func compoundAddressClips(_ text: String) {
        #expect(ClipKindDetector.kind(of: text) == .link)
    }

    @Test(
        "leaves prose and incomplete addresses as text",
        arguments: [
            "Read https://example.com/docs for details",
            "See [the docs](https://example.com/docs) for details",
            "- https://one.example\n- this is not a link",
            "https://",
            "example.com",
            "www.example.com",
            "file://",
            "ssh://",
            "ftp://",
        ])
    func proseIsNotALink(_ text: String) {
        #expect(ClipKindDetector.kind(of: text) == .text)
    }
}
