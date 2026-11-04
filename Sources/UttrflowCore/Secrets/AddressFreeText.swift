// What the rules that read words are given: a clip with its addresses and path listings taken out.

import Foundation

/// Removes what only looks like a credential to a rule about words. See Docs/clipboard-secrets.md.
enum AddressFreeText {
    /// The text without any `scheme://…` address, whose own credentials are the address rules' to judge.
    static func removingAddresses(from text: String) -> String {
        guard text.contains("://") else { return text }
        let scalars = Array(text.unicodeScalars)
        var kept = String.UnicodeScalarView()
        var index = 0
        while index < scalars.count {
            guard index + 3 <= scalars.count, scalars[index] == ":", scalars[index + 1] == "/",
                scalars[index + 2] == "/", let last = kept.last, isSchemeScalar(last)
            else {
                kept.append(scalars[index])
                index += 1
                continue
            }
            while let last = kept.last, isSchemeScalar(last) { kept.removeLast() }
            index += 3
            let start = index
            while index < scalars.count, !endsAddress(scalars[index]) { index += 1 }
            index = endOfAddress(in: scalars[start..<index])
        }
        return String(kept)
    }

    /// Where an address stops: at its end, or before a `;name=value` naming a secret, which a shell reads as a new command.
    private static func endOfAddress(in span: ArraySlice<Unicode.Scalar>) -> Int {
        guard let semicolon = span.firstIndex(of: ";") else { return span.endIndex }
        var tail = String.UnicodeScalarView()
        tail.append(contentsOf: span[(semicolon + 1)...])
        return SecretShapes.hasNamedSecret(String(tail)) ? semicolon + 1 : span.endIndex
    }

    /// An ASCII boundary as the URL rules read it, or non-ASCII that is not part of a word: curly quotes, dashes, spaces.
    private static func endsAddress(_ scalar: Unicode.Scalar) -> Bool {
        if scalar.isASCII { return BearerURLShape.endsURL(UInt8(scalar.value)) }
        let properties = scalar.properties
        switch properties.generalCategory {
        case .nonspacingMark, .spacingMark, .enclosingMark: return false
        default: return !properties.isAlphabetic && properties.numericType == nil
        }
    }

    /// The text without `pwd: /a/path` lines: a shell's working directory, where `pwd` names no password.
    static func removingWorkingDirectoryLines(from text: String) -> String {
        guard text.range(of: "pwd", options: .caseInsensitive) != nil else { return text }
        return text.split(omittingEmptySubsequences: false, whereSeparator: \.isNewline)
            .filter { !isWorkingDirectoryLine($0) }.joined(separator: "\n")
    }

    private static func isWorkingDirectoryLine(_ line: Substring) -> Bool {
        let trimmed = line.trimmingPrefix(while: \.isWhitespace)
        guard let name = trimmed.range(of: "pwd", options: [.anchored, .caseInsensitive]) else {
            return false
        }
        var rest = trimmed[name.upperBound...].trimmingPrefix(while: \.isWhitespace)
        guard let separator = rest.first, separator == ":" || separator == "=" else { return false }
        rest = rest.dropFirst().trimmingPrefix(while: \.isWhitespace)
        guard PathShape.starts.contains(where: { rest.hasPrefix($0) }) else { return false }
        // Only the path: anything after it is still for the credential rules to read.
        let path = rest.prefix { !$0.isWhitespace }
        return rest[path.endIndex...].allSatisfy(\.isWhitespace)
    }

    private static func isSchemeScalar(_ scalar: Unicode.Scalar) -> Bool {
        scalar.isASCII
            && (scalar.properties.isAlphabetic || ("0"..."9").contains(scalar)
                || "+-.".unicodeScalars.contains(scalar))
    }
}
