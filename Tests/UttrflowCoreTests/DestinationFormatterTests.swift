import Testing

@testable import UttrflowCore

@Suite("DestinationFormatter")
struct DestinationFormatterTests {
    @Test("ships a value for every destination")
    func coversEveryDestination() {
        for destination in Destination.allCases {
            #expect(
                DestinationFormatter.registry[destination]?.destination == destination,
                "no formatter for \(destination)")
            #expect(DestinationFormatter.standard(for: destination).destination == destination)
        }
    }

    /// The design's table, one row per destination.
    static let table:
        [(Destination, FirstWordPolicy, TerminalStopPolicy, LayoutPolicy, GrammarPolicy, NumberPolicy)] = [
            (.document, .fromInsertionPoint, .always, [.paragraphs, .lists], .repair, .fromTen),
            (.spreadsheet, .asSpoken, .never, .singleLine, .asSpoken, .always),
            (.sqlEditor, .fromInsertionPoint, .always, .preserveNewlines, .asSpoken, .always),
            (.codeEditor, .fromInsertionPoint, .never, .preserveNewlines, .asSpoken, .always),
            (.terminal, .asSpoken, .never, .singleLine, .asSpoken, .always),
            (
                .messaging, .fromInsertionPoint, .offForShortMessages(sentences: 2), .paragraphs,
                .asSpoken, .fromTen
            ),
            (.email, .fromInsertionPoint, .always, [.paragraphs, .lists], .repair, .fromTen),
            (.plain, .fromInsertionPoint, .always, [.paragraphs, .lists], .repair, .fromTen),
        ]

    @Test(
        "decides the first word, the last mark, the layout, the grammar and the numbers, as the table says"
    )
    func policies() {
        #expect(Self.table.count == Destination.allCases.count)
        for (destination, firstWord, terminalStop, layout, grammar, numbers) in Self.table {
            let formatter = DestinationFormatter.standard(for: destination)
            #expect(formatter.firstWord == firstWord, "\(destination)")
            #expect(formatter.terminalStop == terminalStop, "\(destination)")
            #expect(formatter.layout == layout, "\(destination)")
            #expect(formatter.grammar == grammar, "\(destination)")
            #expect(formatter.numbers == numbers, "\(destination)")
        }
    }

    @Test("lays out paragraphs and lists as two decisions, so a place can want one without the other")
    func layoutIsAnOptionSet() {
        let both: LayoutPolicy = [.paragraphs, .lists]
        #expect(both.contains(.paragraphs) && both.contains(.lists))
        #expect(!LayoutPolicy.paragraphs.contains(.lists))
        #expect(LayoutPolicy.singleLine != LayoutPolicy.preserveNewlines)
    }

    @Test("names a prompt block after its destination, so the model is shown that place's rules")
    func promptBlocks() {
        for destination in Destination.allCases {
            #expect(
                DestinationFormatter.standard(for: destination).promptBlock.rawValue == destination.rawValue)
        }
        #expect(PromptBlockID("shared").description == "shared")
        #expect(PromptBlockID(rawValue: "shared") == "shared")
    }

    @Test("is a value, so two formatters with the same decisions are the same formatter")
    func equality() {
        let one = DestinationFormatter(
            destination: .plain, firstWord: .alwaysCapital, terminalStop: .never, layout: .singleLine,
            grammar: .asSpoken, numbers: .always, promptBlock: "plain")
        let two = DestinationFormatter(
            destination: .plain, firstWord: .alwaysCapital, terminalStop: .never, layout: .singleLine,
            grammar: .asSpoken, numbers: .always, promptBlock: "plain")
        #expect(one == two)
        #expect(one != DestinationFormatter.standard(for: .plain))
    }

    @Test("search fields preserve heard casing, omit terminal stops, and stay on one line")
    func searchField() {
        let app = AppContext(accessibilityRole: "AXSearchField", isMultiline: false)
        let formatter = DestinationFormatter.standard(for: SituationResolver.resolve(from: app))
        #expect(formatter.firstWord == .asSpoken)
        #expect(formatter.terminalStop == .never)
        #expect(formatter.layout == .singleLine)
    }

    @Test(
        "a launcher panel's one-line field takes the search policy whatever role it reports",
        arguments: [DestinationRules.spotlight, DestinationRules.raycast, DestinationRules.alfred])
    func launcherField(bundle: String) {
        for role in ["AXTextField", "AXSearchField", nil] {
            let app = AppContext(bundleIdentifier: bundle, accessibilityRole: role, isMultiline: false)
            let formatter = DestinationFormatter.standard(for: SituationResolver.resolve(from: app))
            #expect(formatter.firstWord == .asSpoken, "\(role ?? "nil")")
            #expect(formatter.terminalStop == .never, "\(role ?? "nil")")
            #expect(formatter.layout == .singleLine, "\(role ?? "nil")")
            #expect(formatter.consequence == .navigates, "\(role ?? "nil")")
        }
    }

    @Test("an editor's main text area keeps its own policy beside the launcher row")
    func editorUnchangedByLauncherRow() {
        let app = AppContext(
            bundleIdentifier: DestinationRules.vsCode, accessibilityRole: "AXTextArea", isMultiline: true)
        let formatter = DestinationFormatter.standard(for: SituationResolver.resolve(from: app))
        #expect(formatter == DestinationFormatter.standard(for: .codeEditor))
    }

    @Test(
        "declares what each place does with the text, so a field that runs it is not treated like one that keeps it"
    )
    func consequences() {
        let expected: [Destination: Consequence] = [
            .document: .stores, .spreadsheet: .stores, .sqlEditor: .stores, .codeEditor: .stores,
            .terminal: .executes, .messaging: .sends, .email: .stores, .plain: .stores,
        ]
        #expect(expected.count == Destination.allCases.count)
        for (destination, consequence) in expected {
            #expect(
                DestinationFormatter.standard(for: destination).consequence == consequence, "\(destination)")
        }
        let search = AppContext(accessibilityRole: "AXSearchField", isMultiline: false)
        #expect(
            DestinationFormatter.standard(for: SituationResolver.resolve(from: search)).consequence
                == .navigates)
    }

    @Test("never lays out paragraphs or lists where Return runs the text")
    func executingPlacesAddNoLayout() {
        for formatter in DestinationFormatter.registry.values where formatter.consequence == .executes {
            #expect(!formatter.layout.contains(.paragraphs), "\(formatter.destination)")
            #expect(!formatter.layout.contains(.lists), "\(formatter.destination)")
        }
    }

    @Test("AX text fields stay on one line")
    func textField() {
        let app = AppContext(accessibilityRole: "AXTextField", isMultiline: false)
        let formatter = DestinationFormatter.standard(for: SituationResolver.resolve(from: app))
        #expect(formatter.layout == .singleLine)
    }

    @Test("owes formatting only where its first-word or stop policy would still change the text")
    func owesFormattingFollowsPolicy() {
        let text = "average handling time in minutes"
        for destination in Destination.allCases {
            let formatter = DestinationFormatter.standard(for: destination)
            let expected = formatter.firstWord != .asSpoken && formatter.terminalStop != .never
            #expect(formatter.owesFormatting(text) == expected, "\(destination)")
            #expect(!formatter.owesFormatting("Average handling time in minutes"), "\(destination)")
            #expect(!formatter.owesFormatting("average handling time, in minutes"), "\(destination)")
            #expect(formatter.owesFormatting("version 2.4.1 at 9,000 rpm") == expected, "\(destination)")
        }
    }

    @Test("a one-line field of no known purpose withholds the stop from one sentence only")
    func oneLineFieldStop() {
        let app = AppContext(accessibilityRole: "AXTextField", isMultiline: false)
        let formatter = DestinationFormatter.standard(for: SituationResolver.resolve(from: app))
        #expect(formatter.terminalStop == .offForShortMessages(sentences: 1))
        #expect(DestinationFormatter.standard(for: .plain).terminalStop == .always)
    }

    @Test("a one-line field keeps a stricter destination policy")
    func oneLineFieldKeepsNever() {
        let app = AppContext(isMultiline: false)
        let situation = Situation(app: app, insertion: .unknown, destination: .spreadsheet)
        #expect(DestinationFormatter.standard(for: situation).terminalStop == .never)
    }

    private static func codeEditor(document: String, before: String) -> DestinationFormatter {
        let app = AppContext(documentName: document)
        let insertion = InsertionPoint(precedingText: before)
        return DestinationFormatter.standard(
            for: Situation(app: app, insertion: insertion, destination: .codeEditor))
    }

    @Test("a README paragraph in a code editor takes a document's stop and lists")
    func markdownParagraph() {
        let formatter = Self.codeEditor(document: "README.md", before: "# Setup\n\n")
        #expect(formatter.terminalStop == .always)
        #expect(formatter.layout == [.paragraphs, .lists])
        #expect(Self.codeEditor(document: "notes.txt", before: "").terminalStop == .always)
    }

    @Test("a Markdown heading and a commit subject stay stopless")
    func headingAndCommitSubject() {
        #expect(Self.codeEditor(document: "README.md", before: "Intro\n\n## ").terminalStop == .never)
        let subject = Self.codeEditor(document: "COMMIT_EDITMSG", before: "")
        #expect(subject.terminalStop == .never)
        #expect(subject.layout == .preserveNewlines)
    }

    @Test("a statement in source takes its first word as spoken, while a comment keeps the caret's capital")
    func statementFirstWordAsSpoken() {
        #expect(Self.codeEditor(document: "Limits.swift", before: "    ").firstWord == .asSpoken)
        #expect(Self.codeEditor(document: "Limits.swift", before: "    // ").firstWord == .fromInsertionPoint)
        #expect(Self.codeEditor(document: "README.md", before: "").firstWord == .fromInsertionPoint)
    }
}
