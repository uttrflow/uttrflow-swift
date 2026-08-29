private import Foundation

/// One sample in the catalogue the backend serves.
///
/// A faithful mirror of the row rather than a convenient reshaping of it. The corpus is
/// curated in a database that several tools read, and a client that quietly renamed or
/// dropped fields would be the reason two of those tools disagree about what a sample
/// is. Anything this harness wants that the row does not have — a cohort, a script — is
/// derived below and marked as derived.
public struct CorpusSample: Sendable, Equatable, Codable, Identifiable {
    public let id: String
    /// The catalogue's name for the sample, and the id everything downstream uses.
    public let slug: String
    /// Where the audio lives in the bucket. Never fetched directly: the harness has no
    /// credentials and asks the backend for a signed URL instead.
    public let s3Key: String
    /// Ground truth — what was actually said.
    public let referenceText: String
    /// What a correct clean-up pass should turn the raw transcript into. Measured by
    /// the transformation half of the harness, not by this one.
    public let expectedTidiedText: String
    /// A BCP-47 tag: `en-GB`, `en-IN`, `hi-IN`.
    public let language: String
    /// What the sample is here to break, in the catalogue's vocabulary, which is wider
    /// than ``TranscriptionCase/Stressor`` and will keep growing. Kept as written, so
    /// that adding a stress to the corpus does not require editing an enum here first.
    public let stresses: [String]
    public let durationMs: Int
    public let sampleRateHz: Int
    /// `nil` until the object has been measured. Used to tell a complete download from
    /// a truncated one, so its absence means the cache can only check presence.
    public let byteSize: Int?
    /// Set aside from the tuning set, so a threshold cannot be fitted to the samples
    /// that also judge it.
    public let isHeldOut: Bool
    /// Who read it and in what conditions.
    ///
    /// Decoded if present and otherwise `nil`: the catalogue has no column for it yet,
    /// and a harness that refused to read the corpus until it did would be holding the
    /// corpus hostage to a migration. Recordings made by ``CorpusUploadOutbox`` carry
    /// one, and everything reports it as unattributed until the column exists.
    public let cohort: String?

    public init(
        id: String,
        slug: String,
        s3Key: String,
        referenceText: String,
        expectedTidiedText: String,
        language: String,
        stresses: [String],
        durationMs: Int,
        sampleRateHz: Int,
        byteSize: Int? = nil,
        isHeldOut: Bool = false,
        cohort: String? = nil
    ) {
        self.id = id
        self.slug = slug
        self.s3Key = s3Key
        self.referenceText = referenceText
        self.expectedTidiedText = expectedTidiedText
        self.language = language
        self.stresses = stresses
        self.durationMs = durationMs
        self.sampleRateHz = sampleRateHz
        self.byteSize = byteSize
        self.isHeldOut = isHeldOut
        self.cohort = cohort
    }

    public var duration: Duration { .milliseconds(durationMs) }

    /// Which of the product's three ways of speaking this is.
    ///
    /// Derived, because BCP-47 has no tag for Hinglish and the catalogue therefore
    /// cannot carry one. A code-switched sample is Hinglish whichever base tag it
    /// files under — the whole point of the category is that it is neither language
    /// on its own — so that stress decides first.
    public var spokenLanguage: TranscriptionCase.Language {
        if stresses.contains(CorpusStress.codeSwitching) { return .hinglish }
        return language.hasPrefix("hi") ? .hindi : .english
    }

    /// The sample as something the scorer can measure against.
    ///
    /// The reference is filed under the script it is actually written in, so a
    /// Devanagari reference is not scored against a Latin transcript and the other way
    /// round. See ``TranscriptionScorer`` for why comparing across scripts measures a
    /// transliterator rather than a recogniser.
    public var passage: TranscriptionCase {
        let script = Script.of(referenceText)
        return TranscriptionCase(
            id: slug,
            language: spokenLanguage,
            stressor: CorpusStress.stressor(for: stresses),
            romanised: script == .latin ? referenceText : "",
            devanagari: script == .devanagari ? referenceText : nil,
            stresses: stresses
        )
    }
}

/// The catalogue's stress vocabulary, and how it lines up with this harness's.
///
/// Two vocabularies rather than one, and deliberately so. The catalogue's is curated
/// alongside a thousand recordings and grows whenever somebody finds a new way to break
/// a recogniser; this harness's five are the ones the hand-written passages were built
/// around. Reporting is done on the catalogue's labels — see
/// ``TranscriptionReport/byStress`` — and this mapping exists only so a remote sample
/// still has a value for the typed axis the local corpus reports on.
public enum CorpusStress {
    public static let codeSwitching = "code-switching"

    /// The catalogue labels this harness has a typed equivalent for, in the order they
    /// are consulted. Order matters: a sample stressing both proper nouns and numbers
    /// files under the first, and doing that consistently is worth more than doing it
    /// cleverly.
    static let mapped: [(label: String, stressor: TranscriptionCase.Stressor)] = [
        ("proper-nouns", .properNouns),
        ("numbers-and-units", .digits),
        ("technical-dictation", .technical),
        ("domain-jargon", .technical),
        ("disfluency", .falseStarts),
        ("punctuation", .everyday),
    ]

    /// - Returns: The typed stressor for a catalogue sample, or ``TranscriptionCase/Stressor/other``
    ///   when the catalogue is stressing something this enum has no word for. Reported
    ///   as "other" rather than folded into "everyday": an accented or noisy sample is
    ///   not an easy one, and filing it under the floor category would flatter the
    ///   number that the floor exists to set.
    static func stressor(for stresses: [String]) -> TranscriptionCase.Stressor {
        mapped.first { stresses.contains($0.label) }?.stressor ?? .other
    }
}

/// What the catalogue was asked for.
///
/// Paging is not optional at a thousand samples — the backend caps a page at 500 — so
/// the query carries it, and ``CorpusCatalogue/allSamples(matching:)`` is the thing
/// everyday callers use so that forgetting to page is not possible.
public struct CorpusQuery: Sendable, Equatable {
    /// A BCP-47 tag, matched exactly by the backend.
    public var language: String?
    /// One of the catalogue's stress labels.
    public var stress: String?
    public var heldOut: Bool?
    public var limit: Int?
    public var offset: Int?

    public init(
        language: String? = nil,
        stress: String? = nil,
        heldOut: Bool? = nil,
        limit: Int? = nil,
        offset: Int? = nil
    ) {
        self.language = language
        self.stress = stress
        self.heldOut = heldOut
        self.limit = limit
        self.offset = offset
    }

    /// The largest page the backend will serve. Named here so the paging loop asks for
    /// as much as it is allowed rather than for a number somebody guessed.
    public static let maximumPageSize = 500
}

/// One page of the catalogue, with the size of the whole thing.
public struct CorpusPage: Sendable, Equatable, Codable {
    public let total: Int
    public let count: Int
    public let samples: [CorpusSample]

    public init(total: Int, count: Int, samples: [CorpusSample]) {
        self.total = total
        self.count = count
        self.samples = samples
    }
}

/// Permission to read one object for a short while.
public struct CorpusDownload: Sendable, Equatable, Codable {
    public let slug: String
    public let url: String
    public let expiresInSeconds: Int
    /// The backend has no bucket configured and this URL answers with an explanation
    /// rather than audio. Reported rather than followed: a run against a placeholder
    /// produces a directory of 501 pages that every later stage then misreads as
    /// unreadable audio.
    public let isPlaceholder: Bool

    public init(slug: String, url: String, expiresInSeconds: Int, isPlaceholder: Bool = false) {
        self.slug = slug
        self.url = url
        self.expiresInSeconds = expiresInSeconds
        self.isPlaceholder = isPlaceholder
    }
}
