// What the user has said about learning from each application, in memory and on disk.
import UttrflowCore
public import Foundation

/// Whether the user has been asked about an application, and what they said.
public enum ConsentState: String, Sendable, Codable, Equatable, CaseIterable {
    /// The user has not been asked about this application.
    case unknown
    /// The user has opted this application in.
    case allowed
    /// The user has said no to this application.
    case declined

    /// How careful this answer is, so folding two spellings of one application never loses a refusal.
    var caution: Int {
        switch self {
        case .unknown: 0
        case .allowed: 1
        case .declined: 2
        }
    }
}

/// What to do about an application, which is to refuse until the user has said otherwise.
public enum ConsentDecision: Sendable, Equatable, CaseIterable {
    /// The user has opted in, so this application may be learned from.
    case proceed
    /// Nothing has been asked yet, so nothing is learned and the user is asked once.
    case refuseAndAsk
    /// The user said no, so nothing is learned and nothing is said about it again.
    case refuseQuietly
}

/// What the user has decided about capture, which is everything that outlives a launch.
public struct CapturePreferences: Sendable, Equatable, Codable {
    /// What was said about each application, keyed by `ApplicationKey` so one app has one answer.
    public private(set) var consent: [String: ConsentState]
    /// Whether the one-time shell history import has already run.
    public var hasImportedShellHistory: Bool

    /// Preferences holding the given answers, filed under one spelling each however they arrived.
    public init(consent: [String: ConsentState] = [:], hasImportedShellHistory: Bool = false) {
        self.consent = Self.folded(consent)
        self.hasImportedShellHistory = hasImportedShellHistory
    }

    /// What was said about one application, which is nothing until it has been asked about.
    public func state(of bundleIdentifier: String) -> ConsentState {
        consent[ApplicationKey.of(bundleIdentifier)] ?? .unknown
    }

    /// One answer per application whatever case the file spells it in, keeping the more careful of two.
    static func folded(_ consent: [String: ConsentState]) -> [String: ConsentState] {
        consent.reduce(into: [:]) { folded, said in
            let key = ApplicationKey.of(said.key)
            guard let kept = folded[key] else { return folded[key] = said.value }
            folded[key] = kept.caution >= said.value.caution ? kept : said.value
        }
    }

    /// What to do in one application, which is the only question the capture path asks of consent.
    public func decision(for bundleIdentifier: String) -> ConsentDecision {
        Self.decision(for: state(of: bundleIdentifier))
    }

    /// The whole of the consent rule, written where it can be read without a store behind it.
    public static func decision(for state: ConsentState) -> ConsentDecision {
        switch state {
        case .allowed: .proceed
        case .unknown: .refuseAndAsk
        case .declined: .refuseQuietly
        }
    }

    /// Records the user's answer about one application, replacing whatever was there.
    public mutating func record(_ state: ConsentState, for bundleIdentifier: String) {
        consent[ApplicationKey.of(bundleIdentifier)] = state
    }

    /// Folds what a file holds as it is read, since a file written before this held both spellings.
    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.init(
            consent: try container.decodeIfPresent([String: ConsentState].self, forKey: .consent)
                ?? [:],
            hasImportedShellHistory: try container.decodeIfPresent(
                Bool.self, forKey: .hasImportedShellHistory) ?? false)
    }
}

/// The preferences on disk, so an answer given once is never asked for twice.
public struct CapturePreferencesFile: Sendable {
    /// The file the answers are read from and written to.
    private let path: String

    /// A file at this path, which need not exist yet.
    public init(path: String) {
        self.path = path
    }

    /// Where the answers live, beside the corpus they gate.
    public static func defaultFile(in directory: URL) -> URL {
        LocalStore.file("predict-consent.v1.json", in: directory)
    }

    /// Reads what was saved, treating a missing or unreadable file as nothing having been said.
    public func load() -> CapturePreferences {
        guard let data = FileManager.default.contents(atPath: path),
            let preferences = try? JSONDecoder().decode(CapturePreferences.self, from: data)
        else { return CapturePreferences() }
        return preferences
    }

    /// Writes what was decided, creating the directory it belongs in when it is not there yet.
    public func save(_ preferences: CapturePreferences) throws {
        try PrivateFile.write(
            JSONEncoder().encode(preferences), to: URL(fileURLWithPath: path))
    }

    /// Deletes every answer, so the applications the loop has met are forgotten with what it learned.
    public func remove() throws {
        do {
            try FileManager.default.removeItem(atPath: path)
        } catch CocoaError.fileNoSuchFile {
            // Already gone, which is what removing it asks for.
        }
    }
}
