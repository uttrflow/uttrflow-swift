// Tokenises a suggestion prompt the way the chat template does, paying only for the lines that changed. See `Docs/performance-suggestions.md`.
import Foundation
private import Synchronization
import UttrflowCore

/// One token the tokenizer splits out before anything else, as `tokenizer.json` declares it.
struct AddedToken: Equatable, Sendable, Decodable {
    let content: String
    /// Whether the token swallows the whitespace before it, which makes a line break no boundary.
    let lstrip: Bool
    /// Whether the token swallows the whitespace after it.
    let rstrip: Bool

    init(content: String, lstrip: Bool = false, rstrip: Bool = false) {
        self.content = content
        self.lstrip = lstrip
        self.rstrip = rstrip
    }

    /// Reads only the added tokens out of a `tokenizer.json`, or nothing when it has none.
    static func read(fromTokenizerFile url: URL) -> [AddedToken]? {
        struct File: Decodable {
            let tokens: [AddedToken]
            enum CodingKeys: String, CodingKey { case tokens = "added_tokens" }
        }
        guard let data = try? Data(contentsOf: url, options: .mappedIfSafe) else { return nil }
        return try? JSONDecoder().decode(File.self, from: data).tokens
    }
}

/// The chat template's tokens for a message, built from a frame read once and each line of the message read once.
final class PromptTokens: Sendable {
    /// The template's tokens before the message, which end on an added token.
    let prefix: [Int]
    /// The template's tokens after the message, which begin on an added token.
    let suffix: [Int]
    /// Whether the template trims whitespace and newlines off the message before placing it.
    let trims: Bool
    /// A first character of the message that would join an added token across the frame, sending the pass the long way.
    private let joinsPrefix: Set<Unicode.Scalar>
    /// A last character of the message that would join an added token across the frame.
    private let joinsSuffix: Set<Unicode.Scalar>
    /// Each line's tokens by its exact bytes, since Swift calls two spellings of "é" equal and the tokenizer does not.
    private let lines = Mutex(BoundedCache<[UInt8], [Int]>(capacity: PromptTokens.lineCapacity))
    /// How many characters and calls went to the tokenizer, so a test can see what a pass paid for.
    private let counts = Mutex<Tally>(Tally())

    /// The lines kept at once, the least recently used dropped first, which is a few screens' worth.
    static let lineCapacity = 512

    /// What went to the tokenizer since the frame was read.
    struct Tally: Equatable, Sendable {
        var encodes = 0
        var characters = 0
    }

    var tally: Tally { counts.withLock { $0 } }

    /// Reads the frame through `render` and proves it on probe messages, or nothing when the tokenizer's added tokens or the template make lines no boundary.
    init?(
        addedTokens: [AddedToken], render: (String) async throws -> [Int], encode: (String) -> [Int],
        tokenText: (Int) -> String?
    ) async {
        let contents = addedTokens.map(\.content)
        let exact = Set(addedTokens.map { Array($0.content.utf8) })
        // A line break is a hard boundary only when it is an added token of its own and no added token runs past it.
        guard exact.contains(Array("\n".utf8)), !addedTokens.contains(where: { $0.lstrip || $0.rstrip }),
            contents.allSatisfy({
                !$0.unicodeScalars.contains("\n") || $0.unicodeScalars.allSatisfy { $0 == "\n" }
            })
        else { return nil }
        guard let first = try? await render("alpha"), let second = try? await render("omega bravo charlie")
        else {
            return nil
        }
        let shared = zip(first, second).prefix { $0 == $1 }.count
        let sharedEnd = zip(first.reversed(), second.reversed()).prefix { $0 == $1 }.count
        guard shared > 0, sharedEnd > 0, shared + sharedEnd < min(first.count, second.count),
            let before = tokenText(first[shared - 1]), exact.contains(Array(before.utf8)),
            let after = tokenText(first[first.count - sharedEnd]), exact.contains(Array(after.utf8))
        else { return nil }
        let prefix = Array(first[..<shared])
        let suffix = Array(first.suffix(sharedEnd))
        // A padded probe says whether the template trims the message, and every probe must come back token for token.
        let padded = "  alpha beta \n"
        guard let paddedTokens = try? await render(padded) else { return nil }
        let trims = paddedTokens == prefix + encode(Self.trimmed(padded)) + suffix
        let joinsPrefix = Self.joining(after: before, among: contents)
        let joinsSuffix = Self.joining(before: after, among: contents)
        // Probes open and close on letters, digits, marks and space markers, which run on into any frame text that is not an added token.
        let probes = [
            "alpha", "omega bravo charlie", padded, "one\n\ntwo three\nfour", "alpha.", "7 ▁x▁", ">x<", "x y",
        ]
        for probe in probes {
            let core = trims ? Self.trimmed(probe) : probe
            guard let first = core.unicodeScalars.first, let last = core.unicodeScalars.last,
                !joinsPrefix.contains(first), !joinsSuffix.contains(last)
            else { continue }
            let chunked = Self.chunks(of: core).flatMap(encode)
            guard (try? await render(probe)) == prefix + chunked + suffix else { return nil }
        }
        self.prefix = prefix
        self.suffix = suffix
        self.trims = trims
        self.joinsPrefix = joinsPrefix
        self.joinsSuffix = joinsSuffix
    }

    /// The whole prompt's tokens for `message`, or nothing when its first or last character could join the frame's added token.
    func tokens(for message: String, encode: (String) -> [Int]) -> [Int]? {
        let core = trims ? Self.trimmed(message) : message
        guard let first = core.unicodeScalars.first, let last = core.unicodeScalars.last,
            !joinsPrefix.contains(first), !joinsSuffix.contains(last)
        else { return nil }
        var tokens = prefix
        for chunk in Self.chunks(of: core) {
            tokens += line(chunk, encode: encode)
        }
        return tokens + suffix
    }

    /// Drops every line read from what the person wrote, keeping the template's frame.
    func forgetEverything() {
        lines.withLock { $0.forgetEverything() }
    }

    /// One line's tokens, read from the cache or from the tokenizer.
    private func line(_ chunk: String, encode: (String) -> [Int]) -> [Int] {
        let key = Array(chunk.utf8)
        if let known = lines.withLock({ $0.value(for: key) }) { return known }
        let tokens = encode(chunk)
        counts.withLock {
            $0.encodes += 1
            $0.characters += chunk.count
        }
        lines.withLock { $0.store(tokens, for: key) }
        return tokens
    }

    /// The message cut after each run of line breaks, where no added token can cross.
    static func chunks(of text: String) -> [String] {
        var chunks: [String] = []
        var current = String.UnicodeScalarView()
        var previous: Unicode.Scalar?
        for scalar in text.unicodeScalars {
            if previous == "\n", scalar != "\n" {
                chunks.append(String(current))
                current = String.UnicodeScalarView()
            }
            current.append(scalar)
            previous = scalar
        }
        if !current.isEmpty { chunks.append(String(current)) }
        return chunks
    }

    /// The message as the template's `trim` filter leaves it.
    static func trimmed(_ text: String) -> String {
        text.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Every character that, following `token`, some added token contains, so the two would read as one.
    static func joining(after token: String, among contents: [String]) -> Set<Unicode.Scalar> {
        let lead = Array(token.unicodeScalars)
        var found: Set<Unicode.Scalar> = []
        for content in contents {
            let scalars = Array(content.unicodeScalars)
            guard scalars.count > lead.count else { continue }
            for start in 0..<(scalars.count - lead.count)
            where scalars[start..<(start + lead.count)].elementsEqual(lead) {
                found.insert(scalars[start + lead.count])
            }
        }
        return found
    }

    /// Every character that, before `token`, ends part of an added token whose rest runs into `token`.
    static func joining(before token: String, among contents: [String]) -> Set<Unicode.Scalar> {
        let tail = Array(token.unicodeScalars)
        var found: Set<Unicode.Scalar> = []
        for content in contents {
            let scalars = Array(content.unicodeScalars)
            for split in scalars.indices.dropFirst() {
                let rest = scalars[split...]
                if rest.starts(with: tail) || tail.starts(with: rest) { found.insert(scalars[split - 1]) }
            }
        }
        return found
    }
}
