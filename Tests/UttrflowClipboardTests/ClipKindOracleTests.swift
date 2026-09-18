// Tests that the windowed, sampled classifier answers as the whole-clip classifier did, on a fixed sample unless `UTTRFLOW_ORACLE_SWEEP=1` asks for every seed in full.

import Foundation
import Testing

@testable import UttrflowClipboard

/// Every fixture is invented, and each credential shape is assembled from pieces so no scanner matches the source.
@Suite("The windowed classifier answers as the whole-clip classifier did", .serialized)
struct ClipKindOracleTests {
    /// Lines of everyday clips, drawn from to build realistic ones.
    static let lines: [String] = [
        "import Foundation", "struct Config: Codable {", "    let name: String", "    var retries: Int = 3",
        "    func load(from url: URL) throws -> Data {", "        return try Data(contentsOf: url)", "    }",
        "}",
        "const total = values.reduce((a, b) => a + b, 0);", "if (total > limit && !done) {",
        "  console.log(`over by ${total - limit}`);", "def parse(line):",
        "    return [x.strip() for x in line]",
        "SELECT id, name FROM users WHERE active = 1;", "git commit -m \"wip\" && git push",
        "The clipboard keeps what you copied and shows it again when the panel opens.",
        "Meet at 4pm, then dinner: Italian.", "Remember the invoice; it is due on Friday.",
        "2026-09-14T10:00:01.123Z INFO [worker-3] request id=48213 path=/api/items status=200 took=12ms",
        "1042,north river,Lakeside,4821.50,2026-09-14",
        "0001f2a0: 4f2a 9c11 e0b3 77d2 0a6f 3c58  O*....w..o<X",
        "QmFzZTY0IGlzIGEgd2F5IHRvIHdyaXRlIGJ5dGVzIGFzIHRleHQgdGhhdCBzdXJ2aXZlcyBjb3B5aW5n",
        "function a(e,t){for(var n=0;n<e.length;n++)if(e[n]===t)return n;return-1};", "  - a list item",
        "# A heading", "// a comment", "Café au lait, naïve résumé — “quoted”", "日本語のテキストです。", "👍🏽 done",
        "", "\t", "order 4000 1234 5678 9011 shipped", "the task-list and the sk-docs mention AKIA",
    ]

    /// A clip of a few to a few hundred lines, sometimes with a planted secret or a near-miss spliced in.
    private static func realisticText(_ random: inout Seeded) -> String {
        var built: [String] = []
        for _ in 0..<Int.random(in: 1...(random.chance(0.05) ? 200 : 12), using: &random) {
            built.append(random.pick(lines))
        }
        if random.chance(0.3) {
            let at = Int.random(in: 0...built.count, using: &random)
            built.insert(SecretShapesOracleTests.plantedText(&random), at: at)
        }
        let separator = random.chance(0.1) ? " " : random.chance(0.1) ? "\r\n" : "\n"
        return built.joined(separator: separator)
    }

    /// Where the classifier and its whole-clip oracle disagree on this text, named.
    private static func disagreement(_ text: String) -> String? {
        let kind = ClipKindDetector.kind(of: text)
        let oracle = WholeClipDetector.kind(of: text)
        if kind != oracle { return "kind \(oracle) became \(kind)" }
        if SecretShapes.matches(text) != BacktrackingPatterns.matches(text) { return "secret" }
        return nil
    }

    private static func failures(seed: Int, count: Int, making make: (inout Seeded) -> String) -> [String] {
        var random = Seeded(seed: seed)
        var failures: [String] = []
        for _ in 0..<count {
            let text = make(&random)
            if let found = disagreement(text), failures.count < 20 {
                failures.append("\(found) on \(text.prefix(200).debugDescription)")
            }
        }
        return failures
    }

    @Test("Random text: 20,000 strings over four seeds in the full sweep", arguments: OracleSweep.seeds(4))
    func randomStrings(seed: Int) async {
        let failures = await offTheTestPool {
            Self.failures(
                seed: 460_000 + seed, count: OracleSweep.strings(5_000),
                making: SecretShapesOracleTests.randomText)
        }
        #expect(failures.isEmpty, "\(failures)")
    }

    @Test(
        "Planted secrets and near-misses: 10,000 over two seeds in the full sweep",
        arguments: OracleSweep.seeds(2))
    func plantedSecrets(seed: Int) async {
        let failures = await offTheTestPool {
            Self.failures(
                seed: 461_000 + seed, count: OracleSweep.strings(5_000),
                making: SecretShapesOracleTests.plantedText)
        }
        #expect(failures.isEmpty, "\(failures)")
    }

    @Test(
        "Realistic clips below the sample threshold: 20,000 over four seeds in the full sweep",
        arguments: OracleSweep.seeds(4))
    func realisticClips(seed: Int) async {
        let failures = await offTheTestPool {
            Self.failures(seed: 462_000 + seed, count: OracleSweep.strings(5_000), making: Self.realisticText)
        }
        #expect(failures.isEmpty, "\(failures)")
    }

    @Test(
        "Every planted secret the whole-clip reading finds is found in the middle of a quarter-megabyte clip")
    func plantedDeepInALargeClip() async {
        // Whole lines, so the secret's line starts where it would in the small context the oracle reads.
        let unit = Self.lines[15] + "\n"
        let filler = String(repeating: unit, count: 1_600)
        let context = String(repeating: unit, count: 4)
        let missed = await offTheTestPool {
            SecretShapesOracleTests.planted.filter { secret in
                BacktrackingPatterns.matches(context + secret + "\n" + context)
                    && ClipKindDetector.kind(of: filler + secret + "\n" + filler) != .secret
            }
        }
        #expect(missed.isEmpty, "\(missed)")
    }

    @Test(
        "A vendor key or card number deep in a two-megabyte clip is found, at a line start or inside a line")
    func deepInTheLargestClip() async {
        let filler = String(repeating: Self.lines[18] + "\n", count: 10_500)
        let key = "gh" + "p_" + String(repeating: "A1b2C3d4", count: 3)
        let card = "4111 " + "1111 " + "1111 " + "1111"
        let kinds = await offTheTestPool {
            [
                filler + key + "\n" + filler, filler + "token is " + key + " ok\n" + filler,
                filler + "card " + card + " ok\n" + filler, filler + filler,
            ].map(ClipKindDetector.kind(of:))
        }
        #expect(kinds == [.secret, .secret, .secret, .text])
    }

    @Test(
        "The vendor-key and card windows agree with the whole-clip patterns where a window's edge could matter"
    )
    func windowEdges() {
        let segment = String(repeating: "a", count: 300)
        let sendGrid = "SG" + "." + segment + "." + String(repeating: "b", count: 16)
        let cases = [
            sendGrid, "x " + sendGrid, "SG" + ".SG" + ".SG" + "." + segment,
            sendGrid.replacingOccurrences(of: ".b", with: ". b"),
            String(repeating: "sk" + "-", count: 400) + String(repeating: "c", count: 16),
            String(repeating: "sk" + "-abc ", count: 200),
            "sk" + "-" + String(repeating: "d", count: 15) + "\u{301}",
            "\u{600}sk" + "-" + String(repeating: "d", count: 16),
            "dop" + "_v1_" + String(repeating: "ab", count: 20),
            String(repeating: "x", count: 90) + "dop" + "_v1_" + String(repeating: "ab", count: 20),
            String(repeating: "1", count: 12) + "3", "4111111111111111\u{301}", "\u{600}4111111111111111",
            "12 34 56 78 90 12 34 56", String(repeating: "4111 1111 1111 1111 ", count: 3),
            "4111-1111-1111-1111-", "x4111111111111111", "4111111111111111.5", "é4111 1111 1111 1111é",
        ]
        for text in cases {
            #expect(
                SecretShapes.matches(text) == BacktrackingPatterns.matches(text), "\(text.debugDescription)")
            #expect(
                CardNumberShape.matches(text) == BacktrackingPatterns.hasCardNumber(text),
                "\(text.debugDescription)")
        }
    }

    @Test("A clip bridged from Objective-C is read through a contiguous copy with the same answer")
    func bridgedText() {
        for text in [
            "password" + "=abc123def456", Self.lines[0] + "\n" + Self.lines[1], "4111 " + "1111 1111 1111",
        ] {
            let bridged = NSString(string: text) as String
            #expect(SecretShapes.matches(bridged) == SecretShapes.matches(text))
            #expect(
                ClipBytes.containsAny(bridged, ["1111", "abc"])
                    == ClipBytes.containsAny(text, ["1111", "abc"]))
            #expect(CodeShapes.isShellCommand(bridged) == CodeShapes.isShellCommand(text))
        }
    }

    @Test("The ASCII readings of the statistical rule and the shell rule answer as the character readings do")
    func asciiReadings() async {
        let failures = await offTheTestPool {
            var random = Seeded(seed: 463_000)
            var failures: [String] = []
            let alphabet = Array("abcXYZ019+/=_-./~:| &;$\t \u{0B}\r\ngitsudols")
            for _ in 0..<OracleSweep.strings(20_000) {
                var text = ""
                for _ in 0..<Int.random(in: 0...60, using: &random) { text.append(random.pick(alphabet)) }
                if random.chance(0.3) {
                    text = random.pick(["./", "$ ", "git ", "a1B2c3D4e5F6g7H8i9J0kLmN "]) + text
                }
                if SecretShapes.hasHighEntropyToken(text) != SecretShapes.hasHighEntropyTokenByCharacter(text)
                    || CodeShapes.isShellCommand(text) != CodeShapes.isShellCommandByCharacter(text),
                    failures.count < 20
                {
                    failures.append(text.debugDescription)
                }
            }
            return failures
        }
        #expect(failures.isEmpty, "\(failures)")
    }
}

/// `ClipKindDetector.kind(of:)` as it read before the windows and the sample: every pattern over the whole clip.
enum WholeClipDetector {
    static func kind(of text: String) -> ClipKind {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return .text }
        if BacktrackingPatterns.matches(trimmed) { return .secret }
        if ColourShape.matches(trimmed) { return .colour }
        if LinkShape.matches(trimmed) { return .link }
        if PathShape.matches(trimmed) { return .filePath }
        if isCode(trimmed) { return .code }
        return .text
    }

    private static func isCode(_ text: String) -> Bool {
        if text.hasPrefix("#!") { return true }
        if String(text.prefix(while: { !$0.isNewline })).wholeMatch(of: CodeShapes.importHeader) != nil {
            return true
        }
        if isShellCommand(text) { return true }
        let signals = [
            text.contains("{") && text.contains("}"), CodeShapes.hasStatementEnding(text),
            CodeShapes.isIndented(text), text.firstMatch(of: CodeShapes.declaration) != nil,
            text.firstMatch(of: CodeShapes.controlFlow) != nil,
            text.firstMatch(of: CodeShapes.codeOperator) != nil,
            text.firstMatch(of: CodeShapes.invocation) != nil,
            text.firstMatch(of: CodeShapes.commentLine) != nil,
            text.firstMatch(of: CodeShapes.query) != nil,
            text.firstMatch(of: CodeShapes.shellFragment) != nil,
        ]
        return signals.count(where: { $0 }) >= 2
    }

    private static func isShellCommand(_ text: String) -> Bool {
        guard !text.contains(where: \.isNewline) else { return false }
        if text.hasPrefix("$ ") || text.hasPrefix("./") { return true }
        return CodeShapes.isShellCommandByCharacter(text)
    }
}
