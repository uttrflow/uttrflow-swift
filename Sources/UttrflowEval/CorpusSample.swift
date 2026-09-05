// The catalogue's row types, query and stress vocabulary.
private import Foundation

/// One catalogue row as the backend serves it; anything the harness derives is marked as derived.
public struct CorpusSample: Sendable, Equatable, Codable, Identifiable {
    public let id: String
    /// The catalogue's name for the sample, and the id everything downstream uses.
    public let slug: String
    /// Where the audio lives in the bucket; fetched only through a signed URL from the backend.
    public let s3Key: String
    /// Ground truth — what was actually said.
    public let referenceText: String
    /// What a correct clean-up pass turns the raw transcript into; measured by the transformation half.
    public let expectedTidiedText: String
    /// A BCP-47 tag: `en-GB`, `en-IN`, `hi-IN`.
    public let language: String
    /// What the sample is here to break, in the catalogue's own growing vocabulary.
    public let stresses: [String]
    public let durationMs: Int
    public let sampleRateHz: Int
    /// The object's size once measured, which lets the cache tell a full download from a truncated one.
    public let byteSize: Int?
    /// Set aside from the tuning set, so a threshold cannot be fitted to the samples that judge it.
    public let isHeldOut: Bool
    /// Who read it and in what conditions; `nil` while the catalogue has no column for it.
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

    /// Which of the product's three ways of speaking this is; the code-switching stress decides first.
    public var spokenLanguage: TranscriptionCase.Language {
        if stresses.contains(CorpusStress.codeSwitching) { return .hinglish }
        return language.hasPrefix("hi") ? .hindi : .english
    }

    /// The sample as something the scorer can measure, with the reference filed under its own script.
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

/// Maps the catalogue's stress labels onto this harness's typed ``TranscriptionCase/Stressor``.
public enum CorpusStress {
    public static let codeSwitching = "code-switching"

    /// The labels with a typed equivalent, in the order they are consulted; the first match wins.
    static let mapped: [(label: String, stressor: TranscriptionCase.Stressor)] = [
        ("proper-nouns", .properNouns),
        ("numbers-and-units", .digits),
        ("technical-dictation", .technical),
        ("domain-jargon", .technical),
        ("disfluency", .falseStarts),
        ("punctuation", .everyday),
    ]

    /// The typed stressor for a sample, or ``TranscriptionCase/Stressor/other`` rather than "everyday".
    static func stressor(for stresses: [String]) -> TranscriptionCase.Stressor {
        mapped.first { stresses.contains($0.label) }?.stressor ?? .other
    }
}

/// What the catalogue is asked for; paging is built in because the backend caps a page at 500.
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

    /// The largest page the backend serves, so the paging loop asks for as much as it is allowed.
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
    /// Whether the URL answers with an explanation instead of audio because no bucket is configured.
    public let isPlaceholder: Bool

    public init(slug: String, url: String, expiresInSeconds: Int, isPlaceholder: Bool = false) {
        self.slug = slug
        self.url = url
        self.expiresInSeconds = expiresInSeconds
        self.isPlaceholder = isPlaceholder
    }
}
