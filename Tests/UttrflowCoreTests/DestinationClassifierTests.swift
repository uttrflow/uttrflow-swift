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
            ("com.apple.Pages", .document),
            ("com.apple.Keynote", .document),
            ("com.apple.Numbers", .spreadsheet),
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
            ("com.jetbrains.goland", .codeEditor),
            ("com.jetbrains.rider", .codeEditor),
            ("com.jetbrains.webstorm", .codeEditor),
            ("com.jetbrains.phpstorm", .codeEditor),
            ("com.jetbrains.rubymine", .codeEditor),
            ("com.jetbrains.clion", .codeEditor),
            ("com.jetbrains.appcode", .codeEditor),
            ("com.jetbrains.mps", .codeEditor),
            ("com.apple.Terminal", .terminal),
            ("com.googlecode.iterm2", .terminal),
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

    @Test(
        "reads the identifiers probed from installed apps, and not their vendor siblings",
        arguments: [
            ("com.mongodb.compass", Destination.sqlEditor, "com.mongodb.atlas"),
            ("org.RedisLabs.RedisInsight-V2", .sqlEditor, "org.RedisLabs.RedisStack"),
            ("com.google.antigravity", .codeEditor, "com.google.drivefs"),
            ("com.vscodium", .codeEditor, "com.apple.TextEdit"),
            ("com.google.android.studio", .codeEditor, "com.google.Chrome"),
        ]
    )
    func classifiesProbedBundles(bundle: String, expected: Destination, sibling: String) {
        #expect(DestinationClassifier.classify(app(bundle)) == expected)
        #expect(DestinationClassifier.classify(app(sibling)) != expected)
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
            ("Budget - Excel", .spreadsheet),
            ("Budget - Excel for the web", .spreadsheet),
            ("Budget - Microsoft Excel", .spreadsheet),
            ("Budget - Microsoft Excel for the web", .spreadsheet),
            ("Inbox (3) - Gmail", .email),
            ("Compose Mail - Outlook", .email),
            ("Mail - Jane Doe - Outlook", .email),
            ("Draft - Spark", .email),
            ("Inbox - Superhuman", .email),
            ("pgAdmin 4", .sqlEditor),
        ]
    )
    func classifiesByTitle(title: String, expected: Destination) {
        #expect(DestinationClassifier.classify(app("com.google.Chrome", title: title)) == expected)
    }

    @Test("an unrelated title mentioning Excel is not a spreadsheet")
    func doesNotMatchAnExcelMentionInTheTitle() {
        #expect(
            DestinationClassifier.classify(app("com.google.Chrome", title: "Excel tips and formulas"))
                == .plain)
    }

    @Test(
        "reads browser chat tabs as messaging by whole-word service title",
        arguments: [
            "general (Channel) - Acme - Slack",
            "WhatsApp",
            "Discord | #general",
            "Telegram Web",
            "Microsoft Teams",
            "Signal",
        ]
    )
    func classifiesChatByTitle(title: String) {
        let browserTab = app("com.google.Chrome", title: title)
        let situation = SituationResolver.resolve(from: browserTab)

        #expect(situation.destination == .messaging)
        #expect(
            DestinationFormatter.standard(for: situation).terminalStop == .offForShortMessages(sentences: 2))
    }

    @Test("does not read a chat service name out of a longer title word")
    func doesNotMatchChatServiceMidWord() {
        #expect(DestinationClassifier.classify(app("com.google.Chrome", title: "Slackline launch")) == .plain)
    }

    @Test("does not read an email client name out of a longer title word")
    func doesNotMatchEmailClientMidWord() {
        #expect(DestinationClassifier.classify(app("com.google.Chrome", title: "Mailbox settings")) == .plain)
        #expect(
            DestinationClassifier.classify(app("com.google.Chrome", title: "Outlooked at the report"))
                == .plain)
    }

    @Test("is plain for an app the table does not name, and for no app at all")
    func plainByDefault() {
        #expect(DestinationClassifier.classify(app("com.example.Unknown", title: "Untitled")) == .plain)
        #expect(DestinationClassifier.classify(app("com.jetbrains.toolbox")) == .plain)
        #expect(DestinationClassifier.kind(for: app("com.jetbrains.toolbox")) == nil)
        #expect(DestinationClassifier.classify(.unknown) == .plain)
        #expect(DestinationClassifier.classify(app("", title: "")) == .plain)
    }

    @Test("the longest matching bundle prefix wins regardless of row order")
    func mostSpecificBundleMatchWins() {
        let rules = [
            DestinationRule(bundlePrefixes: ["com.example."], destination: .email),
            DestinationRule(bundlePrefixes: ["com.example.app"], destination: .messaging),
        ]
        let context = app("com.example.app")
        #expect(DestinationClassifier.classify(context, rules: rules) == .messaging)
        #expect(DestinationClassifier.classify(context, rules: Array(rules.reversed())) == .messaging)
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
        #expect(rule.matches(app(title: "Plan - Docs")))
        #expect(!rule.matches(app("com.example")))
    }

    @Test("every rule in the shipped table names at least one way to match")
    func shippedRulesAreUsable() {
        for rule in DestinationRules.standard {
            #expect(!rule.bundlePrefixes.isEmpty || !rule.titleContains.isEmpty)
        }
        #expect(Set(DestinationRules.standard.map(\.destination)).isSuperset(of: Destination.allCases))
    }
}
