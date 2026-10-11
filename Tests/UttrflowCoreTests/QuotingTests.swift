import Testing
import UttrflowTestSupport

@testable import UttrflowCore

@Suite("Writing and finding quoted values")
struct QuotingTests {
    static let styles: [(String, QuoteStyle)] = [
        ("sql", .sql), ("shellSingle", .shellSingle), ("shellDouble", .shellDouble),
        ("json", .json), ("swift", .swift), ("python", .python),
    ]

    static let specials: [Character] = [
        "'", "\"", "\\", "$", "`", "\n", "\r", "\t", "\0", "\u{1}", "\u{1F}", "\r\n", "é", "a", " ",
    ]

    @Test("reads back every value it writes, for every style", arguments: styles.map(\.0))
    func roundTrips(name: String) throws {
        let style = try #require(Self.styles.first { $0.0 == name }?.1)
        var generator = Seeded(seed: 3870)
        for _ in 0..<500 {
            let length = Int.random(in: 0...8, using: &generator)
            let value = String(
                (0..<length).map { _ in Self.specials.randomElement(using: &generator) ?? "a" })
            let written = Quoting.write(value, style: style)
            #expect(Quoting.read(written, style: style) == value, "\(name) \(generator)")
        }
    }

    @Test("writes one balanced region a scanner reads whole, except shell single quotes which concatenate")
    func writtenValueScansAsOneRegion() {
        for (name, style) in Self.styles where style != .shellSingle {
            let written = Quoting.write("a'b\"c\\d\ne", style: style)
            #expect(Quoting.scan(written, style: style) == [written.startIndex..<written.endIndex], "\(name)")
        }
    }

    @Test(
        "writes each language's own escapes",
        arguments: [
            ("o'brien", QuoteStyle.sql, "'o''brien'"),
            ("it's", .shellSingle, "'it'\\''s'"),
            ("$HOME `x`", .shellDouble, "\"\\$HOME \\`x\\`\""),
            ("a\"b\n\u{1}", .json, "\"a\\\"b\\n\\u0001\""),
            ("a\0\u{1F}", .swift, "\"a\\0\\u{1f}\""),
            ("tab\there", .python, "\"tab\\there\""),
        ])
    func writesLanguageEscapes(value: String, style: QuoteStyle, expected: String) {
        #expect(Quoting.write(value, style: style) == expected)
    }

    @Test("finds balanced regions and yields none for an unbalanced opener")
    func scanRegions() {
        let text = "select 'o''brien', 'x' from t where a = 'open"
        let regions = Quoting.scan(text, style: .sql).map { String(text[$0]) }
        #expect(regions == ["'o''brien'", "'x'"])
        #expect(Quoting.scan("say \"half", style: .json).isEmpty)
    }

    @Test("refuses text that is not one quoted value")
    func readRefusesMalformed() {
        #expect(Quoting.read("abc", style: .json) == nil)
        #expect(Quoting.read("\"", style: .json) == nil)
        #expect(Quoting.read("'a'b'", style: .sql) == nil)
    }

    @Test("reports no quote, a closed quote, or one left open")
    func openingKinds() {
        let text = "x \"a\\\"b\" 'c"
        #expect(Quoting.opening(in: text, at: text.startIndex, styles: QuoteStyle.sourceStrings) == .none)
        let double = text.index(text.startIndex, offsetBy: 2)
        #expect(
            Quoting.opening(in: text, at: double, styles: QuoteStyle.sourceStrings)
                == .closed(end: text.index(double, offsetBy: 6)))
        let single = text.index(text.startIndex, offsetBy: 9)
        #expect(Quoting.opening(in: text, at: single, styles: QuoteStyle.sourceStrings) == .unclosed)
    }
}
