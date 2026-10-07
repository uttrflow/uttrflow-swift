import Testing
import UttrflowCore

@testable import UttrflowAI

/// Issue #1923: in a terminal the first word of a dictated command must keep its heard case.
@Suite("A terminal keeps the heard case of a command's first word", .bug(id: 1923))
struct TerminalHeardCaseTests {
    private let terminal = AppContext(
        applicationName: "Terminal", bundleIdentifier: "com.apple.Terminal")
    private let codeEditor = AppContext(
        applicationName: "Xcode", bundleIdentifier: "com.apple.dt.Xcode",
        documentName: "AppDelegate.swift")

    private func cleaned(_ spoken: String, into app: AppContext) -> String {
        let situation = SituationResolver.resolve(from: app)
        let formatter = DestinationFormatter.standard(for: situation.destination)
        return CleaningPipeline.standard(for: formatter, situation: situation)
            .run(Draft(text: spoken)).text
    }

    /// A terminal app resolves to the terminal destination rather than the code editor's.
    @Test("the terminal destination is reached from com.apple.Terminal")
    func terminalResolvesToTerminal() {
        let destination = SituationResolver.resolve(from: terminal).destination
        #expect(destination == .terminal)
    }

    /// A code editor still resolves to the code editor destination.
    @Test("the code editor destination is reached from Xcode")
    func codeEditorStillResolvesToCodeEditor() {
        let destination = SituationResolver.resolve(from: codeEditor).destination
        #expect(destination == .codeEditor)
    }

    /// The terminal formatter keeps the first word's heard case, since the shell is case-sensitive.
    @Test("the terminal formatter copies the first word's heard case")
    func terminalFormatterPolicy() {
        let formatter = DestinationFormatter.standard(for: .terminal)
        #expect(formatter.firstWord == .asSpoken)
        #expect(formatter.terminalStop == .never)
        #expect(formatter.layout.contains(.preserveNewlines))
        #expect(formatter.grammar == .asSpoken)
    }

    /// The exact cases the issue lists: every lower-case command stays lower-case.
    @Test("a dictated command keeps its case while spoken flags become literal")
    func terminalCommandsKeepTheirCase() {
        for (spoken, expected) in [
            ("ls dash la", "ls -la"), ("npm run build", "npm run build"),
            ("git commit dash m fix the login bug", "git commit -m fix the login bug"),
            ("cd documents slash projects", "cd documents slash projects"),
            ("docker compose up dash d", "docker compose up -d"),
        ] {
            #expect(cleaned(spoken, into: terminal) == expected)
        }
    }

    /// The case the speaker said is preserved through the deterministic pipeline, not just by the formatter.
    @Test("spoken short flags become literal in the rules path")
    func terminalKeepsCaseInTheRulesPath() {
        #expect(cleaned("ls dash la", into: terminal) == "ls -la")
        #expect(cleaned("npm run build", into: terminal) == "npm run build")
    }

    /// A code editor still capitalises the start of a sentence, so the fix has not over-corrected.
    @Test("a code editor capitalises the start of a dictated sentence")
    func codeEditorStillCapitalises() {
        #expect(cleaned("the build failed", into: codeEditor) == "The build failed")
        #expect(cleaned("function do thing", into: codeEditor) == "Function do thing")
    }

    /// A capitalised word mid-sentence in a code editor is left alone; a terminal never capitalises anyway.
    @Test("the code editor still mid-sentence lower-cases a first word at an unknown caret")
    func codeEditorMidSentenceLowercases() {
        let midway = AppContext(
            applicationName: "Xcode", bundleIdentifier: "com.apple.dt.Xcode",
            documentName: "AppDelegate.swift",
            precedingText: "we ran the suite. then ")
        let situation = SituationResolver.resolve(from: midway)
        let formatter = DestinationFormatter.standard(for: situation.destination)
        let cleaned = CleaningPipeline.standard(for: formatter, situation: situation)
            .run(Draft(text: "the build failed")).text
        #expect(cleaned == "the build failed")
    }
}

/// A spoken flag letter is an option, not the pronoun, so later casing leaves it alone.
@Suite("A spoken flag letter keeps the case it was given", .bug(id: 4442))
struct SpokenFlagCaseTests {
    private static let terminal = AppContext(
        applicationName: "Terminal", bundleIdentifier: "com.apple.Terminal")
    private static let codeEditor = AppContext(
        applicationName: "Xcode", bundleIdentifier: "com.apple.dt.Xcode",
        documentName: "AppDelegate.swift")
    private static let notes = AppContext(applicationName: "Notes", bundleIdentifier: "com.apple.Notes")

    private static func cleaned(_ spoken: String, into app: AppContext) -> String {
        let situation = SituationResolver.resolve(from: app)
        let formatter = DestinationFormatter.standard(for: situation.destination)
        return CleaningPipeline.standard(for: formatter, situation: situation)
            .run(Draft(text: spoken)).text
    }

    @Test(
        "dash i stays -i, dash capital i is -I, and dash v stays -v",
        arguments: [
            ("ssh dash i key", "ssh -i key"),
            ("grep dash i error", "grep -i error"),
            ("grep dash capital i error", "grep -I error"),
            ("curl dash v example.com", "curl -v example.com"),
        ])
    func flagLetterKeepsItsCase(_ spoken: String, _ expected: String) {
        #expect(Self.cleaned(spoken, into: Self.terminal) == expected)
        let option = expected.split(separator: " ")[1]
        #expect(Self.cleaned(spoken, into: Self.codeEditor).split(separator: " ")[1] == option)
    }

    @Test("the pronoun in prose is still capitalised")
    func pronounInProseUnchanged() {
        #expect(Self.cleaned("then i left", into: Self.notes) == "Then I left.")
    }
}

/// A shell command in source is not a sentence, so its program name keeps the case it was heard in.
@Suite("A command line in a code editor keeps its heard case", .bug(id: 4441))
struct CodeEditorCommandCaseTests {
    private static let source = AppContext(
        applicationName: "Xcode", bundleIdentifier: "com.apple.dt.Xcode", documentName: "deploy.sh")
    private static let prose = AppContext(
        applicationName: "Xcode", bundleIdentifier: "com.apple.dt.Xcode", documentName: "README.md",
        precedingText: "")
    private static let chat = AppContext(applicationName: "Messages", bundleIdentifier: "com.apple.MobileSMS")

    private static func cleaned(_ spoken: String, into app: AppContext) -> String {
        let situation = SituationResolver.resolve(from: app)
        let formatter = DestinationFormatter.standard(for: situation)
        return CleaningPipeline.standard(for: formatter, situation: situation)
            .run(Draft(text: spoken)).text
    }

    @Test(
        "a command line keeps its program name lower case",
        arguments: [
            ("npm run build", "npm run build"), ("git push origin main", "git push origin main"),
            ("ls dash l", "ls -l"), ("docker compose up", "docker compose up"),
        ])
    func commandKeepsCase(_ spoken: String, _ expected: String) {
        #expect(Self.cleaned(spoken, into: Self.source) == expected)
    }

    @Test("a lone program name is not a command line, and a sentence still gets its capital")
    func proseInSourceKeepsCapital() {
        #expect(Self.cleaned("the build failed", into: Self.source) == "The build failed")
        #expect(Self.cleaned("git", into: Self.source) == "Git")
    }

    @Test("prose that opens with a program name keeps its capital in a document and a chat")
    func proseElsewhereKeepsCapital() {
        #expect(Self.cleaned("git is slow today", into: Self.prose).hasPrefix("Git is slow today"))
        #expect(Self.cleaned("git is slow today", into: Self.chat).hasPrefix("Git is slow today"))
    }
}
