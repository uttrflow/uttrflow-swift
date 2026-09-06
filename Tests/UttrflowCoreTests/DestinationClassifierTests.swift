import Testing

@testable import UttrflowCore

@Suite("DestinationClassifier")
struct DestinationClassifierTests {
    private func app(_ bundle: String? = nil, title: String? = nil) -> AppContext {
        AppContext(bundleIdentifier: bundle, documentName: title)
    }

    @Test(
        "reads every shipped app off the table",
        arguments: [
            ("com.microsoft.Word", Destination.document),
            ("com.apple.iWork.Pages", .document),
            ("com.apple.Notes", .document),
            ("com.apple.TextEdit", .document),
            ("com.apple.iWork.Numbers", .spreadsheet),
            ("com.microsoft.Excel", .spreadsheet),
            ("at.eggerapps.Postico", .sqlEditor),
            ("com.tinyapp.TablePlus", .sqlEditor),
            ("com.jetbrains.datagrip", .sqlEditor),
            ("org.jkiss.dbeaver.core.product", .sqlEditor),
            ("org.pgadmin.pgadmin4", .sqlEditor),
            ("com.apple.dt.Xcode", .codeEditor),
            ("com.todesktop.230313mzl4w4u92", .codeEditor),
            ("com.microsoft.VSCode", .codeEditor),
            ("dev.zed.Zed", .codeEditor),
            ("com.jetbrains.pycharm", .codeEditor),
            ("com.apple.Terminal", .codeEditor),
            ("com.googlecode.iterm2", .codeEditor),
            ("com.tinyspeck.slackmacgap", .messaging),
            ("net.whatsapp.WhatsApp", .messaging),
            ("ru.keepcoder.Telegram", .messaging),
            ("com.hnc.Discord", .messaging),
            ("com.apple.MobileSMS", .messaging),
            ("com.microsoft.teams2", .messaging),
            ("com.apple.mail", .email),
            ("com.microsoft.Outlook", .email),
            ("com.superhuman.electron", .email),
        ]
    )
    func classifiesByBundle(bundle: String, expected: Destination) {
        #expect(DestinationClassifier.classify(app(bundle)) == expected)
    }

    @Test("matches a bundle identifier whatever its case")
    func ignoresBundleCase() {
        #expect(DestinationClassifier.classify(app("COM.APPLE.NOTES")) == .document)
    }

    @Test(
        "reads a browser tab off its title",
        arguments: [
            ("Quarterly plan - Google Docs", Destination.document),
            ("Budget - Google Sheets", .spreadsheet),
            ("Inbox (3) - Gmail", .email),
            ("pgAdmin 4", .sqlEditor),
        ]
    )
    func classifiesByTitle(title: String, expected: Destination) {
        #expect(DestinationClassifier.classify(app("com.google.Chrome", title: title)) == expected)
    }

    @Test("is plain for an app the table does not name, and for no app at all")
    func plainByDefault() {
        #expect(DestinationClassifier.classify(app("com.example.Unknown", title: "Untitled")) == .plain)
        #expect(DestinationClassifier.classify(.unknown) == .plain)
        #expect(DestinationClassifier.classify(app("", title: "")) == .plain)
    }

    @Test("the first matching rule wins, which is what keeps DataGrip out of the editors")
    func firstMatchWins() {
        let rules = [
            DestinationRule(bundlePrefixes: ["com.example."], destination: .email),
            DestinationRule(bundlePrefixes: ["com.example.app"], destination: .messaging),
        ]
        #expect(DestinationClassifier.classify(app("com.example.app"), rules: rules) == .email)
        #expect(DestinationClassifier.classify(app("com.example.app"), rules: []) == .plain)
    }

    @Test("an app the table names by identifier keeps its kind whatever its window is called")
    func bundleBeatsATitleAboveIt() {
        let mail = app("com.apple.mail", title: "Re: the Google Docs migration")
        #expect(DestinationClassifier.classify(mail) == .email)
        let sheet = app("com.example.Unknown", title: "Budget — Google Sheets")
        #expect(
            DestinationClassifier.classify(sheet) == .spreadsheet,
            "a title still decides an app no row names")
    }

    @Test("a rule can be built from either column and defaults the other to nothing")
    func ruleDefaults() {
        let rule = DestinationRule(titleContains: ["Docs"], destination: .document)
        #expect(rule.bundlePrefixes.isEmpty)
        #expect(rule.matches(app(title: "My Docs")))
        #expect(!rule.matches(app("com.example")))
    }

    @Test("every rule in the shipped table names at least one way to match")
    func shippedRulesAreUsable() {
        for rule in DestinationRules.standard {
            #expect(!rule.bundlePrefixes.isEmpty || !rule.titleContains.isEmpty)
        }
        #expect(Set(DestinationRules.standard.map(\.destination)).count == Destination.allCases.count - 1)
    }
}
