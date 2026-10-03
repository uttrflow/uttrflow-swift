import Testing

@testable import UttrflowCore

@Suite("TechnicalToken")
struct TechnicalTokenTests {
    static let technical: [(String, TechnicalToken)] = [
        ("https://example.com/docs", .url), ("http://example.test", .url),
        ("ftp://files.example.com", .url), ("ssh://host.example.com:22", .url),
        ("Https://example.com/docs.", .url), ("(https://a.example)", .url),
        ("src/app/main.swift", .path), ("lib/core/util", .path), ("app/main.swift", .path),
        ("Sources/Core/a.swift,", .path), ("a/b/c", .path), ("docs/readme.md", .path),
        ("config.yaml", .fileName), ("main.swift", .fileName), ("package.json", .fileName),
        ("README.md", .fileName), ("setup.py", .fileName), ("index.html.", .fileName),
        ("my_file.txt", .fileName), ("build-log.txt", .fileName),
        ("example.com", .hostname), ("api.example.io", .hostname), ("docs.example.dev", .hostname),
        ("mail.example.org", .hostname), ("example.co.uk", .hostname), ("status.example.app", .hostname),
        ("v2.3.1", .version), ("2.3.1", .version), ("V10.0", .version), ("1.2", .version),
        ("user_id", .identifier), ("node_modules", .identifier), ("x86_64", .identifier),
        ("k8s", .identifier), ("i18n", .identifier), ("snake_case_name", .identifier),
        ("a11y", .identifier), ("max_retries:", .identifier), ("abc_123", .identifier), ("w3c", .identifier),
    ]

    static let ordinary: [String] = [
        "hello", "Hello.", "and/or", "either/or", "e.g.", "i.e.", "U.S.", "a.m.", "Mr.", "Dr.",
        "okay.thanks", "well.so", "it's", "don't", "mp3", "4th", "2024", "??", "::", "co-op",
    ]

    @Test("a technical token is classified by its kind", arguments: technical)
    func classifies(token: String, kind: TechnicalToken) {
        #expect(TechnicalToken.classify(token) == kind)
    }

    @Test("an ordinary word is not a technical token", arguments: ordinary)
    func leavesOrdinary(word: String) {
        #expect(TechnicalToken.classify(word) == nil)
    }

    @Test("a technical token keeps the case it was written in", arguments: technical.map(\.0))
    func keepsCase(token: String) {
        #expect(WordShape.capitalised(token) == token)
        #expect(WordShape.lowercased(token) == token)
    }
}
