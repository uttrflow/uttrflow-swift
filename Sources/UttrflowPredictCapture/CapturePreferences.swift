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
    /// What was said about each application, keyed by bundle identifier.
    public var consent: [String: ConsentState]
    /// Whether the one-time shell history import has already run.
    public var hasImportedShellHistory: Bool

    /// Preferences holding the given answers, defaulting to nothing having been decided.
    public init(consent: [String: ConsentState] = [:], hasImportedShellHistory: Bool = false) {
        self.consent = consent
        self.hasImportedShellHistory = hasImportedShellHistory
    }

    /// What was said about one application, which is nothing until it has been asked about.
    public func state(of bundleIdentifier: String) -> ConsentState {
        consent[bundleIdentifier] ?? .unknown
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
        consent[bundleIdentifier] = state
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
        let directory = (path as NSString).deletingLastPathComponent
        try FileManager.default.createDirectory(
            atPath: directory, withIntermediateDirectories: true)
        try JSONEncoder().encode(preferences).write(to: URL(fileURLWithPath: path), options: .atomic)
    }
}
