// Synthetic temporary indexes exercise the reader's cached-write refusal boundary.

import Foundation
import Testing
import UttrflowCore

@testable import UttrflowClipboard

@Suite("Rechecking clipboard index files")
struct ClipboardIndexReaderValidationTests {
    private func read(_ url: URL) throws -> Data { try Data(contentsOf: url) }

    @Test("supported and missing indexes permit a cached write without changing their bytes")
    func supportedAndMissingFiles() throws {
        let folder = try TemporaryFolder()
        let history = folder.url.appending(path: "clipboard.v1.json")
        let saved = folder.url.appending(path: "saved.v1.json")
        let data = Data(#"{"version":2,"clips":[]}"#.utf8)
        try data.write(to: history)
        var reader = ClipboardIndexReader(encryptedStore: nil)
        try reader.validateCurrentFormats(in: [history, saved], reading: read)
        #expect(reader.unsupportedFormatVersions == [:])
        #expect(reader.unreplaceable == [])
        #expect(try Data(contentsOf: history) == data)
        #expect(!FileManager.default.fileExists(atPath: saved.path))
    }

    @Test("either index's future payload is refused and recorded intact", arguments: [0, 1])
    func futureSibling(refusedIndex: Int) throws {
        let folder = try TemporaryFolder()
        let files = ["clipboard.v1.json", "saved.v1.json"].map { folder.url.appending(path: $0) }
        let current = Data(#"{"version":2,"clips":[]}"#.utf8)
        let future = Data(#"{"version":99,"futureField":true}"#.utf8)
        for (index, file) in files.enumerated() {
            try (index == refusedIndex ? future : current).write(to: file)
        }
        var reader = ClipboardIndexReader(encryptedStore: nil)
        #expect(throws: ClipboardStoreError.unsupportedFormat) {
            try reader.validateCurrentFormats(in: files, reading: read)
        }
        #expect(reader.unsupportedFormatVersions == [files[refusedIndex]: 99])
        #expect(try Data(contentsOf: files[refusedIndex]) == future)
        #expect(try Data(contentsOf: files[1 - refusedIndex]) == current)
    }

    @Test("an existing unreadable index refuses a cached write without a false version report")
    func unreadableFile() throws {
        let folder = try TemporaryFolder()
        let file = folder.url.appending(path: "clipboard.v1.json", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: file, withIntermediateDirectories: false)
        var reader = ClipboardIndexReader(encryptedStore: nil)
        #expect(throws: ClipboardStoreError.couldNotWrite) {
            try reader.validateCurrentFormats(in: [file], reading: read)
        }
        #expect(reader.unsupportedFormatVersions == [:])
        #expect(try file.resourceValues(forKeys: [.isDirectoryKey]).isDirectory == true)
    }

    @Test("an already protected index is excluded from read-time replacement validation")
    func protectedFile() throws {
        let folder = try TemporaryFolder()
        let file = folder.url.appending(path: "clipboard.v1.json", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: file, withIntermediateDirectories: false)
        var reader = ClipboardIndexReader(encryptedStore: nil)
        reader.unreplaceable.insert(file)
        try reader.validateCurrentFormats(in: [file], reading: read)
        #expect(reader.unreplaceable == [file])
        #expect(reader.unsupportedFormatVersions == [:])
        #expect(try file.resourceValues(forKeys: [.isDirectoryKey]).isDirectory == true)
    }
}
