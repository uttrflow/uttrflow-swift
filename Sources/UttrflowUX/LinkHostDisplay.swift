// The host a link row names, decoded and checked, so the panel shows what a browser would contact.
import Foundation

/// The real host of a copied address, for a row to show in strong weight beside its flags.
public struct LinkHostDisplay: Sendable, Equatable {
    /// The host with any `xn--` labels decoded, lowercased.
    public let host: String
    /// The host exactly as written, lowercased, for the tooltip.
    public let rawHost: String
    /// Whether the authority carries a user name or password before the host.
    public let hasUserInfo: Bool
    /// Whether one label of the host mixes writing systems.
    public let isMixedScript: Bool

    /// Sentences for the badge and the tooltip, empty when nothing is out of the ordinary.
    public var warnings: [String] {
        var found: [String] = []
        if hasUserInfo { found.append("Has a user name before the host") }
        if isMixedScript { found.append("Host mixes writing systems") }
        return found
    }

    /// The tooltip: the raw host first, then each warning on its own line.
    public var tooltip: String {
        ([rawHost == host ? host : "\(host)\n\(rawHost)"] + warnings).joined(separator: "\n")
    }

    /// Reads the first address in `text`, or `nil` when it has no `scheme://authority` form.
    public static func parse(_ text: String) -> LinkHostDisplay? {
        guard var line = text.split(whereSeparator: \.isNewline).first.map(String.init) else {
            return nil
        }
        line = line.trimmingCharacters(in: .whitespaces)
        if line.first == "<", line.last == ">" { line = String(line.dropFirst().dropLast()) }
        guard let marker = line.range(of: "://") else { return nil }
        let scheme = line[..<marker.lowerBound]
        guard !scheme.isEmpty, scheme.allSatisfy({ $0.isLetter || $0.isNumber || "+.-".contains($0) })
        else { return nil }
        let rest = line[marker.upperBound...]
        let authority = rest.prefix { !"/\\?#".contains($0) }
        let hasUserInfo = authority.contains("@")
        let hostAndPort = authority.split(separator: "@", omittingEmptySubsequences: false).last ?? ""
        let rawHost: Substring
        if hostAndPort.first == "[" {
            rawHost = hostAndPort.prefix { $0 != "]" }.dropFirst()
        } else {
            rawHost = hostAndPort.prefix { $0 != ":" }
        }
        let raw = rawHost.lowercased()
        guard !raw.isEmpty else { return nil }
        let labels = raw.split(separator: ".", omittingEmptySubsequences: false).map { label in
            label.hasPrefix("xn--")
                ? (decodePunycode(String(label.dropFirst(4))) ?? String(label))
                : String(label)
        }
        return LinkHostDisplay(
            host: labels.joined(separator: "."), rawHost: raw, hasUserInfo: hasUserInfo,
            isMixedScript: labels.contains(where: mixesScripts))
    }

    // MARK: - Writing systems

    private enum Script: Hashable {
        case latin, cyrillic, greek, armenian, hebrew, arabic, devanagari, thai, cjk
    }

    private static func script(of scalar: Unicode.Scalar) -> Script? {
        switch scalar.value {
        case 0x41...0x5A, 0x61...0x7A, 0xC0...0x24F, 0x1E00...0x1EFF: .latin
        case 0x370...0x3FF, 0x1F00...0x1FFF: .greek
        case 0x400...0x52F: .cyrillic
        case 0x530...0x58F: .armenian
        case 0x590...0x5FF: .hebrew
        case 0x600...0x6FF: .arabic
        case 0x900...0x97F: .devanagari
        case 0xE00...0xE7F: .thai
        case 0x3040...0x30FF, 0x3400...0x4DBF, 0x4E00...0x9FFF, 0xAC00...0xD7AF: .cjk
        default: nil
        }
    }

    private static func mixesScripts(_ label: String) -> Bool {
        Set(label.unicodeScalars.compactMap(script(of:))).count > 1
    }

    // MARK: - Punycode (RFC 3492)

    private static func digit(of scalar: Unicode.Scalar) -> Int? {
        switch scalar.value {
        case 0x30...0x39: Int(scalar.value) - 0x30 + 26
        case 0x41...0x5A: Int(scalar.value) - 0x41
        case 0x61...0x7A: Int(scalar.value) - 0x61
        default: nil
        }
    }

    private static func adapt(_ delta: Int, _ points: Int, first: Bool) -> Int {
        var delta = first ? delta / 700 : delta / 2
        delta += delta / points
        var k = 0
        while delta > 455 {
            delta /= 35
            k += 36
        }
        return k + 36 * delta / (delta + 38)
    }

    /// The label after its `xn--` prefix, or `nil` when it is not valid punycode.
    static func decodePunycode(_ label: String) -> String? {
        let scalars = Array(label.unicodeScalars)
        let split = scalars.lastIndex(of: "-")
        var output = split.map { Array(scalars[..<$0]) } ?? []
        guard output.allSatisfy({ $0.isASCII }) else { return nil }
        var position = split.map { $0 + 1 } ?? 0
        var n = 128
        var i = 0
        var bias = 72
        while position < scalars.count {
            let previous = i
            var weight = 1
            var k = 36
            while true {
                guard position < scalars.count, let value = digit(of: scalars[position]) else {
                    return nil
                }
                position += 1
                let (product, overflowed) = value.multipliedReportingOverflow(by: weight)
                let (sum, summed) = i.addingReportingOverflow(product)
                guard !overflowed, !summed else { return nil }
                i = sum
                let threshold = k <= bias ? 1 : (k >= bias + 26 ? 26 : k - bias)
                if value < threshold { break }
                let (next, grew) = weight.multipliedReportingOverflow(by: 36 - threshold)
                guard !grew else { return nil }
                weight = next
                k += 36
            }
            let count = output.count + 1
            bias = adapt(i - previous, count, first: previous == 0)
            n += i / count
            i %= count
            guard let scalar = Unicode.Scalar(UInt32(clamping: n)) else { return nil }
            output.insert(scalar, at: i)
            i += 1
        }
        var text = String.UnicodeScalarView()
        text.append(contentsOf: output)
        return String(text)
    }
}
