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
            (
                .messaging, .fromInsertionPoint, .offForShortMessages(sentences: 2), .paragraphs,
                .asSpoken, .fromTen
            ),
            (.email, .fromInsertionPoint, .always, [.paragraphs, .lists], .repair, .fromTen),
            (.plain, .fromInsertionPoint, .always, .paragraphs, .repair, .fromTen),
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
}
