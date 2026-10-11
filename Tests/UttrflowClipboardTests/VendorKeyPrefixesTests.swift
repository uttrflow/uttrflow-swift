// Tests that every row of the vendor key prefix table is masked by both readers, alone and inside a longer paste.

import Testing

@testable import UttrflowClipboard
@testable import UttrflowCore

/// Every key below is built from a table row at run time, so no secret scanner matches the source.
@Suite("Each vendor key prefix is one table row that both readers follow")
struct VendorKeyPrefixesTests {
    /// The row's prefix and a body of exactly its shortest length, written in digits every alphabet holds.
    private static func sample(_ row: VendorKeyPrefix, extra: Int = 0) -> String {
        let digits = Array("3141592653")
        return row.prefix + String((0..<(row.minimum + extra)).map { digits[$0 % digits.count] })
    }

    private static var rows: [String] { VendorKeyPrefixes.all.map(\.prefix) }

    private static func row(_ prefix: String) -> VendorKeyPrefix? {
        VendorKeyPrefixes.all.first { $0.prefix == prefix }
    }

    @Test("a key of every row is masked on its own", arguments: rows)
    func keyAlone(_ prefix: String) throws {
        let key = Self.sample(try #require(Self.row(prefix)))
        #expect(key.firstMatch(of: SecretShapes.vendorKey) != nil)
        #expect(SecretShapes.matches(key))
        #expect(ClipKindDetector.kind(of: key) == .secret)
    }

    @Test("a key of every row is masked inside a multi-line paste", arguments: rows)
    func keyInsideAPaste(_ prefix: String) throws {
        let key = Self.sample(try #require(Self.row(prefix)), extra: 4)
        let paste = "deploy notes for the staging box\nuse " + key + " for now\nthanks"
        #expect(ClipKindDetector.kind(of: paste) == .secret)
    }

    @Test("prose that only names a row's prefix is not masked", arguments: rows)
    func proseNamingThePrefix(_ prefix: String) {
        let prose = "Keys from that service start with " + prefix + " and are long.\nRotate them often."
        #expect(ClipKindDetector.kind(of: prose) != .secret)
    }

    @Test("a body one character short of a row's shortest is not a key of that row", arguments: rows)
    func shortBody(_ prefix: String) throws {
        let row = try #require(Self.row(prefix))
        let short = String(Self.sample(row).dropLast())
        #expect(short.firstMatch(of: SecretShapes.vendorKey).map { $0.output == short } != true)
    }

    @Test("the byte windows open at every row's prefix and hold its shortest match")
    func windowsCoverEveryRow() {
        #expect(VendorKeyWindows.longestShortestMatch > VendorKeyPrefixes.longestShortestMatch)
        #expect(VendorKeyWindows.width > VendorKeyWindows.longestShortestMatch + 1)
        for row in VendorKeyPrefixes.all {
            let bytes = Array(row.prefix.utf8)
            let opens = bytes.withUnsafeBufferPointer { VendorKeyPrefixes.opens($0, at: 0) }
            #expect(opens, "\(row.prefix) does not open a window")
        }
    }

    @Test("no two rows share a prefix")
    func prefixesAreDistinct() {
        #expect(Set(Self.rows).count == Self.rows.count)
    }
}
