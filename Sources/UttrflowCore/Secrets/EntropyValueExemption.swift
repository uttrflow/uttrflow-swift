import Foundation

/// Identifies encoded content and contextual digests that are not credentials.
struct EntropyValueExemption {
    private let contextualDigests: Set<String>

    /// Scans a clip once for contextual digest values before classifying its individual tokens.
    init(in text: String) {
        var digests = Set<String>()
        let pattern =
            #"(?i)(?:[\"'](?:commit|sha1|sha256|sha-256|hash|digest)[\"']\s*:\s*[\"']([0-9a-f]{32,})[\"']|\bthe\s+build\s+is\s+at\s+([0-9a-f]{32,})\s+and\s+passed\b)"#
        if let expression = try? NSRegularExpression(pattern: pattern) {
            let range = NSRange(text.startIndex..., in: text)
            SecretShapes.tally?.record(text.count)
            expression.enumerateMatches(in: text, range: range) { match, _, _ in
                guard let match else { return }
                for group in 1..<match.numberOfRanges where match.range(at: group).location != NSNotFound {
                    if let capture = Range(match.range(at: group), in: text) {
                        digests.insert(text[capture].lowercased())
                    }
                }
            }
        }
        contextualDigests = digests
    }

    /// Data payloads and contextual source-control hashes are not credentials.
    func matches(_ token: String) -> Bool {
        SecretShapes.tally?.record(token.count)
        if Self.isBase64DataURIValue(token) { return true }
        let value = token.trimmingCharacters(in: CharacterSet(charactersIn: "\"',"))
        return value.split(whereSeparator: { !$0.isASCII || !$0.isHexDigit }).contains {
            $0.count >= SecretShapes.hexTokenLength && contextualDigests.contains($0.lowercased())
        }
            || isBase64Checksum(value)
    }

    /// A labelled SHA checksum is not a credential when its decoded digest has the named bit length.
    private func isBase64Checksum(_ value: String) -> Bool {
        guard value.hasPrefix("sha"), let separator = value.firstIndex(of: "-") else { return false }
        let algorithm = value[..<separator]
        guard let bits = Int(algorithm.dropFirst(3)), [256, 384, 512].contains(bits),
            let digest = Data(base64Encoded: String(value[value.index(after: separator)...]))
        else { return false }
        return digest.count == bits / 8
    }

    /// Recognises a complete data URI, including common HTML and CSS wrappers copied with one word.
    private static func isBase64DataURIValue(_ token: String) -> Bool {
        if token.range(of: "data:", options: [.anchored, .caseInsensitive]) != nil {
            return isValidBase64DataURI(token[...])
        }
        if token.lowercased().hasPrefix("src=") {
            var value = String(token.dropFirst(4))
            if value.hasSuffix(">") {
                value.removeLast()
                if value.hasSuffix("/") { value.removeLast() }
            }
            if let quote = value.first, quote == "\"" || quote == "'" {
                guard value.last == quote else { return false }
                value.removeFirst()
                value.removeLast()
            }
            return isValidBase64DataURI(value[...])
        }
        guard let url = token.range(of: "url(", options: .caseInsensitive) else { return false }
        let property = token[..<url.lowerBound]
        guard property.isEmpty || property.hasSuffix(":") else { return false }
        var contents = String(token[url.upperBound...])
        if contents.hasSuffix("}") { contents.removeLast() }
        if contents.hasSuffix(";") { contents.removeLast() }
        guard contents.hasSuffix(")") else { return false }
        contents.removeLast()
        if let quote = contents.first, quote == "\"" || quote == "'" {
            guard contents.last == quote else { return false }
            contents.removeFirst()
            contents.removeLast()
        }
        return isValidBase64DataURI(contents[...])
    }

    /// Requires a MIME type, the base64 marker and a decodable payload before exempting entropy.
    private static func isValidBase64DataURI(_ uri: Substring) -> Bool {
        guard let scheme = uri.range(of: "data:", options: [.anchored, .caseInsensitive]),
            let comma = uri.firstIndex(of: ",")
        else { return false }
        let metadata = uri[scheme.upperBound..<comma]
        guard metadata.lowercased().hasSuffix(";base64") else { return false }
        let fields = metadata.dropLast(";base64".count).split(
            separator: ";", omittingEmptySubsequences: false)
        let parameters: ArraySlice<Substring>
        if let first = fields.first, !first.isEmpty {
            let mime = first.split(separator: "/", omittingEmptySubsequences: false)
            guard mime.count == 2, mime.allSatisfy(isMIMEComponent) else { return false }
            parameters = fields.dropFirst()
        } else {
            parameters = fields.dropFirst()
        }
        guard parameters.allSatisfy(isMIMEParameter) else { return false }
        return Data(base64Encoded: String(uri[uri.index(after: comma)...])) != nil
    }

    /// Checks one MIME type component or parameter against the ASCII token characters.
    private static func isMIMEComponent(_ value: Substring) -> Bool {
        let punctuation = "!#$%&'*+-.^_`|~"
        return !value.isEmpty
            && value.allSatisfy {
                $0.isASCII && ($0.isLetter || $0.isNumber || punctuation.contains($0))
            }
    }

    /// Requires each media-type parameter to have a nonempty token name and value.
    private static func isMIMEParameter(_ value: Substring) -> Bool {
        let pair = value.split(separator: "=", omittingEmptySubsequences: false)
        return pair.count == 2 && pair.allSatisfy(isMIMEComponent)
    }
}
