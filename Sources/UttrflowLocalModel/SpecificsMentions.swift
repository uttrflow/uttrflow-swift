import Foundation
import UttrflowAI
import UttrflowCore
import UttrflowPredict

extension Specifics {
    private static let currencyUnits: [String: String] = {
        let locale = Locale(identifier: "en_US")
        let singulars = Locale.commonISOCurrencyCodes.compactMap {
            locale.localizedString(forCurrencyCode: $0)?.split(whereSeparator: { !$0.isLetter }).last
                .map { String($0).lowercased() }
        }
        return singulars.reduce(into: [:]) {
            $0[$1] = $1
            $0["\($1)s"] = $1
        }
    }()
    /// The ordinals a day of the month is said with, read from the one ordinal table.
    private static let ordinalDays = NumberFormsPass.ordinalUnits.filter { $0.value <= 31 }
    static func specifics(in line: String, after typed: String, writesCode: Bool = false) -> [Mention] {
        scan(line, after: typed.count, writesCode: writesCode)
    }

    static func mentions(in text: String, writesCode: Bool = false) -> [Mention] {
        scan(text, writesCode: writesCode)
    }

    private static func scan(_ text: String, after typedLength: Int? = nil, writesCode: Bool) -> [Mention] {
        let words = text.split(whereSeparator: \.isWhitespace)
        let tokens = words.map { normalised($0) ?? "" }
        let numberWords = spelledNumberIndices(in: tokens)
        let typedEnd = typedLength.map { text.index(text.startIndex, offsetBy: min($0, text.count)) }
        var found: [Mention] = []
        var index = 0
        while index < words.count {
            let match =
                currencyAmount(at: index, in: words, tokens: tokens, spelledNumbers: numberWords)
                ?? (!writesCode
                    ? numberMention(at: index, in: words, tokens: tokens, spelledNumbers: numberWords) : nil)
            if let match {
                let end = words[match.endIndex - 1].endIndex
                if typedEnd.map({ end > $0 }) ?? true {
                    found.append(match.mention)
                }
                index = match.endIndex
                continue
            }
            let word = words[index]
            guard typedEnd.map({ word.endIndex > $0 }) ?? true, let token = normalised(word),
                let kind = kind(
                    of: token, at: index, in: words, tokens: tokens, spelledNumbers: numberWords,
                    writesCode: writesCode)
            else { index += 1; continue }
            if writesCode && kind == .number,
                isConventionalCode(token, word: word, after: text[..<word.startIndex])
            {
                index += 1
                continue
            }
            found.append(mention(token, kind: kind, at: index, in: words, tokens: tokens))
            index += 1
        }
        return found
    }

    private static func numericValue(
        at index: Int, tokens: [String], spelledNumbers: Set<Int>
    ) -> (String, Int)? {
        if spelledNumbers.contains(index), let number = cardinal(at: index, in: tokens) {
            return (String(number.value), number.count)
        }
        return NumberWords.digits(tokens[index]).map { (canonicalNumber($0), 1) }
    }

    private static func canonicalNumber(_ token: String) -> String {
        let parts = token.split(separator: ".", omittingEmptySubsequences: false)
        guard parts.count <= 2, parts[0].contains(",") else { return token }
        let groups = parts[0].split(separator: ",", omittingEmptySubsequences: false)
        guard let first = groups.first, (1...3).contains(first.count), first.allSatisfy(\.isNumber),
            groups.dropFirst().allSatisfy({ $0.count == 3 && $0.allSatisfy(\.isNumber) }),
            parts.dropFirst().allSatisfy({ $0.allSatisfy(\.isNumber) })
        else { return token }
        return groups.joined() + (parts.count == 2 ? ".\(parts[1])" : "")
    }

    private static func currencyAmount(
        at index: Int, in words: [Substring], tokens: [String], spelledNumbers: Set<Int>
    ) -> (mention: Mention, endIndex: Int)? {
        guard let number = numericValue(at: index, tokens: tokens, spelledNumbers: spelledNumbers) else {
            return nil
        }
        let unitIndex = index + number.1
        guard unitIndex < words.count, let unit = currencyUnits[tokens[unitIndex]] else { return nil }
        return (Mention(token: "\(number.0) \(unit)", kind: .amount), unitIndex + 1)
    }

    private static func numberMention(
        at index: Int, in words: [Substring], tokens: [String], spelledNumbers: Set<Int>
    ) -> (mention: Mention, endIndex: Int)? {
        guard let number = numericValue(at: index, tokens: tokens, spelledNumbers: spelledNumbers),
            (index..<(index + number.1)).allSatisfy({ spelledNumbers.contains($0) }) || number.1 == 1,
            kind(
                of: tokens[index], at: index, in: words, tokens: tokens, spelledNumbers: spelledNumbers)
                == .number
        else { return nil }
        return (Mention(token: number.0, kind: .number), index + number.1)
    }

    private static func mention(
        _ token: String, kind: Kind, at index: Int, in words: [Substring], tokens: [String]
    ) -> Mention {
        if kind == .address, isBareHost(token) {
            return Mention(token: token.lowercased(), kind: kind)
        }
        if kind == .date, let date = ordinalDate(at: index, in: words, tokens: tokens) {
            return Mention(token: "\(date.day) \(date.month)", kind: kind)
        }
        guard kind == .date, startsANumber(token) else { return Mention(token: token, kind: kind) }
        let neighbors = [
            index > 0 ? words[index - 1] : nil, index + 1 < words.count ? words[index + 1] : nil,
        ]
        for (offset, neighbor) in neighbors.enumerated() {
            guard let number = neighbor.flatMap(normalised), startsANumber(number) else { continue }
            let monthIndex = offset == 0 ? index - 2 : index + 2
            guard words.indices.contains(monthIndex), let month = normalised(words[monthIndex]),
                isCalendarWord(month)
            else { continue }
            let year = canonicalNumber(normalised(token[...]) ?? token)
            return Mention(token: "\(year) \(month) \(canonicalNumber(number))", kind: kind)
        }
        guard let calendarWord = neighbors.compactMap({ $0.flatMap(normalised) }).first(where: isCalendarWord)
        else { return Mention(token: canonicalNumber(normalised(token[...]) ?? token), kind: kind) }
        return Mention(token: "\(token) \(calendarWord)", kind: kind)
    }

    private static func spelledNumberIndices(in tokens: [String]) -> Set<Int> {
        var indices: Set<Int> = []
        for index in tokens.indices {
            guard let number = cardinal(at: index, in: tokens) else { continue }
            indices.formUnion(index..<(index + number.count))
        }
        return indices
    }

    private static func cardinal(at index: Int, in tokens: [String]) -> (value: Int, count: Int)? {
        let expanded = tokens[index...].flatMap {
            $0.split(separator: "-", omittingEmptySubsequences: false).map(String.init)
        }
        guard let value = NumberWords.cardinal(expanded[...]) else { return nil }
        var expandedCount = 0
        for (offset, token) in tokens[index...].enumerated() {
            expandedCount += token.split(separator: "-", omittingEmptySubsequences: false).count
            if expandedCount >= value.count { return (value.value, offset + 1) }
        }
        return nil
    }

    private static func ordinalDate(
        at index: Int, in words: [Substring], tokens: [String]
    ) -> (day: Int, month: String)? {
        let pieces = tokens[index].split(separator: "-", omittingEmptySubsequences: false)
        let ten = pieces.count == 2 ? String(pieces[0]) : tokens[index]
        let unit = pieces.count == 2 ? String(pieces[1]) : tokens.dropFirst(index + 1).first ?? ""
        let day =
            ordinalDays[tokens[index]]
            ?? NumberWords.tens[ten].flatMap { ten in ordinalDays[unit].map { ten + $0 } }
        guard let day, day <= 31 else { return nil }
        let count = pieces.count == 2 || NumberWords.tens[tokens[index]] == nil ? 1 : 2
        let next = index + count
        let monthIndex = [index - 1, next + (tokens.indices.contains(next) && tokens[next] == "of" ? 1 : 0)]
            .first { words.indices.contains($0) && isCalendarWord(tokens[$0]) }
        return monthIndex.map { (day, tokens[$0]) }
    }

    private static func kind(
        of token: String, at index: Int, in words: [Substring], tokens: [String], spelledNumbers: Set<Int>,
        writesCode: Bool = false
    ) -> Kind? {
        if token.contains(where: isAmountSign) {
            return .amount
        }
        if isAddress(token, at: index, in: words, writesCode: writesCode) { return .address }
        if namesCredential(token) { return .credential }
        if isDayPeriod(token, at: index, in: words) || isTimeToken(token) { return .time }
        if isCalendarWord(token) { return .date }
        if ordinalDate(at: index, in: words, tokens: tokens) != nil { return .date }
        if startsANumber(token) {
            if isDateNumber(at: index, in: words) { return .date }
            if Timestamps.isTimestamp(Substring(token)) { return .time }
            return .number
        }
        if spelledNumbers.contains(index) { return .number }
        return nil
    }

    private static func isCalendarWord(_ token: String) -> Bool {
        token.allSatisfy(\.isLetter) && Timestamps.isTimestamp(Substring("\(token) 1"))
    }

    private static func isTimeToken(_ token: String) -> Bool {
        let lowercased = token.lowercased()
        let isDayHalf =
            lowercased == Calendar.current.amSymbol.lowercased()
            || lowercased == Calendar.current.pmSymbol.lowercased()
        let isClock = token.contains(":") && Timestamps.isTimestamp(Substring(token))
        let hasDayHalf = [Calendar.current.amSymbol, Calendar.current.pmSymbol].contains {
            lowercased.hasSuffix($0.lowercased())
                && lowercased.dropLast($0.count).contains(where: \.isNumber)
        }
        return isDayHalf || isClock || hasDayHalf
    }

    private static func isDayPeriod(_ token: String, at index: Int, in words: [Substring]) -> Bool {
        switch token.lowercased() {
        case "afternoon", "dawn", "dusk", "evening", "midnight", "morning", "night", "noon":
            return index == 0 || normalised(words[index - 1]) != "@"
        default: return false
        }
    }

    private static func isDateNumber(at index: Int, in words: [Substring]) -> Bool {
        let neighbors = [
            index > 0 ? words[index - 1] : nil, index + 1 < words.count ? words[index + 1] : nil,
        ]
        if neighbors.contains(where: { word in
            guard let word, let token = normalised(word) else { return false }
            return isCalendarWord(token)
        }) {
            return true
        }
        return neighbors.enumerated().contains { offset, word in
            guard let word, let token = normalised(word), startsANumber(token) else { return false }
            let numberIndex = offset == 0 ? index - 1 : index + 1
            let monthIndex = offset == 0 ? numberIndex - 1 : numberIndex + 1
            guard words.indices.contains(monthIndex), let month = normalised(words[monthIndex])
            else { return false }
            return isCalendarWord(month)
        }
    }

    private static func isAddress(
        _ token: String, at index: Int, in words: [Substring], writesCode: Bool
    ) -> Bool {
        if (token.contains("@") && token.count > 1) || token.contains("://") || token.hasPrefix("www.")
            || isHostPath(token)
        {
            return true
        }
        return isBareHost(token) && !(writesCode && isMemberAccess(at: index, in: words))
    }

    private static func isMemberAccess(at index: Int, in words: [Substring]) -> Bool {
        guard index + 1 < words.count else { return false }
        let next = words[index + 1].trimmingCharacters(in: .whitespacesAndNewlines)
        return ["=", "==", "===", "!=", "(", "[", ",", ";", ")", "?", "+", "-", "*", "/"]
            .contains { next.hasPrefix($0) }
    }

    /// Whether a token names a specific: a number not part of a name, an amount, an address or a credential.
    static func isSpecific(_ token: String) -> Bool {
        let words = [Substring(token)]
        let tokens = words.map { normalised($0) ?? "" }
        let numbers = spelledNumberIndices(in: tokens)
        return kind(of: token, at: 0, in: words, tokens: tokens, spelledNumbers: numbers) != nil
    }

}
