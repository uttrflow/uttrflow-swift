import Testing

@testable import UttrflowPredict

@Suite("Which key accepts, application by application")
struct AcceptKeyTests {
    @Test("A plain text field gets Tab, which is what nothing else has claimed.")
    func defaultIsTab() {
        #expect(AcceptKeys.standard.key(forBundleIdentifier: "com.apple.Notes") == .tab)
    }

    @Test(
        "A terminal gets the right arrow, because Tab there is the shell's own completion.",
        arguments: [
            "com.apple.Terminal", "com.googlecode.iterm2", "com.mitchellh.ghostty",
            "net.kovidgoyal.kitty", "io.alacritty", "com.github.wez.wezterm",
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

    @Test("A bundle identifier is matched whatever its case, since macOS is inconsistent about it.")
    func matchingIgnoresCase() {
        #expect(AcceptKeys.standard.key(forBundleIdentifier: "COM.APPLE.TERMINAL") == .rightArrow)
    }

    @Test("The user's own choice beats what the application would otherwise get.")
    func overrideWins() {
        let keys = AcceptKeys(overrides: ["com.apple.Terminal": .optionTab])
        #expect(keys.key(forBundleIdentifier: "com.apple.Terminal") == .optionTab)
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
