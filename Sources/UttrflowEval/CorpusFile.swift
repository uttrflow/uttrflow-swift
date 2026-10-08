// Evaluation cases kept as data, one JSON file per category, read and validated here.
import Foundation
import UttrflowCore

/// Cases from `Resources/Corpus/<category>.json` or `<category>.<set>.json`: `id`, `spoken`, `expected` required.
enum CorpusFile {
    /// Why a corpus file could not be read, naming the case where there is one.
    struct Failure: Error, Equatable, CustomStringConvertible {
        let category: EvaluationCase.Category
        let caseID: String?
        let reason: String

        var description: String {
            "corpus \(category.rawValue)\(caseID.map { " case \($0)" } ?? ""): \(reason)"
        }
    }

    /// The cases of one category or set, or none when its file fails to load; `load(_:set:)` says why.
    static func cases(in category: EvaluationCase.Category, set: String? = nil) -> [EvaluationCase] {
        (try? load(category, set: set)) ?? []
    }

    /// The cases of one category or set, read from the bundled file and validated.
    static func load(_ category: EvaluationCase.Category, set: String? = nil) throws -> [EvaluationCase] {
        let name = [category.rawValue, set].compactMap(\.self).joined(separator: ".")
        guard
            let path = Bundle.module.path(forResource: name, ofType: "json", inDirectory: "Corpus"),
            let data = FileManager.default.contents(atPath: path)
        else { throw Failure(category: category, caseID: nil, reason: "no file") }
        return try decode(data, as: category)
    }

    /// Every bundled file's name without its extension, so each can be loaded and checked by name.
    static var bundledNames: [String] {
        Bundle.module.paths(forResourcesOfType: "json", inDirectory: "Corpus")
            .map { URL(fileURLWithPath: $0).deletingPathExtension().lastPathComponent }.sorted()
    }

    /// The cases in one file's bytes, refused whole if any case breaks the schema.
    static func decode(_ data: Data, as category: EvaluationCase.Category) throws -> [EvaluationCase] {
        let records: [Record]
        do {
            records = try JSONDecoder().decode([Record].self, from: data)
        } catch {
            throw Failure(category: category, caseID: nil, reason: "unreadable: \(error)")
        }
        var seen: Set<String> = []
        return try records.map { record in
            guard seen.insert(record.id).inserted else {
                throw Failure(category: category, caseID: record.id, reason: "duplicate id")
            }
            return try record.evaluationCase(category: category)
        }
    }

    /// One case as written in a file.
    struct Record: Decodable {
        let id: String
        /// Why the case exists, for whoever reads the file; never scored.
        let note: String?
        let spoken: String
        let expected: String
        let language: String?
        let origin: EvaluationCase.Origin?
        let addedFor: Int?
        let mustKeep: [String]?
        let mustNotAdd: [String]?
        let context: Context?
        let destination: Destination?
        let mustBeginWith: String?
        let mustEndWith: String?
        let expectedExact: String?
        let doubtful: [String]?
        let pausedAfter: [Int]?
        let minimumSentences: Int?
        let classes: [FormattingClass]?

        enum CodingKeys: String, CodingKey, CaseIterable {
            case id, note, spoken, expected, language, origin, addedFor, mustKeep, mustNotAdd, context
            case destination, mustBeginWith, mustEndWith, expectedExact, doubtful, pausedAfter
            case minimumSentences, classes
        }

        init(from decoder: any Decoder) throws {
            try RefusesUnknownKeys.check(decoder, allowed: CodingKeys.allCases.map(\.rawValue))
            let values = try decoder.container(keyedBy: CodingKeys.self)
            id = try values.decode(String.self, forKey: .id)
            note = try values.decodeIfPresent(String.self, forKey: .note)
            spoken = try values.decode(String.self, forKey: .spoken)
            expected = try values.decode(String.self, forKey: .expected)
            language = try values.decodeIfPresent(String.self, forKey: .language)
            origin = try values.decodeIfPresent(EvaluationCase.Origin.self, forKey: .origin)
            addedFor = try values.decodeIfPresent(Int.self, forKey: .addedFor)
            mustKeep = try values.decodeIfPresent([String].self, forKey: .mustKeep)
            mustNotAdd = try values.decodeIfPresent([String].self, forKey: .mustNotAdd)
            context = try values.decodeIfPresent(Context.self, forKey: .context)
            destination = try values.decodeIfPresent(Destination.self, forKey: .destination)
            mustBeginWith = try values.decodeIfPresent(String.self, forKey: .mustBeginWith)
            mustEndWith = try values.decodeIfPresent(String.self, forKey: .mustEndWith)
            expectedExact = try values.decodeIfPresent(String.self, forKey: .expectedExact)
            doubtful = try values.decodeIfPresent([String].self, forKey: .doubtful)
            pausedAfter = try values.decodeIfPresent([Int].self, forKey: .pausedAfter)
            minimumSentences = try values.decodeIfPresent(Int.self, forKey: .minimumSentences)
            classes = try values.decodeIfPresent([FormattingClass].self, forKey: .classes)
        }

        func evaluationCase(category: EvaluationCase.Category) throws -> EvaluationCase {
            func refuse(_ reason: String) -> Failure {
                Failure(category: category, caseID: id, reason: reason)
            }
            guard !id.isEmpty, !spoken.isEmpty, !expected.isEmpty else {
                throw refuse("empty id, spoken or expected")
            }
            var code = LanguageCode.english
            if let language {
                guard let parsed = LanguageCode(language) else { throw refuse("bad language \(language)") }
                code = parsed
            }
            let keep = mustKeep ?? []
            // Read as the scorer reads it, so a reference that would lose its own required word is refused.
            if let missing = Scorer.lost(keep, in: expected).first {
                throw refuse("mustKeep word \"\(missing)\" is not in expected")
            }
            return EvaluationCase(
                id: id, category: category, language: code, spoken: spoken, expected: expected,
                mustKeep: keep, context: context?.appContext ?? .unknown, mustNotAdd: mustNotAdd ?? [],
                destination: destination ?? .plain, mustBeginWith: mustBeginWith, mustEndWith: mustEndWith,
                minimumSentences: minimumSentences, expectedExact: expectedExact, doubtful: doubtful ?? [],
                classes: classes ?? [], pausedAfter: pausedAfter ?? [],
                origin: origin ?? .authored, addedFor: addedFor)
        }
    }

    /// The part of `AppContext` a case can state; every value in it is invented.
    struct Context: Decodable {
        let applicationName: String?
        let bundleIdentifier: String?
        let documentName: String?
        let pageAddress: String?
        let selectedText: String?
        let precedingText: String?
        let followingText: String?
        let accessibilityRole: String?
        let isMultiline: Bool?
        let fieldLabel: String?

        enum CodingKeys: String, CodingKey, CaseIterable {
            case applicationName, bundleIdentifier, documentName, pageAddress, selectedText
            case precedingText, followingText, accessibilityRole, isMultiline, fieldLabel
        }

        init(from decoder: any Decoder) throws {
            try RefusesUnknownKeys.check(decoder, allowed: CodingKeys.allCases.map(\.rawValue))
            let values = try decoder.container(keyedBy: CodingKeys.self)
            applicationName = try values.decodeIfPresent(String.self, forKey: .applicationName)
            bundleIdentifier = try values.decodeIfPresent(String.self, forKey: .bundleIdentifier)
            documentName = try values.decodeIfPresent(String.self, forKey: .documentName)
            pageAddress = try values.decodeIfPresent(String.self, forKey: .pageAddress)
            selectedText = try values.decodeIfPresent(String.self, forKey: .selectedText)
            precedingText = try values.decodeIfPresent(String.self, forKey: .precedingText)
            followingText = try values.decodeIfPresent(String.self, forKey: .followingText)
            accessibilityRole = try values.decodeIfPresent(String.self, forKey: .accessibilityRole)
            isMultiline = try values.decodeIfPresent(Bool.self, forKey: .isMultiline)
            fieldLabel = try values.decodeIfPresent(String.self, forKey: .fieldLabel)
        }

        var appContext: AppContext {
            AppContext(
                applicationName: applicationName, bundleIdentifier: bundleIdentifier,
                documentName: documentName,
                pageAddress: pageAddress, selectedText: selectedText, precedingText: precedingText,
                followingText: followingText, accessibilityRole: accessibilityRole, isMultiline: isMultiline,
                fieldLabel: fieldLabel)
        }
    }

    /// Refuses an object carrying a key the schema does not name, so a misspelt field fails rather than vanishing.
    enum RefusesUnknownKeys {
        struct AnyKey: CodingKey {
            let stringValue: String
            var intValue: Int? { nil }
            init(stringValue: String) { self.stringValue = stringValue }
            init?(intValue _: Int) { nil }
        }

        static func check(_ decoder: any Decoder, allowed: [String]) throws {
            let keys = try decoder.container(keyedBy: AnyKey.self).allKeys.map(\.stringValue)
            if let unknown = keys.first(where: { !allowed.contains($0) }) {
                throw DecodingError.dataCorrupted(
                    .init(codingPath: decoder.codingPath, debugDescription: "unknown key \(unknown)"))
            }
        }
    }
}
