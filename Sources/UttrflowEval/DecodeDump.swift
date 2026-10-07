// One decode's per-word evidence, kept beside the corpus so fits never re-decode. See Docs/eval-methodology.md.
public import Foundation
private import CryptoKit

/// Everything that makes two decodes of one recording comparable; a dump is read only under the same identity.
public struct DecodeEngineIdentity: Sendable, Equatable, Codable {
    public let engineVersion: String
    public let weightsRevision: String
    public let tokenizerRevision: String
    /// A digest of the prompt the decoder was primed with, so the prompt itself is never stored.
    public let promptDigest: String
    /// A digest of the decoding options, fallback ladder included.
    public let optionsDigest: String

    public init(
        engineVersion: String, weightsRevision: String, tokenizerRevision: String,
        promptDigest: String, optionsDigest: String
    ) {
        self.engineVersion = engineVersion
        self.weightsRevision = weightsRevision
        self.tokenizerRevision = tokenizerRevision
        self.promptDigest = promptDigest
        self.optionsDigest = optionsDigest
    }

    /// The first field, in declaration order, whose value differs from `other`'s; `nil` when they match.
    public func differingField(from other: Self) -> String? {
        let fields: [(String, String, String)] = [
            ("engineVersion", engineVersion, other.engineVersion),
            ("weightsRevision", weightsRevision, other.weightsRevision),
            ("tokenizerRevision", tokenizerRevision, other.tokenizerRevision),
            ("promptDigest", promptDigest, other.promptDigest),
            ("optionsDigest", optionsDigest, other.optionsDigest),
        ]
        return fields.first { $0.1 != $0.2 }?.0
    }

    /// A short stable name for this identity, used in a dump's file name.
    var fileKey: String {
        let joined = [engineVersion, weightsRevision, tokenizerRevision, promptDigest, optionsDigest]
            .joined(separator: "\u{1F}")
        return SHA256.hash(data: Data(joined.utf8)).prefix(8).map { String(format: "%02x", $0) }.joined()
    }
}

/// A runner-up the decoder weighed at a word's first token.
public struct DecodeAlternative: Sendable, Equatable, Codable {
    public let text: String
    public let logProbability: Double

    public init(text: String, logProbability: Double) {
        self.text = text
        self.logProbability = logProbability
    }
}

/// One recognised word and what the decoder knew about it; absent evidence means "not read", never "certain".
public struct DecodedWord: Sendable, Equatable, Codable {
    public let text: String
    public let start: Double
    public let end: Double
    public let logProbability: Double
    /// The chosen token's log-probability minus the best rival's.
    public let margin: Double?
    /// Entropy in nats over the step's distribution, computed by our own sampler.
    public let entropy: Double?
    public let alternatives: [DecodeAlternative]?

    public init(
        text: String, start: Double, end: Double, logProbability: Double, margin: Double? = nil,
        entropy: Double? = nil, alternatives: [DecodeAlternative]? = nil
    ) {
        self.text = text
        self.start = start
        self.end = end
        self.logProbability = logProbability
        self.margin = margin
        self.entropy = entropy
        self.alternatives = alternatives
    }
}

/// A cache of one decode of one recording: words and evidence, never audio.
public struct DecodeDump: Sendable, Equatable, Codable {
    /// The audio's ``RecordingIdentity`` digest.
    public let recordingIdentity: String
    public let engine: DecodeEngineIdentity
    /// Which rung of the temperature fallback ladder produced the kept decode; 0 is the first try.
    public let fallbackRung: Int
    public let words: [DecodedWord]

    public init(
        recordingIdentity: String, engine: DecodeEngineIdentity, fallbackRung: Int, words: [DecodedWord]
    ) {
        self.recordingIdentity = recordingIdentity
        self.engine = engine
        self.fallbackRung = fallbackRung
        self.words = words
    }
}

/// Why a dump could not be read for a fit.
public enum DecodeDumpError: Error, Sendable, Equatable, CustomStringConvertible {
    case engineMismatch(recordingIdentity: String, field: String)
    case store(EvaluationStoreError)

    public var description: String {
        switch self {
        case .engineMismatch(let recording, let field):
            "dump for \(recording) was decoded under a different engine: \(field) differs"
        case .store(let error): error.description
        }
    }
}

/// Dumps on disk beside the local corpus, one file per decode, never overwritten.
public struct DecodeDumpStore: Sendable {
    /// Inside the local corpus directory, which is never tracked.
    public static let directoryName = "decode-dumps"

    public let directory: URL

    public init(corpusDirectory: URL) {
        directory = corpusDirectory.appending(path: Self.directoryName)
    }

    /// Writes `dump` as a new file and returns it with its size; an earlier decode is never replaced.
    @discardableResult
    public func save(_ dump: DecodeDump) throws(DecodeDumpError) -> (url: URL, bytes: Int) {
        let encoder = JSONEncoder()
        encoder.outputFormatting = .readable
        let data: Data
        do {
            data = try encoder.encode(dump)
        } catch {
            throw .store(.couldNotWrite(path: directory.path, reason: "\(error)"))
        }
        let stem = "\(Self.fileStem(dump.recordingIdentity))-\(dump.engine.fileKey)"
        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        } catch {
            throw .store(.couldNotWrite(path: directory.path, reason: "\(error)"))
        }
        var take = 1
        while true {
            let url = directory.appending(path: "\(stem)-\(take).json")
            guard !FileManager.default.fileExists(atPath: url.path) else {
                take += 1
                continue
            }
            do {
                // Creating only when absent keeps two writers from replacing each other's decode.
                try data.write(to: url, options: .withoutOverwriting)
                return (url, data.count)
            } catch  where FileManager.default.fileExists(atPath: url.path) {
                take += 1
            } catch {
                throw .store(.couldNotWrite(path: url.lastPathComponent, reason: "\(error)"))
            }
        }
    }

    /// Every dump decoded under `engine`; any other identity is refused, naming the field that differs.
    public func dumps(decodedUnder engine: DecodeEngineIdentity) throws(DecodeDumpError) -> [DecodeDump] {
        guard FileManager.default.fileExists(atPath: directory.path) else { return [] }
        let files: [URL]
        do {
            files = try FileManager.default.contentsOfDirectory(
                at: directory, includingPropertiesForKeys: nil
            )
            .filter { $0.pathExtension == "json" }
            .sorted { $0.lastPathComponent < $1.lastPathComponent }
        } catch {
            throw .store(.couldNotRead(path: directory.path, reason: "\(error)"))
        }
        var dumps: [DecodeDump] = []
        for file in files {
            guard let data = FileManager.default.contents(atPath: file.path) else {
                throw .store(.couldNotRead(path: file.lastPathComponent, reason: "unreadable file"))
            }
            let dump: DecodeDump
            do {
                dump = try JSONDecoder().decode(DecodeDump.self, from: data)
            } catch {
                throw .store(.couldNotRead(path: file.lastPathComponent, reason: "\(error)"))
            }
            if let field = dump.engine.differingField(from: engine) {
                throw .engineMismatch(recordingIdentity: dump.recordingIdentity, field: field)
            }
            dumps.append(dump)
        }
        return dumps
    }

    private static func fileStem(_ recordingIdentity: String) -> String {
        String(recordingIdentity.map { $0.isLetter || $0.isNumber ? $0 : "-" })
    }
}
