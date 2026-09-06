// Who read a passage and where, and the slug rules the catalogue enforces.
private import Foundation

/// Who read a passage and in what conditions, the axis on which "did it get worse" is answered.
public struct RecordingCohort: Sendable, Equatable, Codable, Identifiable {
    /// Short, stable and URL-safe, because it becomes part of the sample's key in the bucket.
    public let id: String
    /// Who was speaking, as a label rather than a name; nothing about a person belongs in the corpus.
    public let speaker: String
    /// The room and the microphone, which is why a cohort is not simply a speaker.
    public let setting: String

    public init(id: String, speaker: String, setting: String) {
        self.id = id
        self.speaker = speaker
        self.setting = setting
    }

    public var description: String { "\(speaker) · \(setting)" }

    /// What every report calls a recording nobody attributed; never merged with anything.
    public static let unattributed = "unattributed"
}

/// A name the catalogue's `url_slug` domain (`^[a-z0-9][a-z0-9-]{1,63}$`) accepts, checked before recording.
public enum CorpusSlug {
    /// Two characters to sixty-four, and only lowercase letters, digits and hyphens.
    public static func isValid(_ slug: String) -> Bool {
        guard (2...64).contains(slug.count) else { return false }
        guard let first = slug.first, first.isLowercaseASCIILetter || first.isASCIIDigit else {
            return false
        }
        return slug.allSatisfy { $0.isLowercaseASCIILetter || $0.isASCIIDigit || $0 == "-" }
    }

    /// A slug for one passage read by one cohort, cohort first so the bucket sorts by sitting.
    public static func make(passage: String, cohort: String?) -> String {
        let base = [cohort, passage].compactMap(\.self).joined(separator: "-")
        return sanitised(base)
    }

    /// Folds text into the domain's shape without truncating; callers check ``isValid(_:)`` on the result.
    public static func sanitised(_ text: String) -> String {
        var slug = ""
        var lastWasHyphen = false
        for character in text.lowercased() {
            if character.isLowercaseASCIILetter || character.isASCIIDigit {
                slug.append(character)
                lastWasHyphen = false
            } else if !lastWasHyphen, !slug.isEmpty {
                slug.append("-")
                lastWasHyphen = true
            }
        }
        if slug.hasSuffix("-") { slug.removeLast() }
        return slug
    }
}

extension Character {
    /// ASCII only, because the domain is an ASCII regex and a folded "ü" would be refused by Postgres.
    fileprivate var isLowercaseASCIILetter: Bool { "a"..."z" ~= self }
    fileprivate var isASCIIDigit: Bool { "0"..."9" ~= self }
}
