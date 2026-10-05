import Testing

@testable import UttrflowCore

@Suite("DestinationClassifier page host")
struct DestinationHostTests {
    private static let rules: [DestinationRule] = [
        DestinationRule(
            hostSuffixes: ["sheets.example.com"], titleContains: ["Example Sheets"], kind: .spreadsheet),
        DestinationRule(hostSuffixes: ["chat.example.net"], titleContains: ["Chatter"], kind: .chat),
        DestinationRule(hostSuffixes: ["example.com"], titleContains: ["Mail"], kind: .email),
    ]

    private static let browser = "com.example.browser"

    @Test(
        "the host decides a page-hosted app before its title",
        arguments: [
            ("https://mail.example.com/u/0/inbox?q=secret", "Inbox (3) - Mail", Destination.email),
            ("https://mail.example.com/thread/9", "Quarterly numbers", .email),
            ("https://sheets.example.com/d/abc/edit", "Budget - Example Sheets", .spreadsheet),
            ("https://sheets.example.com/d/abc/edit", "Budget", .spreadsheet),
            ("https://chat.example.net/client/T1/C2", "general", .messaging),
            ("https://eu.chat.example.net/", "Chatter", .messaging),
            ("HTTPS://Chat.Example.NET./x", "anything", .messaging),
            ("https://notexample.com/a", "Budget", .plain),
            ("https://blog.invalid/posts/mail-merge", "Mail merge guide", .plain),
            ("https://docs.invalid/help", "How to use Chatter well", .plain),
            ("https://news.invalid/", "Chatter", .messaging),
            ("file:///Users/someone/page.html", "Mail merge guide", .plain),
        ])
    func hostFirst(address: String, title: String, expected: Destination) {
        let app = AppContext(bundleIdentifier: Self.browser, documentName: title, pageAddress: address)
        #expect(DestinationClassifier.classify(app, rules: Self.rules) == expected)
    }

    @Test("without an address the title still decides")
    func titleFallback() {
        let app = AppContext(bundleIdentifier: Self.browser, documentName: "Inbox - Mail")
        #expect(DestinationClassifier.classify(app, rules: Self.rules) == .email)
    }

    @Test("the longest host suffix wins over a shorter one in an earlier row")
    func longestSuffix() {
        let rules = Array(Self.rules.reversed())
        let app = AppContext(pageAddress: "https://sheets.example.com/d/1")
        #expect(DestinationClassifier.classify(app, rules: rules) == .spreadsheet)
    }

    @Test(
        "an address keeps only its host",
        arguments: [
            ("https://Mail.Example.com/inbox?q=private#frag", "mail.example.com" as String?),
            ("http://user:pw@chat.example.net:8443/a", "chat.example.net"),
            ("about:blank", nil),
            ("file:///tmp/x.html", nil),
            ("not an address", nil),
        ])
    func hostOnly(address: String, expected: String?) {
        #expect(AppContext(pageAddress: address).pageHost == expected)
    }

    @Test("the host never reaches a description")
    func neverDescribed() {
        let app = AppContext(applicationName: "Browser", pageAddress: "https://mail.example.com/x")
        #expect(!app.description.contains("example"))
    }

    @Test("a bundle row still outranks the host")
    func bundleFirst() {
        let rules = Self.rules + [DestinationRule(bundlePrefixes: [Self.browser], kind: .codeEditor)]
        let app = AppContext(bundleIdentifier: Self.browser, pageAddress: "https://mail.example.com/")
        #expect(DestinationClassifier.classify(app, rules: rules) == .codeEditor)
    }
}
