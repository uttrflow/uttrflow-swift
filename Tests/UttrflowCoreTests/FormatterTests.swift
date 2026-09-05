import Testing

@testable import UttrflowCore

@Suite("Formatter")
struct FormatterTests {
    @Test("ships a value for every destination")
    func coversEveryDestination() {
        for destination in Destination.allCases {
            #expect(
                Formatter.registry[destination]?.destination == destination, "no formatter for \(destination)"
            )
            #expect(Formatter.standard(for: destination).destination == destination)
        }
    }

    @Test(
        "decides the first word and the last mark per destination, as the design's table says",
        arguments: [
            (Destination.document, FirstWordPolicy.fromInsertionPoint, TerminalStopPolicy.always),
            (.spreadsheet, .asSpoken, .never),
            (.sqlEditor, .fromInsertionPoint, .always),
            (.codeEditor, .fromInsertionPoint, .never),
            (.messaging, .fromInsertionPoint, .offForShortMessages(sentences: 2)),
            (.email, .fromInsertionPoint, .always),
            (.plain, .fromInsertionPoint, .always),
        ]
    )
    func policies(destination: Destination, firstWord: FirstWordPolicy, terminalStop: TerminalStopPolicy) {
        let formatter = Formatter.standard(for: destination)
        #expect(formatter.firstWord == firstWord)
        #expect(formatter.terminalStop == terminalStop)
    }

    @Test("is a value, so two formatters with the same decisions are the same formatter")
    func equality() {
        let one = Formatter(destination: .plain, firstWord: .alwaysCapital, terminalStop: .never)
        let two = Formatter(destination: .plain, firstWord: .alwaysCapital, terminalStop: .never)
        #expect(one == two)
        #expect(one != Formatter.standard(for: .plain))
    }
}
