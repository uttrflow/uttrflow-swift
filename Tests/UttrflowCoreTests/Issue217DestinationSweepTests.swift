import Testing

@testable import UttrflowCore

/// Regression for issue 217: a window-title fragment has to stand as words before it picks a formatter.
@Suite("Issue 217 sweep: a title substring decides nothing mid-word")
struct Issue217DestinationSweepTests {
    @Test("refuses a fragment buried inside a longer word")
    func refusesAMidWordFragment() {
        let rule = DestinationRule(titleContains: ["Gmail"], destination: .email)
        #expect(!rule.matchesTitle(AppContext(documentName: "gmailer release notes")))
        #expect(!rule.matchesTitle(AppContext(documentName: "ungmail")))
        #expect(rule.matchesTitle(AppContext(documentName: "Inbox (3) - Gmail")))
    }

    @Test("every browser tab the table is written for still reads off its title")
    func keepsTheTabsItWasWrittenFor() {
        for (title, expected) in [
            ("Quarterly plan - Google Docs", Destination.document),
            ("Budget - Google Sheets", .spreadsheet),
            ("Inbox (3) - Gmail", .email),
            ("pgAdmin 4", .sqlEditor),
        ] {
            let app = AppContext(bundleIdentifier: "com.google.Chrome", documentName: title)
            #expect(DestinationClassifier.classify(app) == expected)
        }
    }
}
