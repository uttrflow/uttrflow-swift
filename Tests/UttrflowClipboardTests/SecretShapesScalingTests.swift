// Tests that reading a clip for a credential costs characters in proportion to its length.

import Testing

@testable import UttrflowClipboard

@Suite("Reading a clip for a credential costs a bounded number of reads per character")
struct SecretShapesScalingTests {
    /// The most reads any character may cost, which a reread of the rest of a run exceeds within a few kilobytes.
    static let readsPerCharacter = 64

    /// Runs with no break in them, each a shape a backtracking pattern rereads from every place a match could start.
    static let shapes: [String: String] = [
        "hex": "0123456789abcdef",
        "letters": "a",
        "dotted": "ab.c-",
        "header": "eyJa",
        "headers and stops": "eyJa.",
        "schemes": "ab+c",
        "scheme separators": "a://b:",
        "keyword assignments": "pwd=",
        "keywords in one word": "apikeytokenpassword",
        "keyword and spaces": "password  ",
        "quoted keywords": "pwd=\"pwd='",
        "separated keywords": "client-secret=",
        "blank lines": "\n",
        "commas": "token=a, ",
    ]

    private static func text(_ unit: String, length: Int) -> String {
        String(String(repeating: unit, count: length / unit.count + 1).prefix(length))
    }

    /// The characters the readers take over this text, with a line that does not end where a value does.
    private static func charactersRead(_ text: String) -> Int {
        let tally = ScanTally()
        SecretShapes.$tally.withValue(tally) {
            _ = SecretShapes.hasJSONWebToken(text)
            _ = SecretShapes.hasCredentialledURL(text)
            _ = SecretShapes.hasNamedSecret(text)
        }
        return tally.count
    }

    @Test(
        "Each shape costs at most a fixed number of reads per character, at every length",
        arguments: shapes.keys.sorted())
    func boundedPerCharacter(shape: String) throws {
        let unit = try #require(Self.shapes[shape])
        for length in [1_000, 16_000, 64_000] {
            // A trailing word keeps every line from ending at a value, so nothing stops the reading early.
            let text = Self.text(unit, length: length) + " x"
            let read = Self.charactersRead(text)
            #expect(
                read <= Self.readsPerCharacter * text.count,
                "\(shape): \(text.count) characters took \(read) reads")
        }
    }

    @Test(
        "Sixty-four times the text costs at most sixty-four times the reads, plus a little",
        arguments: shapes.keys.sorted())
    func growsLinearly(shape: String) throws {
        let unit = try #require(Self.shapes[shape])
        let short = Self.charactersRead(Self.text(unit, length: 1_000) + " x")
        let long = Self.charactersRead(Self.text(unit, length: 64_000) + " x")
        #expect(long <= 64 * short + 64 * Self.readsPerCharacter, "\(shape): \(short) reads became \(long)")
    }

    @Test("A two-megabyte clip, the largest the watcher keeps, costs no more per character than a small one")
    func largestClip() {
        let text = Self.text("pwd=eyJa://b:", length: 2_000_000) + " x"
        #expect(Self.charactersRead(text) <= Self.readsPerCharacter * text.count)
    }

    @Test("A secret after a long run is still found")
    func findsPastTheRun() {
        let run = Self.text("pwd=", length: 64_000)
        #expect(SecretShapes.hasNamedSecret(run + "\npassword=hunter2"))
        #expect(SecretShapes.hasJSONWebToken(Self.text("eyJa", length: 64_000) + ".b."))
        #expect(SecretShapes.hasCredentialledURL(String(repeating: "a://b:", count: 10_000) + "c@d"))
    }
}
