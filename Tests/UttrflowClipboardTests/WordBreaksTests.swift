// Tests that the word boundaries the secret readers ask about are the ones `\b` draws over the whole text.

import Foundation
import Testing

@testable import UttrflowClipboard
@testable import UttrflowCore
import UttrflowTestSupport

/// `WordBreaks` stands for the `\b` in the named-secret pattern, so it is measured against `\b` itself.
@Suite("The word boundaries the secret readers find are the ones `\\b` draws")
struct WordBreaksTests {
    nonisolated(unsafe) static let boundary = #/\b/#

    /// Text on every edge the word rules draw: ASCII, digits, underscores, marks, emoji and scripts written without spaces.
    static let table: [String] = [
        "api_key=abc123", "API-KEY: x", "password = \"hunter2\"", "x.password=1", "3.14 and 1,000",
        "snake_case_name", "camelCaseName", "_leading and trailing_", "  spaced  out  ", "tab\there",
        "line\nbreak\r\nand\rreturn", "e\u{301}te\u{301}", "cafe\u{301} au lait", "\u{301}lone mark",
        "naïve résumé", "😀 emoji 😀", "👩‍👩‍👧 family", "🇺🇸🇬🇧 flags", "a😀b", "日本語のテキスト",
        "中文字符 mixed with English", "カタカナ", "한국어 text", "ก้าวไปข้างหน้า", "don't can't",
        "U.S.A. e.g.", "a:b;c,d", "a: b", "https://example.com/path", "x\u{200D}y", "\u{FEFF}bom",
        "٣٤٥ arabic digits", "٣.٤", "½ fraction", "\u{212A}elvin", "api_\u{212A}ey=abc123", "a\u{A0}b",
        "co-op", "e.g.x", "3,000.50", "a\u{0}b", "\u{37E}x", "x\u{0B}y", "pwd=\"\u{301}abc",
        "password=\"a\r\nb\"", "token= 'x'\u{2028}", "secret=abc;\u{85}", "DB_PASSWORD=a1",
        "b\u{301}Password=a1", "tPassword=1", "f();", "end.", "", "a", " ", "\u{301}",
    ]

    /// Pieces of every shape the readers meet, to be strung together at random.
    static let pieces: [String] = [
        "a", "Z", "0", "9", "_", "-", ".", ":", "=", ";", ",", "\"", "'", " ", "\t", "\n", "\r\n",
        "\r", "\u{301}", "\u{200D}", "😀", "🇺🇸", "日", "語", "é", "\u{212A}", "\u{A0}", "½", "٣",
        "\u{FEFF}", "\u{0}", "\u{2028}", "\u{85}", "\u{37E}", "\u{0B}", "password", "pwd", "api_key",
        "x", "'s", "()", "//", "ก", "้",
    ]

    /// Every place `\b` stands in the whole text, read with the context on both sides of it.
    private static func drawnByPattern(_ text: String) -> Set<String.Index> {
        Set(text.matches(of: boundary).map(\.range.lowerBound))
    }

    /// Where `WordBreaks` disagrees with `\b`, asked at every character boundary in order, named by offset.
    private static func disagreements(_ text: String, floorFollows: Bool) -> [String] {
        let drawn = drawnByPattern(text)
        var breaks = WordBreaks(text)
        var found: [String] = []
        var index = text.startIndex
        while true {
            let answered = breaks.isBoundary(index, from: floorFollows ? index : text.startIndex)
            if answered != drawn.contains(index) {
                let offset = text.distance(from: text.startIndex, to: index)
                found.append("\(text.debugDescription) at \(offset): answered \(answered)")
            }
            guard index < text.endIndex else { break }
            index = text.index(after: index)
        }
        return found
    }

    @Test("Every awkward text, asked from the start, reads as `\\b` does", arguments: table)
    func awkwardTextFromTheStart(_ text: String) {
        #expect(Self.disagreements(text, floorFollows: false).isEmpty)
    }

    @Test("Every awkward text, asked with the floor at the question, reads as `\\b` does", arguments: table)
    func awkwardTextWithARisingFloor(_ text: String) {
        #expect(Self.disagreements(text, floorFollows: true).isEmpty)
    }

    @Test("Random strings of those pieces read as `\\b` does", arguments: OracleSweep.seeds(4))
    func randomStrings(seed: Int) async {
        let failures = await offTheTestPool {
            var random = Seeded(seed: 486_000 + seed)
            var failures: [String] = []
            for _ in 0..<OracleSweep.strings(5_000) {
                var text = ""
                for _ in 0..<Int.random(in: 0...14, using: &random) {
                    if random.chance(1.0 / 10),
                        let scalar = Unicode.Scalar(UInt32.random(in: 0...0x2FFF, using: &random))
                    {
                        text.unicodeScalars.append(scalar)
                    } else {
                        text += random.pick(Self.pieces)
                    }
                }
                let found =
                    Self.disagreements(text, floorFollows: random.chance(0.5))
                if !found.isEmpty, failures.count < 20 { failures.append(contentsOf: found) }
            }
            return failures
        }
        #expect(failures.isEmpty, "\(failures)")
    }

    /// Every ASCII character, because the fast path decides a window of them from the rules instead of from the pattern.
    static let ascii: [String] = (0..<128).map { String(UnicodeScalar(UInt8($0))) }

    /// Two members of every ASCII word class where the class has two, so a string over these meets every pair of classes.
    static let classes: [String] = [
        "a", "Z", "0", "9", "_", ":", ".", "'", ",", ";", " ", "-", "\n",
    ]

    /// One member of every ASCII word class, to stand either side of a character under test.
    static let representatives: [String] = ["a", "0", "_", ":", ".", ",", " ", "-"]

    /// The string at `position` in the ordering of every `length`-character string over `alphabet`.
    private static func string(at position: Int, length: Int, over alphabet: [String]) -> String {
        var remaining = position
        var built = ""
        for _ in 0..<length {
            built += alphabet[remaining % alphabet.count]
            remaining /= alphabet.count
        }
        return built
    }

    /// How many of the strings to read: all of them in the sweep, every twenty-fifth by default.
    private static var step: Int { OracleSweep.isFull ? 1 : OracleSweep.sampleDivisor }

    /// The first twenty places one of these strings is read differently from `\b`, asked with each floor in turn.
    private static func firstDisagreements(_ count: Int, _ text: (Int) -> String) -> [String] {
        var failures: [String] = []
        for position in Swift.stride(from: 0, to: count, by: step) where failures.count < 20 {
            let built = text(position)
            failures.append(contentsOf: disagreements(built, floorFollows: position.isMultiple(of: 2)))
        }
        return failures
    }

    @Test("Every ASCII string of up to three characters reads as `\\b` does", arguments: 1...3)
    func everyShortASCIIString(_ length: Int) async {
        let count = Int(pow(128.0, Double(length)))
        let failures = await offTheTestPool {
            Self.firstDisagreements(count) { Self.string(at: $0, length: length, over: Self.ascii) }
        }
        #expect(failures.isEmpty, "\(failures)")
    }

    @Test("Every five-character string over two members of each word class reads as `\\b` does")
    func everyStringOverTheClasses() async {
        let count = Int(pow(Double(Self.classes.count), 5.0))
        let failures = await offTheTestPool {
            Self.firstDisagreements(count) { Self.string(at: $0, length: 5, over: Self.classes) }
        }
        #expect(failures.isEmpty, "\(failures)")
    }

    @Test(
        "Every ASCII character reads as `\\b` does in every four-character context",
        arguments: 0..<128)
    func everyASCIICharacterInContext(_ code: Int) async {
        let middle = String(UnicodeScalar(UInt8(code)))
        let contexts = Self.representatives.count * Self.representatives.count
        let failures = await offTheTestPool {
            Self.firstDisagreements(contexts * contexts) {
                Self.string(at: $0 / contexts, length: 2, over: Self.representatives) + middle
                    + Self.string(at: $0 % contexts, length: 2, over: Self.representatives)
            }
        }
        #expect(failures.isEmpty, "\(failures)")
    }

    @Test("A boundary already passed is answered again while the floor still allows it")
    func repeatedQuestions() {
        let text = "api_key=abc123"
        var breaks = WordBreaks(text)
        let keywordEnd = text.index(text.startIndex, offsetBy: 7)
        let atEnd = breaks.isBoundary(keywordEnd, from: text.startIndex)
        let atStart = breaks.isBoundary(text.startIndex, from: text.startIndex)
        let atEndAgain = breaks.isBoundary(keywordEnd, from: text.startIndex)
        #expect(atEnd)
        #expect(atStart)
        #expect(atEndAgain)
    }
}
