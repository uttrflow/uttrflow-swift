import Testing

@testable import UttrflowClipboard
@testable import UttrflowCore

@Suite("Secret shaped identifiers")
struct SecretIdentifierContextTests {
    @Test("leaves quoted UUIDs and contextual hashes readable")
    func identifiersAndHashes() {
        let uuid = "aef383b1-53aa-42a2-b0df-8f48935cc7f6"
        let secondUUID = "99512f9b-a5c5-4507-a498-a66ccae430d7"
        let commit = String(repeating: "a1b2c3d4", count: 5)
        let sha256 = String(repeating: "0123456789abcdef", count: 4)
        let ordinary = [
            #"{"id": "\#(uuid)", "name": "Ravi", "active": true}"#,
            #"[{"id":"\#(uuid)"},{"id":"\#(secondUUID)"}]"#,
            #"{"commit":"\#(commit)","branch":"main"}"#,
            #"{"sha256": "\#(sha256)", "size": 20480}"#,
            "The build is at \(commit) and passed",
        ]

        for text in ordinary {
            #expect(!SecretShapes.matches(text), "Masked ordinary identifier: \(text)")
            #expect(!SecretShapes.hasHighEntropyToken(text))
            #expect(!SecretShapes.hasHighEntropyTokenByCharacter(text))
            #expect(ClipKindDetector.kind(of: text) != .secret)
        }
    }

    @Test("keeps a generated JSON API key secret")
    func generatedAPIKey() {
        let key = ["9f2b7c4e1a8d3f6b", "Qv7RkT2mXeL9pAz4", "NbHc8FwJ"].joined()
        let json = #"{"api_key": "\#(key)"}"#
        #expect(key.count == 40)
        #expect(SecretShapes.matches(json))
        #expect(ClipKindDetector.kind(of: json) == .secret)
    }

    @Test("scans contextual digests in linear work as a clip grows")
    func contextualDigestScanScalesLinearly() {
        let digest = String(repeating: "a1b2c3d4", count: 5)
        func measured(_ count: Int) -> Int {
            let entry = "\"hash\":\"\(digest)\""
            let text = "{" + Array(repeating: entry, count: count).joined(separator: ", ") + "}"
            let tally = ScanTally()
            let isSecret = SecretShapes.$tally.withValue(tally) {
                SecretShapes.hasHighEntropyToken(text)
            }
            #expect(!isSecret)
            return tally.count
        }

        let small = measured(16)
        let large = measured(256)
        #expect(large <= 20 * small, "16x more digest entries took \(small) to \(large) reads")
    }
}
