private import Foundation

/// Who read a passage, and in what conditions.
///
/// The third axis the corpus has to be reported on, and the one that only appears once
/// it is large. Eighteen passages read by one person in one room have no cohorts; a
/// thousand read over weeks have several, and a headline word error rate over the lot
/// answers no question anybody has. "Did it get worse" is only a question about a
/// cohort: worse for the second speaker, worse in a noisy room, worse on the laptop
/// microphone. Averaging those together is how a regression in one of them hides behind
/// an improvement in another.
public struct RecordingCohort: Sendable, Equatable, Codable, Identifiable {
    /// Short, stable, and safe in a URL, because it becomes part of the sample's slug
    /// and therefore part of its key in the bucket.
    public let id: String
    /// Who was speaking. A label, not a name: the corpus is a measurement, and the
    /// backend's own privacy rules say nothing about a person belongs in it.
    public let speaker: String
    /// The room and the microphone. What actually distinguishes two sittings by the same
    /// person, and the reason a cohort is not simply a speaker.
    public let setting: String

    public init(id: String, speaker: String, setting: String) {
        self.id = id
        self.speaker = speaker
        self.setting = setting
    }

    public var description: String { "\(speaker) · \(setting)" }

    /// What every report calls a recording nobody attributed.
    ///
    /// Named rather than left blank, and never quietly merged with anything: an
    /// unattributed row is a gap in the corpus's bookkeeping, and it should look like
    /// one.
    public static let unattributed = "unattributed"
}

/// A name the corpus catalogue will accept.
///
/// The backend's `url_slug` domain is `^[a-z0-9][a-z0-9-]{1,63}$`, enforced by a CHECK
/// constraint. Checking it here, before a passage is read aloud, is the whole point: a
/// slug rejected at upload time is rejected after somebody has already spoken, at the
/// end of a sitting, when the useful moment to fix it has passed.
public enum CorpusSlug {
    /// Two characters to sixty-four, and only lowercase letters, digits and hyphens.
    public static func isValid(_ slug: String) -> Bool {
        guard (2...64).contains(slug.count) else { return false }
        guard let first = slug.first, first.isLowercaseASCIILetter || first.isASCIIDigit else {
            return false
        }
        return slug.allSatisfy { $0.isLowercaseASCIILetter || $0.isASCIIDigit || $0 == "-" }
    }

    /// A slug for one passage read by one cohort.
    ///
    /// Cohort first, so the bucket sorts by sitting and a session that has to be thrown
    /// away can be found by eye. Unattributed recordings keep the passage id alone
    /// rather than gaining an `unattributed-` prefix — that prefix would become part of
    /// the key, and renaming a thousand objects later to attribute them is not a thing
    /// anybody does.
    public static func make(passage: String, cohort: String?) -> String {
        let base = [cohort, passage].compactMap(\.self).joined(separator: "-")
        return sanitised(base)
    }

    /// Folds anything a person might type into the shape the domain allows.
    ///
    /// Lossy on purpose and never silently: callers check ``isValid(_:)`` on the result,
    /// so a label that folds away to nothing — or to something too long — is refused
    /// rather than turned into a slug that no longer identifies anything.
    ///
    /// Deliberately does **not** truncate to the domain's sixty-four characters. Two long
    /// cohort names that agree in their first sixty-four would produce one slug, and the
    /// catalogue upserts by slug: the second sitting would overwrite the first in the
    /// bucket, silently, and the corpus would be smaller than anybody believed. Refusing
    /// the name is the only safe answer.
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
    /// ASCII only, deliberately. The domain is an ASCII regex, so folding "ü" to a
    /// letter here would produce a slug Postgres then refuses.
    fileprivate var isLowercaseASCIILetter: Bool { "a"..."z" ~= self }
    fileprivate var isASCIIDigit: Bool { "0"..."9" ~= self }
}
