/// Applies Unicode confusable and script rules to panel names.

import Foundation

struct AliasUnicodeRules: Sendable {
    private static let japaneseNameScripts: Set<String> = ["Hani", "Hira", "Kana"]
    private static let koreanNameScripts: Set<String> = ["Hani", "Hang"]

    private let confusables: [UInt32: String]
    private let scripts: [ScriptRange]
    private let scriptExtensions: [ScriptRange]

    static let loaded: Result<AliasUnicodeRules, LoadError> = load()

    func skeleton(_ text: String, locale: Locale) -> String {
        let input = PanelAlias.handle(text, locale: locale).decomposedStringWithCanonicalMapping
        var output = String.UnicodeScalarView()
        for scalar in input.unicodeScalars {
            if let replacement = confusables[scalar.value] {
                output.append(contentsOf: replacement.unicodeScalars)
            } else {
                output.append(scalar)
            }
        }
        return String(output).decomposedStringWithCanonicalMapping
    }

    func mixesScripts(_ text: String) -> Bool {
        var sharedScripts: Set<String>?
        var observedScripts = Set<String>()
        for scalar in text.unicodeScalars where scalar.properties.isAlphabetic {
            let candidates =
                scriptExtensions(for: scalar.value)
                ?? script(for: scalar.value).map { [$0] }
            guard let candidates, !candidates.isEmpty else { continue }
            if candidates.contains("Zyyy") || candidates.contains("Zinh") { continue }
            observedScripts.formUnion(candidates)
            if sharedScripts == nil {
                sharedScripts = Set(candidates)
            } else {
                sharedScripts?.formIntersection(candidates)
            }
        }
        guard sharedScripts?.isEmpty == true else { return false }
        return !allowsStandardHanName(observedScripts)
    }

    /// Whether a mixed Han name uses only the standard Japanese or Korean script combination.
    private func allowsStandardHanName(_ scripts: Set<String>) -> Bool {
        let hasHan = scripts.contains("Hani")
        let hasKana = scripts.contains("Hira") || scripts.contains("Kana")
        let hasHangul = scripts.contains("Hang")
        let isJapanese = scripts.isSubset(of: Self.japaneseNameScripts) && hasHan && hasKana
        let isKorean = scripts.isSubset(of: Self.koreanNameScripts) && hasHan && hasHangul
        return isJapanese || isKorean
    }

    private func scriptExtensions(for scalar: UInt32) -> [String]? {
        value(at: scalar, in: scriptExtensions)
    }

    private func script(for scalar: UInt32) -> String? {
        value(at: scalar, in: scripts)?.first
    }

    private func value(at scalar: UInt32, in ranges: [ScriptRange]) -> [String]? {
        var lower = 0
        var upper = ranges.count
        while lower < upper {
            let middle = lower + (upper - lower) / 2
            let range = ranges[middle]
            if scalar < range.first {
                upper = middle
            } else if scalar > range.last {
                lower = middle + 1
            } else {
                return range.values
            }
        }
        return nil
    }

    private static func load() -> Result<AliasUnicodeRules, LoadError> {
        do {
            let confusables = try read("confusables")
            let scripts = try read("Scripts")
            let extensions = try read("ScriptExtensions")
            let aliases = try parseScriptAliases(read("PropertyValueAliases"))
            return .success(
                AliasUnicodeRules(
                    confusables: try parseConfusables(confusables),
                    scripts: try parseRanges(scripts, aliases: aliases),
                    scriptExtensions: try parseRanges(extensions, aliases: aliases)))
        } catch let error {
            return .failure(error)
        }
    }

    private static func read(_ name: String) throws(LoadError) -> String {
        guard let url = Bundle.module.url(forResource: name, withExtension: "txt") else {
            throw .missingResource
        }
        do {
            return try String(contentsOf: url, encoding: .utf8)
        } catch {
            throw .unreadable
        }
    }

    private static func parseConfusables(_ text: String) throws(LoadError) -> [UInt32: String] {
        var result: [UInt32: String] = [:]
        for line in text.split(whereSeparator: \.isNewline) {
            let fields = line.prefix { $0 != "#" }
                .split(separator: ";", omittingEmptySubsequences: true)
            guard fields.count == 3 else { continue }
            guard let source = UInt32(fields[0].trimmingCharacters(in: .whitespaces), radix: 16) else {
                throw .invalidData
            }
            let target = fields[1].split(whereSeparator: \.isWhitespace).compactMap {
                UInt32($0, radix: 16).flatMap(Unicode.Scalar.init)
            }
            guard !target.isEmpty, target.count == fields[1].split(whereSeparator: \.isWhitespace).count
            else {
                throw .invalidData
            }
            result[source] = String(String.UnicodeScalarView(target))
        }
        guard !result.isEmpty else { throw .invalidData }
        return result
    }

    private static func parseScriptAliases(_ text: String) throws(LoadError) -> [String: String] {
        var result: [String: String] = [:]
        for line in text.split(whereSeparator: \.isNewline) {
            let fields = line.prefix { $0 != "#" }
                .split(separator: ";", omittingEmptySubsequences: true)
                .map { $0.trimmingCharacters(in: .whitespaces) }
            guard fields.first == "sc" else { continue }
            guard fields.count >= 3 else { throw .invalidData }
            for alias in fields.dropFirst() {
                result[alias] = fields[1]
            }
        }
        guard !result.isEmpty else { throw .invalidData }
        return result
    }

    private static func parseRanges(
        _ text: String, aliases: [String: String]
    ) throws(LoadError) -> [ScriptRange] {
        var result: [ScriptRange] = []
        for line in text.split(whereSeparator: \.isNewline) {
            let fields = line.prefix { $0 != "#" }
                .split(separator: ";", omittingEmptySubsequences: true)
            guard fields.count == 2 else { continue }
            let bounds = fields[0].trimmingCharacters(in: .whitespaces).components(separatedBy: "..")
            guard bounds.count <= 2, let first = UInt32(bounds[0], radix: 16) else { throw .invalidData }
            let last = bounds.count == 2 ? UInt32(bounds[1], radix: 16) : first
            guard let last else { throw .invalidData }
            let values = fields[1].split(whereSeparator: \.isWhitespace).map {
                aliases[String($0)] ?? String($0)
            }
            guard !values.isEmpty else { throw .invalidData }
            result.append(ScriptRange(first: first, last: last, values: values))
        }
        guard !result.isEmpty else { throw .invalidData }
        return result.sorted { $0.first < $1.first }
    }

    enum LoadError: Error, Sendable {
        case missingResource
        case unreadable
        case invalidData
    }
}

private struct ScriptRange: Sendable {
    let first: UInt32
    let last: UInt32
    let values: [String]
}
