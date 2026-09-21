// Tests that the shipped Info.plist keeps the updater's archive check switched on.

import Foundation
import Testing

/// Reads `Resources/Uttrflow-Info.plist` as it ships, so removing a key fails here and not in a release.
@Suite("The updater's configuration")
struct UpdateConfigurationTests {
    /// The shipped Info.plist as a dictionary.
    private func shippedInfo() throws -> [String: Any] {
        let plist = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()  // UttrflowTests
            .deletingLastPathComponent()  // Tests
            .deletingLastPathComponent()  // package root
            .appending(path: "Resources/Uttrflow-Info.plist")
        let data = try Data(contentsOf: plist)
        return try #require(
            try PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any])
    }

    @Test("verifies an update archive against the EdDSA key before it is unpacked")
    func verifiesBeforeExtraction() throws {
        let info = try shippedInfo()
        #expect(info["SUVerifyUpdateBeforeExtraction"] as? Bool == true)
    }

    @Test("carries a real EdDSA public key and an https feed")
    func carriesTheKeyAndFeed() throws {
        let info = try shippedInfo()
        let key = try #require(info["SUPublicEDKey"] as? String)
        // The public half of the release signing key; changing it strands every installed copy.
        #expect(key == "apWgly8fYgdo1U2MUj56SuqUqZ4QHv5GRZIbuLT0PGE=")
        #expect(Data(base64Encoded: key)?.count == 32, "an Ed25519 public key is 32 bytes")
        let feed = try #require((info["SUFeedURL"] as? String).flatMap(URL.init(string:)))
        #expect(feed.scheme == "https")
    }
}
