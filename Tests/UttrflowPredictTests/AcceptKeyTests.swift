import Testing
import UttrflowCore

@testable import UttrflowPredict

@Suite("Which key accepts, application by application")
struct AcceptKeyTests {
    @Test("A plain text field gets Tab, which is what nothing else has claimed.")
    func defaultIsTab() {
        #expect(AcceptKeys.standard.key(forBundleIdentifier: "com.example.plain-text-app") == .tab)
    }

    @Test(
        "Tab remains available for native editing in every destination kind.",
        arguments: [
            ("com.apple.Notes", nil, AcceptKey.optionTab),
            ("md.obsidian", nil, .optionTab),
            ("notion.id", nil, .optionTab),
            ("net.shinyfrog.bear", nil, .optionTab),
            ("com.microsoft.Word", nil, .optionTab),
            ("com.google.Chrome", "Quarterly plan - Google Docs", .optionTab),
            ("com.google.Chrome", "Budget - Excel", .optionTab),
            ("com.google.Chrome", "Budget - Excel for the web", .optionTab),
            ("com.google.Chrome", "Budget - Google Sheets", .optionTab),
            ("com.apple.mail", nil, .tab),
            ("com.apple.MobileSMS", nil, .tab),
            ("com.apple.Terminal", nil, .rightArrow),
            ("com.apple.dt.Xcode", nil, .optionTab),
            ("com.jetbrains.datagrip", nil, .optionTab),
            ("com.example.plain-text-app", nil, .tab),
        ])
    func destinationKindKeepsItsNativeTabBehavior(
        bundleIdentifier: String, documentName: String?, expected: AcceptKey
    ) {
        let application = AppContext(bundleIdentifier: bundleIdentifier, documentName: documentName)
        #expect(AcceptKeys.standard.key(for: application) == expected)
    }

    @Test(
        "Spreadsheets keep native cell navigation by accepting with Option-Tab.",
        arguments: [
            "com.apple.iWork.Numbers", "com.microsoft.Excel",
        ])
    func spreadsheetsGetOptionTab(bundleIdentifier: String) {
        #expect(AcceptKeys.standard.key(forBundleIdentifier: bundleIdentifier) == .optionTab)
    }

    @Test("Google Sheets gets Option-Tab when its browser window title identifies it.")
    func googleSheetsGetsOptionTab() {
        let application = AppContext(documentName: "Quarterly plan - Google Sheets")
        #expect(AcceptKeys.standard.key(for: application) == .optionTab)
    }

    @Test("A browser override wins when its window title identifies Google Sheets.")
    func browserSpreadsheetOverrideWins() {
        let keys = AcceptKeys(overrides: ["com.google.Chrome": .rightArrow])
        let application = AppContext(
            bundleIdentifier: "com.google.Chrome", documentName: "Quarterly plan - Google Sheets")

        #expect(keys.key(for: application) == .rightArrow)
    }

    @Test(
        "A terminal gets the right arrow, because Tab there is the shell's own completion.",
        arguments: [
            "com.apple.Terminal", "com.googlecode.iterm2", "com.mitchellh.ghostty",
            "net.kovidgoyal.kitty", "org.alacritty", "com.github.wez.wezterm",
            "dev.warp.Warp-Stable", "co.zeit.hyper", "org.tabby",
        ])
    func terminalsGetTheRightArrow(bundleIdentifier: String) {
        #expect(AcceptKeys.standard.key(forBundleIdentifier: bundleIdentifier) == .rightArrow)
    }

    @Test(
        "Every entry in the one terminal table is a terminal to both readers, so the key and the prompt strip agree.",
        arguments: TerminalApplications.bundleIdentifierPrefixes)
    func theTableAnswersBothReaders(bundleIdentifier: String) {
        #expect(TerminalApplications.contains(bundleIdentifier))
        #expect(AcceptKeys.standard.key(forBundleIdentifier: bundleIdentifier) == .rightArrow)
    }

    @Test(
        "The table is read whatever the identifier's case, and holds every terminal both readers ask about."
    )
    func theTableIgnoresCase() {
        #expect(TerminalApplications.contains("COM.APPLE.TERMINAL"))
        #expect(TerminalApplications.contains("co.zeit.hyper"))
        #expect(TerminalApplications.contains("dev.warp.Warp-Stable"))
        #expect(!TerminalApplications.contains("com.apple.Notes"))
    }

    @Test(
        "An editor gets Option-Tab, because Tab there is indentation before it is anything else.",
        arguments: [
            "com.apple.dt.Xcode", "com.microsoft.VSCode", "com.visualstudio.code.oss",
            "com.todesktop.230313mzl4w4u92", "com.jetbrains.intellij", "com.sublimetext.4",
            "dev.zed.Zed", "org.vim.MacVim", "com.panic.Nova",
        ])
    func editorsGetOptionTab(bundleIdentifier: String) {
        #expect(AcceptKeys.standard.key(forBundleIdentifier: bundleIdentifier) == .optionTab)
    }

    @Test(
        "A launcher gets Tab because it is not an editor.",
        arguments: ["com.jetbrains.toolbox"])
    func nonEditorsGetTab(bundleIdentifier: String) {
        #expect(AcceptKeys.standard.key(forBundleIdentifier: bundleIdentifier) == .tab)
    }

    @Test(
        "A query editor gets Option-Tab too, since its Tab indents or completes SQL.",
        arguments: ["com.jetbrains.datagrip", "com.tinyapp.TablePlus", "org.jkiss.dbeaver.core.product"])
    func queryEditorsGetOptionTab(bundleIdentifier: String) {
        #expect(AcceptKeys.standard.key(forBundleIdentifier: bundleIdentifier) == .optionTab)
    }

    @Test(
        "Document editors get Option-Tab so Tab remains available for their native editing behavior.",
        arguments: ["com.microsoft.Word", "com.apple.iWork.Pages", "com.apple.TextEdit"])
    func documentEditorsGetOptionTab(bundleIdentifier: String) {
        #expect(AcceptKeys.standard.key(forBundleIdentifier: bundleIdentifier) == .optionTab)
    }

    @Test(
        "Every terminal to AI suggestions is a terminal to dictation, and every terminal row is one to suggestions."
    )
    func terminalsAgreeWithTheDestinationTable() {
        for prefix in TerminalApplications.bundleIdentifierPrefixes {
            #expect(
                DestinationClassifier.rule(for: AppContext(bundleIdentifier: prefix))?.kind == .terminal,
                "\(prefix) is a terminal to suggestions and not to dictation")
        }
        let rows = DestinationRules.standard.filter { $0.kind == .terminal }
        for prefix in rows.flatMap(\.bundlePrefixes) {
            #expect(TerminalApplications.contains(prefix), "\(prefix) is a terminal to dictation only")
        }
    }

    @Test(
        "Every editor to AI suggestions is an editor to dictation, so a dictation there is laid out as code.")
    func editorsAgreeWithTheDestinationTable() {
        let editors = DestinationRules.bundlePrefixes(of: [.codeEditor, .sqlEditor])
        #expect(!editors.isEmpty)
        for prefix in editors {
            #expect(AcceptKeys.standard.key(forBundleIdentifier: prefix) == .optionTab)
            let kind = DestinationClassifier.rule(for: AppContext(bundleIdentifier: prefix))?.kind
            #expect(
                kind == .codeEditor || kind == .sqlEditor || kind == .documentEditor,
                "\(prefix) is an editor to suggestions only")
        }
    }

    @Test("A bundle identifier is matched whatever its case, since macOS is inconsistent about it.")
    func matchingIgnoresCase() {
        #expect(AcceptKeys.standard.key(forBundleIdentifier: "COM.APPLE.TERMINAL") == .rightArrow)
    }

    @Test("The user's own choice beats what the application would otherwise get.")
    func overrideWins() {
        let keys = AcceptKeys(overrides: ["com.apple.Terminal": .optionTab])
        #expect(keys.key(forBundleIdentifier: "com.apple.Terminal") == .optionTab)
    }

    @Test("A user's choice still wins for a document editor.")
    func documentEditorOverrideWins() {
        let keys = AcceptKeys(overrides: ["com.microsoft.Word": .tab])
        #expect(keys.key(forBundleIdentifier: "com.microsoft.Word") == .tab)
    }

    @Test("A user's choice still wins for a spreadsheet.")
    func spreadsheetOverrideWins() {
        let keys = AcceptKeys(overrides: ["com.microsoft.Excel": .rightArrow])
        #expect(keys.key(forBundleIdentifier: "com.microsoft.Excel") == .rightArrow)
    }

    @Test("An override is found however the user's own file spelled the identifier.")
    func overrideIgnoresCase() {
        let keys = AcceptKeys(overrides: ["COM.APPLE.NOTES": .rightArrow])
        #expect(keys.key(forBundleIdentifier: "com.apple.notes") == .rightArrow)
    }

    @Test("An override for one application leaves every other application alone.")
    func overrideIsNarrow() {
        let keys = AcceptKeys(overrides: ["com.apple.Notes": .rightArrow])
        #expect(keys.key(forBundleIdentifier: "com.apple.dt.Xcode") == .optionTab)
    }

    @Test("A field answers the same as the application it belongs to.")
    func surfacesAnswerTheSame() {
        let surface = Surface(bundleIdentifier: "com.apple.Terminal", role: "AXTextArea")
        #expect(AcceptKeys.standard.key(for: surface) == .rightArrow)
    }

    @Test("Every key is a keystroke the tap could actually see.")
    func everyKeyIsAStroke() {
        #expect(AcceptKey.tab.stroke == KeyStroke(.tab))
        #expect(AcceptKey.rightArrow.stroke == KeyStroke(.rightArrow))
        #expect(AcceptKey.optionTab.stroke == KeyStroke(.tab, modifiers: .option))
    }

    @Test("Every accept key occupies a slot the tap can arm.", arguments: AcceptKey.allCases)
    func everyKeyIsArmable(key: AcceptKey) {
        #expect(!ArmedKeys.slot(of: key.stroke).isEmpty)
    }
}
