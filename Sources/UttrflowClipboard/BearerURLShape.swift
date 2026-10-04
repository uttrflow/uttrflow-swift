// Recognises a web address that is itself a credential.

/// A URL whose holder can act with it: a chat webhook, or one signed or carrying a token. See Docs/clipboard-secrets.md.
enum BearerURLShape {
    private static let maximumSchemeLessAddressLength = 256
    private static let schemeLessSlackPathPrefixes = [
        Array("services".utf8), Array("workflows".utf8), Array("triggers".utf8),
    ]
    private static let schemeLessSlackPrefixReadLimit = 25

    /// Whether any URL in the text, or nested in one, is a bearer credential, reading each byte of it a bounded number of times.
    static func matches(_ text: String, read: inout Int) -> Bool {
        var count = 0
        defer { read += count }
        return ClipBytes.read(text) { _, bytes in
            var from = 0
            while let separator = find(bytes, from: from, to: bytes.count) {
                let start = separator + 3
                var end = start
                while end < bytes.count, !endsURL(bytes[end]) { end += 1 }
                count += 2 * (end - separator)
                if hasCredentialParameter(urlText(bytes, from: start, to: end)) { return true }
                if hasWebhook(bytes, from: start, to: end) { return true }
                from = end
            }
            if hasSchemeLessSlackWebhook(bytes, read: &count) { return true }
            return false
        }
    }

    /// Whether the address starting at `start`, or one nested after a later `://` before `end`, is a webhook.
    private static func hasWebhook(_ bytes: UnsafeBufferPointer<UInt8>, from start: Int, to end: Int) -> Bool
    {
        var authority = start
        while authority <= end {
            let nested = find(bytes, from: authority, to: end)
            let location = Location(urlText(bytes, from: authority, to: nested ?? end))
            if isWebhook(host: location.host, path: location.path) { return true }
            guard let nested else { return false }
            authority = nested + 3
        }
        return false
    }

    /// Where the next `://` starts at or after `from` and before `limit`.
    private static func find(_ bytes: UnsafeBufferPointer<UInt8>, from: Int, to limit: Int) -> Int? {
        var offset = from
        while offset + 3 <= limit {
            if bytes[offset] == UInt8(ascii: ":"), bytes[offset + 1] == UInt8(ascii: "/"),
                bytes[offset + 2] == UInt8(ascii: "/")
            {
                return offset
            }
            offset += 1
        }
        return nil
    }

    /// Whether a byte cannot stand in a URL as copied: ASCII space or control, a quote or an angle bracket.
    private static func endsURL(_ byte: UInt8) -> Bool {
        byte <= 0x20 || byte >= 0x80 || byte == 0x7F || byte == UInt8(ascii: "\"")
            || byte == UInt8(ascii: "'")
            || byte == UInt8(ascii: "<") || byte == UInt8(ascii: ">") || byte == UInt8(ascii: "`")
    }

    /// Whether a query or fragment parameter, its name percent-decoded, carries a signature or a token.
    private static func hasCredentialParameter(_ text: Substring) -> Bool {
        let beforeQuery = text.prefix { $0 != "?" && $0 != "#" }
        let rest = text.dropFirst(beforeQuery.count).dropFirst()
        return rest.split { $0 == "&" || $0 == ";" || $0 == "#" || $0 == "?" }.contains { pair in
            let name = pair.prefix { $0 != "=" }
            let value = pair.dropFirst(name.count + 1)
            return value.count >= shortestValue
                && credentialParameters.contains(normalizedParameterName(percentDecoded(name)))
                && SecretShapes.looksGenerated(percentDecoded(value))
        }
    }

    /// Treat hyphens and underscores as equivalent in credential parameter names.
    private static func normalizedParameterName(_ name: String) -> String {
        String(name.lowercased().map { $0 == "-" ? "_" : $0 })
    }

    /// The fewest characters a parameter's value needs to be a credential rather than a placeholder.
    private static let shortestValue = 8

    /// Query and fragment parameters that carry a signature or a token, lowercase.
    private static let credentialParameters: Set<String> = [
        "sig", "signature", "x_amz_signature", "x_goog_signature", "x_amz_security_token",
        "api_key", "apikey", "key", "auth", "jwt", "password", "code",
        "access_token", "id_token", "refresh_token", "token",
    ]

    /// The name with each `%XX` escape of an ASCII byte replaced by that byte; any other `%` stays as written.
    private static func percentDecoded(_ name: Substring) -> String {
        guard name.contains("%") else { return String(name) }
        var decoded: [UInt8] = []
        var bytes = name.utf8[...]
        while let byte = bytes.popFirst() {
            if byte == UInt8(ascii: "%"), bytes.count >= 2,
                let high = hexValue(bytes[bytes.startIndex]),
                let low = hexValue(bytes[bytes.index(after: bytes.startIndex)]), high < 8
            {
                decoded.append(high << 4 | low)
                bytes = bytes.dropFirst(2)
            } else {
                decoded.append(byte)
            }
        }
        return String(decoding: decoded, as: UTF8.self)
    }

    /// The value of one hexadecimal digit, either case.
    private static func hexValue(_ byte: UInt8) -> UInt8? {
        switch byte {
        case UInt8(ascii: "0")...UInt8(ascii: "9"): byte - UInt8(ascii: "0")
        case UInt8(ascii: "a")...UInt8(ascii: "f"): byte - UInt8(ascii: "a") + 10
        case UInt8(ascii: "A")...UInt8(ascii: "F"): byte - UInt8(ascii: "A") + 10
        default: nil
        }
    }

    /// Incoming-webhook addresses of the chat services, which post as whoever holds them.
    private static func isWebhook(host: String, path: [Substring]) -> Bool {
        switch host {
        case "api.telegram.org":
            guard let bot = path.first, bot.hasPrefix("bot"), let colon = bot.firstIndex(of: ":") else {
                return false
            }
            let identifier = bot[bot.index(bot.startIndex, offsetBy: 3)..<colon]
            let token = bot[bot.index(after: colon)...]
            return !identifier.isEmpty && identifier.allSatisfy(\.isNumber)
                && identifier.allSatisfy(\.isASCII)
                && token.count == 35 && token.allSatisfy(\.isASCII)
                && token.allSatisfy { $0.isLetter || $0.isNumber || $0 == "_" || $0 == "-" }
        case "hooks.slack.com":
            guard ["services", "workflows", "triggers"].contains(path.first ?? ""), path.count >= 4,
                hasIdentifier(path[1], prefix: "T"), hasIdentifier(path[2], prefix: "B")
            else { return false }
            return SecretShapes.looksGenerated(String(path[3]))
        case "discord.com", "discordapp.com", "ptb.discord.com", "canary.discord.com":
            guard path.first == "api", let hook = path.firstIndex(of: "webhooks") else { return false }
            guard path.count - hook >= 3, !path[hook + 1].isEmpty,
                path[hook + 1].allSatisfy(\.isNumber), path[hook + 1].allSatisfy(\.isASCII)
            else { return false }
            return SecretShapes.looksGenerated(String(path[hook + 2]))
        case "outlook.office.com":
            return path.first == "webhook" && path.count >= 2
        default:
            return host.hasSuffix(".webhook.office.com") && path.first == "webhookb2" && path.count >= 2
        }
    }

    /// Whether a Slack address copied without its scheme has the same team, channel and generated-token shape.
    private static func hasSchemeLessSlackWebhook(
        _ bytes: UnsafeBufferPointer<UInt8>, read: inout Int
    ) -> Bool {
        let host = Array("hooks.slack.com".utf8)
        guard bytes.count >= host.count else { return false }
        var start = 0
        while start + host.count <= bytes.count {
            guard bytes[start].lowercasedASCII == host[0] else {
                read += 1
                start += 1
                continue
            }
            let candidateStart = start
            start += 1
            read += host.count
            guard host.indices.allSatisfy({ bytes[candidateStart + $0].lowercasedASCII == host[$0] }),
                candidateStart == 0 || !isHostByte(bytes[candidateStart - 1])
            else { continue }
            let pathStart = candidateStart + host.count
            guard pathStart < bytes.count, bytes[pathStart] == UInt8(ascii: "/") else { continue }

            let segmentStart = pathStart + 1
            guard
                Self.schemeLessSlackPathPrefixes.contains(where: {
                    matches($0, bytes: bytes, from: segmentStart)
                })
            else {
                read += Self.schemeLessSlackPrefixReadLimit
                continue
            }

            var end = pathStart
            let limit = min(bytes.count, candidateStart + Self.maximumSchemeLessAddressLength)
            while end < limit, !endsURL(bytes[end]) { end += 1 }
            read += end - pathStart
            guard end == bytes.count || endsURL(bytes[end]) else { continue }
            let location = Location(urlText(bytes, from: candidateStart, to: end))
            if isWebhook(host: location.host, path: location.path) { return true }
        }
        return false
    }

    /// Whether the path at `start` begins with a webhook route and a segment boundary.
    private static func matches(
        _ expected: [UInt8], bytes: UnsafeBufferPointer<UInt8>, from start: Int
    ) -> Bool {
        guard start + expected.count < bytes.count else { return false }
        return expected.indices.allSatisfy({ bytes[start + $0].lowercasedASCII == expected[$0] })
            && bytes[start + expected.count] == UInt8(ascii: "/")
    }

    /// Whether a byte can continue a hostname.
    private static func isHostByte(_ byte: UInt8) -> Bool {
        (UInt8(ascii: "a")...UInt8(ascii: "z")).contains(byte.lowercasedASCII)
            || (UInt8(ascii: "0")...UInt8(ascii: "9")).contains(byte)
            || byte == UInt8(ascii: ".") || byte == UInt8(ascii: "-")
    }

    /// Whether a service identifier has its required prefix and an alphanumeric suffix.
    private static func hasIdentifier(_ value: Substring, prefix: String) -> Bool {
        value.first == prefix.first && value.count >= 2 && value.dropFirst().allSatisfy(\.isASCII)
            && value.dropFirst().allSatisfy { $0.isLetter || $0.isNumber }
    }
}

private extension UInt8 {
    var lowercasedASCII: UInt8 {
        (UInt8(ascii: "A")...UInt8(ascii: "Z")).contains(self) ? self + 32 : self
    }
}

/// The text of the bytes from `start` to `end`.
private func urlText(_ bytes: UnsafeBufferPointer<UInt8>, from start: Int, to end: Int) -> Substring {
    Substring(String(decoding: UnsafeBufferPointer(rebasing: bytes[start..<end]), as: UTF8.self))
}

/// Where one URL's text after `://` points: its host lowercased without a closing dot, and its path's segments.
private struct Location {
    var host: String
    var path: [Substring]

    init(_ text: Substring) {
        let beforeQuery = text.prefix { $0 != "?" && $0 != "#" }
        let authority = beforeQuery.prefix { $0 != "/" }
        let hostAndPort = authority.split(separator: "@", omittingEmptySubsequences: false).last ?? ""
        let name = hostAndPort.prefix { $0 != ":" }
        host = String(name.hasSuffix(".") ? name.dropLast() : name).lowercased()
        path = beforeQuery.dropFirst(authority.count).split(separator: "/")
    }
}
