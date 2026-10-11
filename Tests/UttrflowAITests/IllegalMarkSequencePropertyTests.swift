import Foundation
import Testing
import UttrflowTestSupport

@testable import UttrflowAI
@testable import UttrflowCore

/// Whatever the recogniser hands over, no destination's cleaned text carries a mark sequence that can never be legal.
@Suite("Illegal mark sequences")
struct IllegalMarkSequencePropertyTests {
    /// A shape of output no input may produce.
    enum Property: String, CaseIterable {
        case spaceAfterOpener, spaceBeforeCloser, spaceBeforeMark, adjacentMarks, lineStartsWithMark
        case unbalancedBrackets, stopAfterIllegalToken, notIdempotent
    }

    /// Failures that stand today, as destination and property with the issue that fixes each; the list only shrinks.
    static let knownFaults: [String: Int] = ["terminal notIdempotent": 7327]

    static let seeds = Seeded.seeds(0..<150)

    static let words = [
        "the", "meeting", "is", "at", "and", "of", "we", "will", "ship", "Monday", "42", "3.5", "Dr.", "e.g.",
        "etc.", "p.m.", "OK", "hello", "world", "a", "to", "my", "their",
    ]
    static let marks = [",", ".", "?", "!", ";", ":", "...", "?!"]
    static let wrappers = [("(", ")"), ("[", "]"), ("\u{201C}", "\u{201D}")]

    /// Recogniser-style text: words with marks stuck to them, and balanced bracket and quote spans.
    static func dictation(_ random: inout Seeded) -> [String] {
        var tokens: [String] = []
        var closers: [String] = []
        for _ in 0..<Int.random(in: 1...14, using: &random) {
            var token = random.pick(words)
            if random.chance(0.15) {
                let pair = random.pick(wrappers)
                token = pair.0 + token
                closers.append(pair.1)
            } else if let closer = closers.last, random.chance(0.3) {
                token += closer
                closers.removeLast()
            }
            // A recogniser never writes a second mark after an abbreviation's own stop, so the input is legal too.
            if random.chance(0.25), !token.hasSuffix(".") { token += random.pick(marks) }
            tokens.append(token)
        }
        if !tokens.isEmpty { tokens[tokens.count - 1] += closers.reversed().joined() }
        return tokens
    }

    static func clean(_ words: [String], in destination: Destination) -> (once: String, twice: String) {
        let app = AppContext()
        let situation = Situation(app: app, insertion: app.insertionPoint, destination: destination)
        let pipeline = CleaningPipeline.standard(
            for: .standard(for: destination), situation: situation)
        let once = pipeline.run(Draft(text: words.joined(separator: " "))).text
        return (once, pipeline.run(Draft(text: once)).text)
    }

    private static let clauseMarks: Set<Character> = [",", ".", "?", "!", ";", ":"]
    private static let openers: Set<Character> = ["(", "[", "{", "\u{201C}"]
    private static let closers: Set<Character> = [")", "]", "}", "\u{201D}"]

    /// The properties `words` breaks when cleaned for `destination`.
    static func broken(
        _ words: [String], in destination: Destination,
        cleaning: (([String], Destination) -> (once: String, twice: String))? = nil
    ) -> Set<Property> {
        let (text, again) = cleaning?(words, destination) ?? clean(words, in: destination)
        var found = shapes(of: text, saidAs: words)
        if text != again { found.insert(.notIdempotent) }
        return found
    }

    /// The shape properties a finished text breaks; a stop counts as added unless `said` held that token.
    static func shapes(of text: String, saidAs said: [String]) -> Set<Property> {
        var found: Set<Property> = []
        let characters = Array(text)
        for (index, character) in characters.enumerated() {
            let next = index + 1 < characters.count ? characters[index + 1] : nil
            if openers.contains(character), next == " " { found.insert(.spaceAfterOpener) }
            if index > 0, characters[index - 1] == " " {
                if closers.contains(character) { found.insert(.spaceBeforeCloser) }
                if clauseMarks.contains(character), next.map({ !$0.isNumber && $0 != "." }) ?? true {
                    found.insert(.spaceBeforeMark)
                }
            }
        }
        for run in text.split(whereSeparator: { !Self.clauseMarks.contains($0) }) where run.count > 1 {
            if !["?!", "!?", "..."].contains(String(run)) { found.insert(.adjacentMarks) }
        }
        let flat = text.replacingOccurrences(of: "\n", with: " ")
        for (open, close) in wrappers {
            let opens = flat.filter { String($0) == open }.count
            let closes = flat.filter { String($0) == close }.count
            if opens != closes { found.insert(.unbalancedBrackets) }
        }
        for line in text.split(separator: "\n") {
            if let first = line.drop(while: { $0 == " " }).first, clauseMarks.contains(first) {
                found.insert(.lineStartsWithMark)
            }
        }
        let spoken = Set(said.map { $0.lowercased() })
        for token in text.split(whereSeparator: \.isWhitespace) {
            guard let last = token.last, last == "." || last == "?" || last == "!" else { continue }
            let core = String(token.dropLast())
            if MarkLegality.verdict(.stop, after: core) == .illegal, !spoken.contains(token.lowercased()) {
                found.insert(.stopAfterIllegalToken)
            }
        }
        return found
    }

    static func shrunk(
        _ words: [String], _ property: Property, in destination: Destination,
        cleaning: (([String], Destination) -> (once: String, twice: String))? = nil
    ) -> [String] {
        var current = words
        var index = 0
        while index < current.count {
            var smaller = current
            smaller.remove(at: index)
            if !smaller.isEmpty, broken(smaller, in: destination, cleaning: cleaning).contains(property) {
                current = smaller
            } else {
                index += 1
            }
        }
        return current
    }

    @Test("no destination writes an illegal mark sequence on generated recogniser text")
    func holds() {
        for destination in Destination.allCases {
            var reported: Set<Property> = Set(
                Property.allCases.filter { Self.knownFaults["\(destination.rawValue) \($0.rawValue)"] != nil }
            )
            for seed in Self.seeds {
                var random = Seeded(seed: seed)
                let words = Self.dictation(&random)
                for property in Self.broken(words, in: destination).subtracting(reported) {
                    reported.insert(property)
                    let smallest = Self.shrunk(words, property, in: destination)
                    let (once, twice) = Self.clean(smallest, in: destination)
                    Issue.record(
                        "\(destination.rawValue) breaks \(property.rawValue) at \(random): \"\(smallest.joined(separator: " "))\" gives \"\(once)\" then \"\(twice)\""
                    )
                }
            }
        }
    }

    @Test("each known fault still happens, so a fixed one leaves the list")
    func knownFaultsStillHappen() {
        for (name, issue) in Self.knownFaults {
            let parts = name.split(separator: " ").map(String.init)
            let destination = Destination(rawValue: parts[0])
            let property = Property(rawValue: parts[1])
            let happens = Self.seeds.contains { seed in
                var random = Seeded(seed: seed)
                return Self.broken(Self.dictation(&random), in: destination ?? .plain).contains(
                    property ?? .notIdempotent)
            }
            #expect(happens, "\(name) no longer happens: remove it from the list and close #\(issue)")
        }
    }

    @Test("a text with a space before a comma, a doubled stop and an unclosed bracket is caught")
    func catchesSeededDefects() {
        #expect(Self.properties(of: "we ship , now").contains(.spaceBeforeMark))
        #expect(Self.properties(of: "we ship.. now").contains(.adjacentMarks))
        #expect(Self.properties(of: "( we ship").contains(.spaceAfterOpener))
        #expect(Self.properties(of: "we ship ) now").contains(.spaceBeforeCloser))
        #expect(Self.properties(of: "we ship (now").contains(.unbalancedBrackets))
        #expect(Self.properties(of: ", we ship").contains(.lineStartsWithMark))
        #expect(Self.properties(of: "ship the. now").contains(.stopAfterIllegalToken))
    }

    /// The shape properties of a finished text, without running the pipeline.
    static func properties(of text: String) -> Set<Property> {
        shapes(of: text, saidAs: [])
    }
}
