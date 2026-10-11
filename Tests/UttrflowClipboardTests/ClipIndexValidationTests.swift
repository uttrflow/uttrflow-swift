// Temporary synthetic indexes exercise the write-time inspection boundary.

import CryptoKit
import Foundation
import Testing
import UttrflowCore

@testable import UttrflowClipboard

@Suite("Clipboard index inspection")
struct ClipIndexValidationTests {
    private struct Keys: StoreKeyProviding {
        let value: SymmetricKey
        func key(createIfMissing: Bool) throws -> SymmetricKey { value }
    }

    @Test("absent indexes remain writable")
    func absentIndex() throws {
        let folder = try TemporaryFolder()
        let url = folder.url.appending(path: "absent.json")
        #expect(try ClipIndexValidation.inspect(url, using: nil) == nil)
        #expect(!FileManager.default.fileExists(atPath: url.path))
    }

    @Test(
        "supported object and legacy-array payloads keep their bytes",
        arguments: [
            #"[]"#, #"{"version":1,"clips":[]}"#, #"{"version":2,"clips":[]}"#,
        ])
    func supportedPayload(_ json: String) throws {
        let folder = try TemporaryFolder()
        let url = folder.url.appending(path: "index.json")
        let data = Data(json.utf8)
        try data.write(to: url)
        #expect(try ClipIndexValidation.inspect(url, using: nil) == nil)
        #expect(try Data(contentsOf: url) == data)
    }

    @Test("future schemas are reported without inspecting or rewriting their fields")
    func futureSchema() throws {
        let folder = try TemporaryFolder()
        let url = folder.url.appending(path: "index.json")
        let data = Data(#"{"version":99,"futureField":{"keep":[1,2,3]}}"#.utf8)
        try data.write(to: url)
        #expect(try ClipIndexValidation.inspect(url, using: nil) == 99)
        #expect(try Data(contentsOf: url) == data)
    }

    @Test(
        "malformed supported payloads and unknown fields refuse replacement",
        arguments: [
            #"{"version":2}"#, #"{"version":"2","clips":[]}"#,
            #"{"version":2,"clips":[],"futureField":true}"#, #"[{}]"#,
            #"""
            {"version":2,"clips":[
            {"id":"00000000-0000-4000-8000-000000000001","text":"Synthetic row","kind":"text",
            "copiedAt":0,"futureField":true}]}
            """#,
            #"""
            {"version":2,"clips":[
            {"id":"00000000-0000-4000-8000-000000000001","text":"Synthetic row","kind":"text",
            "copiedAt":"invalid"}]}
            """#,
            #"{"version":2,"clips":["invalid"]}"#, "malformed JSON",
        ])
    func refusedPayload(_ json: String) throws {
        let folder = try TemporaryFolder()
        let url = folder.url.appending(path: "index.json")
        let data = Data(json.utf8)
        try data.write(to: url)
        #expect(throws: ClipboardStoreError.couldNotWrite) {
            try ClipIndexValidation.inspect(url, using: nil)
        }
        #expect(try Data(contentsOf: url) == data)
    }

    @Test("a file read failure remains a typed refusal")
    func unreadableIndex() throws {
        let folder = try TemporaryFolder()
        #expect(throws: ClipboardStoreError.couldNotWrite) {
            try ClipIndexValidation.inspect(folder.url, using: nil)
        }
    }

    @Test("sealed indexes require their key and authenticate without rewriting")
    func sealedIndex() throws {
        let folder = try TemporaryFolder()
        let url = folder.url.appending(path: "index.json")
        let store = EncryptedStore(keys: Keys(value: SymmetricKey(size: .bits256)))
        let payload = Data(#"{"version":2,"clips":[]}"#.utf8)
        let data = try store.seal(payload, for: url.lastPathComponent)
        try data.write(to: url)
        #expect(try ClipIndexValidation.inspect(url, using: store) == nil)
        #expect(throws: ClipboardStoreError.couldNotWrite) {
            try ClipIndexValidation.inspect(url, using: nil)
        }
        let wrongKey = EncryptedStore(keys: Keys(value: SymmetricKey(size: .bits256)))
        #expect(throws: ClipboardStoreError.couldNotWrite) {
            try ClipIndexValidation.inspect(url, using: wrongKey)
        }
        #expect(try Data(contentsOf: url) == data)
    }

    @Test("future envelopes return their version before asking for a key")
    func futureEnvelope() throws {
        let folder = try TemporaryFolder()
        let url = folder.url.appending(path: "index.json")
        let store = EncryptedStore(keys: Keys(value: SymmetricKey(size: .bits256)))
        var data = try store.seal(Data("[]".utf8), for: url.lastPathComponent)
        data[EncryptedStore.sealedHeaderLength] = 99
        try data.write(to: url)
        #expect(try ClipIndexValidation.inspect(url, using: nil) == 99)
        #expect(try Data(contentsOf: url) == data)
    }

    @Test("truncated sealed headers and damaged authentication refuse replacement")
    func damagedEnvelope() throws {
        let folder = try TemporaryFolder()
        let url = folder.url.appending(path: "index.json")
        let store = EncryptedStore(keys: Keys(value: SymmetricKey(size: .bits256)))
        let sealed = try store.seal(Data("[]".utf8), for: url.lastPathComponent)
        var damaged = sealed
        damaged[damaged.count - 1] ^= 1
        for data in [Data(sealed.prefix(EncryptedStore.sealedHeaderLength)), damaged] {
            try data.write(to: url)
            #expect(throws: ClipboardStoreError.couldNotWrite) {
                try ClipIndexValidation.inspect(url, using: store)
            }
            #expect(try Data(contentsOf: url) == data)
        }
    }
}
