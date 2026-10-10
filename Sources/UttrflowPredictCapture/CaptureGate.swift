// Every reason a finished value may not be learned, and the answer the capture path asks for.
private import Foundation
private import UttrflowClipboard
private import UttrflowCore
private import UttrflowPredict
public import UttrflowPredictStore

/// Why a value the user finished entering was not remembered.
public enum CaptureRefusal: String, Sendable, Equatable, CaseIterable {
    /// The field hides what is typed into it, so what it holds is never read.
    case secureField
    /// The user said no to this application.
    case consentDeclined
    /// The value has the shape of a credential.
    case looksLikeSecret
    /// The value is a short grouped digit code in an application that is not a terminal.
    case sensitiveValue
    /// The value would destroy data if it were ever completed and run.
    case destructive
    /// The value is too short to ever be worth completing.
    case tooShort
}

/// Every reason not to write, consulted before a value can reach the corpus.
public enum CaptureGate {
    /// The shortest value worth remembering, below which a completion could never save a keystroke.
    public static let minimumLength = 2

    /// Why this value may not be recorded, or nothing when it may.
    public static func refusal(
        toRecord text: String, from reading: FieldReading, given preferences: CapturePreferences
    ) -> CaptureRefusal? {
        if let refusal = fieldRefusal(reading, given: preferences) { return refusal }
        // A list marker alone, such as `- ` or `1.` ending a list, is too short to be an item.
        guard text.count >= minimumLength, !ListMarker.isAlone(text) else { return .tooShort }
        if looksLikeSensitiveValue(text, from: reading) { return .sensitiveValue }
        if looksLikeSecret(text) { return .looksLikeSecret }
        // A destructive command is never stored, so it can never be one keystroke from running.
        return DestructiveCommand.matches(text, failClosedOnUnresolved: true) ? .destructive : nil
    }

    /// Why an edit inside inserted text may not be heard, checked on the field and on each side's words.
    public static func refusal(
        toHear edit: EditedSpan, from reading: FieldReading, given preferences: CapturePreferences
    ) -> CaptureRefusal? {
        if let refusal = fieldRefusal(reading, given: preferences) { return refusal }
        for side in [edit.old, edit.new] where !side.isEmpty {
            let text = side.joined(separator: " ")
            if looksLikeSensitiveValue(text, from: reading) { return .sensitiveValue }
            if side.contains(where: looksLikeSecret) || looksLikeSecret(text) { return .looksLikeSecret }
        }
        return nil
    }

    /// Why nothing from this field may be kept, whatever it holds: the one consent rule both paths ask.
    private static func fieldRefusal(
        _ reading: FieldReading, given preferences: CapturePreferences
    ) -> CaptureRefusal? {
        guard !reading.isSecure else { return .secureField }
        switch preferences.decision(for: reading.bundleIdentifier) {
        case .refuseQuietly: return .consentDeclined
        case .proceed: return nil
        }
    }

    /// The version of the credential rules, raised whenever their behavior changes so learned lines are swept once.
    public static let secretRulesVersion = 5

    /// Removes every learned line the credential rules now recognise, once per `secretRulesVersion`, and counts them.
    @discardableResult
    public static func sweepSecrets(from store: PredictStore) async throws(PredictStoreError) -> Int {
        try await store.sweep("looksLikeSecret", version: secretRulesVersion) { text, surface in
            let reading = FieldReading(bundleIdentifier: surface.bundleIdentifier, role: surface.role)
            return looksLikeSecret(text) || looksLikeSensitiveValue(text, from: reading)
        }
    }

    /// Whether a value, or any line of it, has the shape of a credential, asked of the clipboard's rules.
    public static func looksLikeSecret(_ text: String) -> Bool {
        // A learned value's lines come back one at a time, so each is judged as the one-line clip it becomes.
        SecretShapes.matches(text)
            || (text.contains(where: \.isNewline)
                && text.split(whereSeparator: \.isNewline).contains { SecretShapes.matches(String($0)) })
    }

    /// Whether a value has the shape of a grouped code, PIN, phone or account number.
    public static func looksLikeSensitiveValue(_ text: String, from reading: FieldReading) -> Bool {
        guard !TerminalApplications.contains(reading.bundleIdentifier) else { return false }
        let trimmed = codeCore(of: text.trimmingCharacters(in: .whitespacesAndNewlines))
        guard !isOrdinaryNumericShape(trimmed) else { return false }
        var digitCount = 0
        var hasDigitSinceSeparator = false
        for character in trimmed {
            if character.isNumber {
                digitCount += 1
                hasDigitSinceSeparator = true
            } else if character.isWhitespace || codeSeparators.contains(character) {
                guard hasDigitSinceSeparator else { return false }
                hasDigitSinceSeparator = false
            } else {
                return false
            }
        }
        return digitCount >= 2 && hasDigitSinceSeparator
    }

    /// The marks that join digit groups in a code, an expiry date or a time.
    private static let codeSeparators: Set<Character> = ["-", ".", "/", ":", "_", ","]

    /// The value without the trailing punctuation or paired parentheses a code is written with.
    private static func codeCore(of text: String) -> String {
        var core = Substring(text)
        while let last = core.last, last.isPunctuation, last != ")" { core.removeLast() }
        let opened = core.filter { $0 == "(" }.count
        guard opened == core.filter({ $0 == ")" }).count else { return String(core) }
        return String(core.filter { $0 != "(" && $0 != ")" })
    }

    private static func isOrdinaryNumericShape(_ text: String) -> Bool {
        let characters = Array(text)

        let pair = text.split(whereSeparator: \.isWhitespace)
        if pair.count == 2, pair.allSatisfy({ $0.count == 2 && $0.allSatisfy(\.isNumber) }) {
            return true
        }

        if let dot = characters.firstIndex(of: "."),
            characters.lastIndex(of: ".") == dot
        {
            let whole = characters[..<dot]
            let fraction = characters[(dot + 1)...]
            if (1...4).contains(whole.count), (1...2).contains(fraction.count),
                whole.allSatisfy(\.isNumber), fraction.allSatisfy(\.isNumber)
            {
                return true
            }
        }

        if characters.count == 10, characters[4] == "-", characters[7] == "-",
            let year = Int(String(characters[0..<4])),
            let month = Int(String(characters[5..<7])),
            let day = Int(String(characters[8..<10])),
            (1...12).contains(month)
        {
            let leapYear = year.isMultiple(of: 400) || (year.isMultiple(of: 4) && !year.isMultiple(of: 100))
            let daysByMonth = [31, leapYear ? 29 : 28, 31, 30, 31, 30, 31, 31, 30, 31, 30, 31]
            return (1...daysByMonth[month - 1]).contains(day)
        }

        return false
    }
}
