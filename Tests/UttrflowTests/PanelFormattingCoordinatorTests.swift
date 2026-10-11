// Tests for the panel formatter's guarded result and request ownership.
import OSLog
import Testing
import UttrflowClipboard
import UttrflowCore
@testable import Uttrflow
@testable import UttrflowUX

@Suite("Panel formatting execution")
@MainActor
struct PanelFormattingCoordinatorTests {
    nonisolated static let original = "let value=1"
    nonisolated static let formatted = "let value = 1"

    @Test(
        "refused, changed-meaning and identical outputs end without presenting a sheet",
        arguments: [
            (nil, PanelFormatEnding.unreadable),
            ("let value=2", .unfaithful), (original, .alreadyFormatted),
        ])
    func endsWithoutSheet(_ output: String?, _ expected: PanelFormatEnding) async {
        let formatter = PanelFormatterStub(output: output)
        var endings: [PanelFormatEnding] = []
        var shown = 0
        await PanelFormattingCoordinator(formatter: formatter, log: Logger()).run(
            text: Self.original, language: .swift,
            actions: .init(
                isCurrent: { true }, finish: { endings.append($0) },
                present: { _, _ in shown += 1 }))
        #expect(endings == [expected])
        #expect(shown == 0)
        #expect(await formatter.texts == [Self.original])
        #expect(await formatter.languages == [.swift])
    }

    @Test("faithful output carries the original and exact prepared diff to one presentation")
    func presentsPreparedDiff() async throws {
        let formatter = PanelFormatterStub(output: Self.formatted)
        var endings: [PanelFormatEnding] = []
        var results: [(PreparedFormattingSheet, String)] = []
        await PanelFormattingCoordinator(formatter: formatter, log: Logger()).run(
            text: Self.original, language: .swift,
            actions: .init(
                isCurrent: { true }, finish: { endings.append($0) },
                present: { results.append(($0, $1)) }))
        #expect(endings.isEmpty)
        #expect(results.count == 1)
        let result = try #require(results.first)
        #expect(result.1 == Self.formatted)
        #expect(result.0.original == Self.original)
        #expect(result.0.formatted == Self.formatted)
        #expect(result.0.sheet.kind == .formatting)
        #expect(
            result.0.sheet.diff == [
                TextDiff.Line(kind: .removed, text: Self.original),
                TextDiff.Line(kind: .added, text: Self.formatted),
            ])
        #expect(result.0.sheet.isConfirmEnabled)
        #expect(await formatter.texts == [Self.original])
        #expect(await formatter.languages == [.swift])
    }

    @Test(
        "a request superseded while formatting publishes neither an ending nor a sheet",
        arguments: [nil, "let value=2", original, formatted])
    func ignoresSupersededRequest(_ output: String?) async {
        let (entered, arrival) = AsyncStream.makeStream(of: Void.self)
        let (resumed, release) = AsyncStream.makeStream(of: Void.self)
        let formatter = PanelFormatterStub(output: output) {
            arrival.yield(())
            for await _ in resumed { break }
        }
        var current = true
        var endings: [PanelFormatEnding] = []
        var shown = 0
        let run = Task {
            await PanelFormattingCoordinator(formatter: formatter, log: Logger()).run(
                text: Self.original, language: .swift,
                actions: .init(
                    isCurrent: { current }, finish: { endings.append($0) },
                    present: { _, _ in shown += 1 }))
        }
        for await _ in entered { break }
        current = false
        release.yield(())
        await run.value
        arrival.finish()
        release.finish()
        #expect(endings.isEmpty)
        #expect(shown == 0)
        #expect(await formatter.texts == [Self.original])
        #expect(await formatter.languages == [.swift])
    }
}

private actor PanelFormatterStub: CodeFormatting {
    let output: String?
    let beforeReturn: @Sendable () async -> Void
    var texts: [String] = []
    var languages: [CodeLanguage] = []

    init(output: String?, beforeReturn: @escaping @Sendable () async -> Void = {}) {
        self.output = output
        self.beforeReturn = beforeReturn
    }

    func isAvailable(for language: CodeLanguage) async -> Bool { true }

    func format(_ text: String, as language: CodeLanguage) async -> String? {
        texts.append(text)
        languages.append(language)
        await beforeReturn()
        return output
    }
}
