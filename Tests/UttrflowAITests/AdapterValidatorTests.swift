import Foundation
import Testing

@testable import UttrflowAI
@testable import UttrflowCore

/// One invented answer and the caret text it is written between.
struct BalanceCase: Sendable, CustomTestStringConvertible {
    let output: String
    var preceding = ""
    var following = ""

    var testDescription: String { "\(preceding)|\(output)|\(following)" }
}

/// The bracket and quote balance check, against an invented corpus of broken answers and of correct fragments.
@Suite("AdapterValidator")
struct AdapterValidatorTests {
    static let malformed: [BalanceCase] = [
        BalanceCase(output: "print(name))"),
        BalanceCase(output: "items[0)"),
        BalanceCase(output: "foo(bar]"),
        BalanceCase(output: "}"),
        BalanceCase(output: "let s = \"hello"),
        BalanceCase(output: "SELECT * FROM users WHERE name = 'Bob"),
        BalanceCase(output: "echo \"done"),
        BalanceCase(output: "git commit -m \"fix typo"),
        BalanceCase(output: "map { $0 })"),
        BalanceCase(output: "dict[\"key)"),
        BalanceCase(output: "if (a && b)) {"),
        BalanceCase(output: "call(a, [b, c)]"),
        BalanceCase(output: "x = (1 + 2]"),
        BalanceCase(output: "grep 'error log"),
        BalanceCase(output: "run `make build"),
        BalanceCase(output: "SELECT count(*)) FROM t"),
        BalanceCase(output: "{\"name\": \"Ada\"}}"),
        BalanceCase(output: "{\"name\": \"Ada}"),
        BalanceCase(output: "arr[i]]"),
        BalanceCase(output: "ls -la)"),
        BalanceCase(output: "print(\"hi')"),
        BalanceCase(output: "a, b))", preceding: "foo("),
        BalanceCase(output: "]", preceding: "call(", following: ")"),
    ]

    static let wellFormed: [BalanceCase] = [
        BalanceCase(output: "print(name)"),
        BalanceCase(output: "items[0]"),
        BalanceCase(output: "WHERE id IN (1, 2"),
        BalanceCase(output: "OR b = 2)", preceding: "SELECT * FROM t WHERE (a = 1 "),
        BalanceCase(output: "let s = \"hello\""),
        BalanceCase(output: "echo \"it's done\""),
        BalanceCase(output: "git commit -m \"don't panic\""),
        BalanceCase(output: "name = 'O''Brien'"),
        BalanceCase(output: "echo don't"),
        BalanceCase(output: "hello world", preceding: "let s = \""),
        BalanceCase(output: "hello\" + name", preceding: "let s = \""),
        BalanceCase(output: "map { $0 * 2 }"),
        BalanceCase(output: "if (a && b) {"),
        BalanceCase(output: "{\"name\": \"Ada\"}"),
        BalanceCase(output: "path = \"C:\\\\temp\\\\\""),
        BalanceCase(output: "\"a \\\" b\""),
        BalanceCase(output: "\"hello", following: "\", world)"),
        BalanceCase(output: "arr[i][j]"),
        BalanceCase(output: "ls -la | grep \"log\""),
        BalanceCase(output: "foo(bar[0], baz{1})"),
        BalanceCase(output: "print(\") is a paren\")"),
        BalanceCase(output: "total)", preceding: "print(\"(\"\nsum("),
    ]

    @Test("refuses every broken answer in the corpus", arguments: malformed)
    func refusesBrokenAnswers(_ sample: BalanceCase) {
        let verdict = AdapterValidator.balance(
            of: sample.output, preceding: sample.preceding, following: sample.following)
        guard case .malformed = verdict else {
            Issue.record("accepted \(sample.testDescription)")
            return
        }
    }

    @Test("accepts every correct fragment in the corpus, a continued clause included", arguments: wellFormed)
    func acceptsCorrectFragments(_ sample: BalanceCase) {
        #expect(
            AdapterValidator.balance(
                of: sample.output, preceding: sample.preceding, following: sample.following) == .wellFormed)
    }

    @Test("both corpora hold at least twenty cases")
    func corporaAreLargeEnough() {
        #expect(Self.malformed.count >= 20)
        #expect(Self.wellFormed.count >= 20)
    }

    @Test("judges nothing where the screen says prose is written")
    func abstainsOutsideNotation() {
        func situation(_ destination: Destination, preceding: String) -> Situation {
            let app = AppContext(documentName: "Cache.swift", precedingText: preceding)
            return Situation(app: app, insertion: app.insertionPoint, destination: destination)
        }
        #expect(AdapterValidator.verdict(on: "fine)", in: situation(.document, preceding: "")) == .notApplicable)
        #expect(
            AdapterValidator.verdict(on: "fine)", in: situation(.codeEditor, preceding: "// ")) == .notApplicable)
        #expect(
            AdapterValidator.verdict(on: "fine)", in: situation(.codeEditor, preceding: "let x = "))
                == .malformed(reason: "closes ) that nothing opened"))
        #expect(AdapterValidator.verdict(on: "echo \"hi", in: situation(.terminal, preceding: "")) != .wellFormed)
    }

    @Test("checks a 300-word dictation in under 2 ms")
    func checksQuickly() {
        let output = Array(repeating: "call(items[0], \"name\")", count: 150).joined(separator: " ")
        #expect(output.split(separator: " ").count == 300)
        let clock = ContinuousClock()
        // The fastest of several runs, so a loaded machine's scheduling is not counted against the check.
        let fastest = (0..<20).map { _ in
            clock.measure { _ = AdapterValidator.balance(of: output, preceding: "", following: "") }
        }.min()
        #expect(fastest.map { $0 < .milliseconds(2) } == true)
    }
}
