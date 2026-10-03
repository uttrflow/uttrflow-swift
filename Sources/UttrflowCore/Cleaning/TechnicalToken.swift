import Foundation

/// What a single written token is when it is technical text whose case is not prose: see `Docs/cleanup.md`.
public enum TechnicalToken: Equatable, Sendable {
    case url
    case hostname
    case path
    case fileName
    case version
    case identifier

    /// The kind of technical token `text` is, read off its own core; nil for an ordinary word.
    public static func classify(_ text: String) -> TechnicalToken? {
        let core = WordShape(text).core
        guard core.contains(where: \.isLetter) || core.contains(where: \.isNumber) else { return nil }
        if isURL(core) { return .url }
        if isPath(core) { return .path }
        if let kind = dottedKind(core) { return kind }
        if isIdentifier(core) { return .identifier }
        return nil
    }

    /// Endings that make a dotted name a host; an unknown one is left as words rather than guessed at.
    public static let topLevels: Set<String> = [
        "com", "net", "org", "edu", "gov", "mil", "int", "info", "biz",
        "io", "co", "ai", "dev", "app", "me", "sh", "xyz", "tech", "online", "site", "store", "cloud",
        "in", "uk", "us", "ca", "au", "de", "fr", "nl", "es", "it", "jp", "cn", "br", "ru", "ie", "nz",
    ]

    /// File endings common enough that a dotted name ending on one is a file name.
    public static let fileExtensions: Set<String> = [
        "json", "txt", "md", "swift", "py", "js", "ts", "html", "css", "xml", "csv", "pdf",
        "yaml", "yml", "toml", "sh", "rb", "go", "rs", "kt", "java", "png", "jpg", "zip",
    ]

    private static func isURL(_ core: String) -> Bool {
        guard let range = core.range(of: "://") else { return false }
        let scheme = core[..<range.lowerBound]
        return !scheme.isEmpty && scheme.allSatisfy(\.isLetter) && range.upperBound < core.endIndex
    }

    /// Slash-joined segments: three or more, or two ending on a file name; "and/or" is two words.
    private static func isPath(_ core: String) -> Bool {
        let segments = core.split(separator: "/", omittingEmptySubsequences: false)
        guard segments.count >= 2, segments.allSatisfy({ !$0.isEmpty }) else { return false }
        return segments.count >= 3 || dottedKind(String(segments[segments.count - 1])) == .fileName
    }

    /// A version ("2.3.1", "v2.3"), a file name or a host, read from a dotted token's segments.
    private static func dottedKind(_ core: String) -> TechnicalToken? {
        let segments = core.split(separator: ".", omittingEmptySubsequences: false)
        guard segments.count >= 2, segments.allSatisfy({ !$0.isEmpty }) else { return nil }
        let numbered = [segments[0].drop(while: { $0 == "v" || $0 == "V" })] + segments.dropFirst()
        if numbered.allSatisfy({ !$0.isEmpty && $0.allSatisfy(\.isNumber) }) { return .version }
        guard segments.allSatisfy({ $0.allSatisfy { $0.isLetter || $0.isNumber || $0 == "_" || $0 == "-" } }),
            segments.dropLast().contains(where: { $0.count >= 2 })
        else { return nil }
        let ending = segments[segments.count - 1].lowercased()
        if fileExtensions.contains(ending) { return .fileName }
        if topLevels.contains(ending) { return .hostname }
        return nil
    }

    /// An underscore between letters or digits ("user_id"), or digits between letters ("k8s", "i18n").
    private static func isIdentifier(_ core: String) -> Bool {
        let characters = Array(core)
        let isWordy: (Character) -> Bool = { $0.isLetter || $0.isNumber }
        let underscored = characters.indices.dropFirst().dropLast().contains { index in
            characters[index] == "_" && isWordy(characters[index - 1]) && isWordy(characters[index + 1])
        }
        let runs = characters.split(whereSeparator: { !isWordy($0) }).flatMap(kindRuns)
        let numbered = zip(zip(runs, runs.dropFirst()), runs.dropFirst(2)).contains { pair, next in
            pair.0 && !pair.1 && next
        }
        return underscored || numbered
    }

    /// Whether each run of a word is letters (true) or digits (false), in order.
    private static func kindRuns(_ word: ArraySlice<Character>) -> [Bool] {
        word.reduce(into: []) { runs, character in
            if runs.last != character.isLetter { runs.append(character.isLetter) }
        }
    }
}
