// What the rules that read words are given: a clip with its addresses and path listings taken out.

import Foundation

/// Removes what only looks like a credential to a rule about words. See Docs/clipboard-secrets.md.
enum AddressFreeText {
    /// The text without any `scheme://…` address, whose own credentials are the address rules' to judge.
    static func removingAddresses(from text: String) -> String {
        guard text.contains("://") else { return text }
        var bytes = Array(text.utf8)
        var kept: [UInt8] = []
        kept.reserveCapacity(bytes.count)
        var index = 0
        while index < bytes.count {
            guard index + 3 <= bytes.count, bytes[index] == UInt8(ascii: ":"), bytes[index + 1] == UInt8(ascii: "/"),
                bytes[index + 2] == UInt8(ascii: "/")
            else {
                kept.append(bytes[index])
                index += 1
                continue
            }
            while let last = kept.last, isSchemeByte(last) { kept.removeLast() }
            index += 3
            while index < bytes.count, !BearerURLShape.endsURL(bytes[index]) { index += 1 }
        }
        bytes = kept
        return String(decoding: bytes, as: UTF8.self)
    }

    /// The text without `pwd: /a/path` lines: a shell's working directory, where `pwd` names no password.
    static func removingWorkingDirectoryLines(from text: String) -> String {
        guard text.range(of: "pwd", options: .caseInsensitive) != nil else { return text }
        return text.split(omittingEmptySubsequences: false, whereSeparator: \.isNewline)
            .filter { !isWorkingDirectoryLine($0) }.joined(separator: "\n")
    }

    private static func isWorkingDirectoryLine(_ line: Substring) -> Bool {
        let trimmed = line.trimmingPrefix(while: \.isWhitespace)
        guard let name = trimmed.range(of: "pwd", options: [.anchored, .caseInsensitive]) else { return false }
        var rest = trimmed[name.upperBound...].trimmingPrefix(while: \.isWhitespace)
        guard let separator = rest.first, separator == ":" || separator == "=" else { return false }
        rest = rest.dropFirst().trimmingPrefix(while: \.isWhitespace)
        return ["/", "~/", "./", "../"].contains { rest.hasPrefix($0) }
    }

    private static func isSchemeByte(_ byte: UInt8) -> Bool {
        (0x30...0x39).contains(byte) || (0x41...0x5A).contains(byte) || (0x61...0x7A).contains(byte)
            || byte == UInt8(ascii: "+") || byte == UInt8(ascii: "-") || byte == UInt8(ascii: ".")
    }
}
