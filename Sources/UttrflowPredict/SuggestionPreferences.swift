public import struct Foundation.Date
public import struct Foundation.TimeInterval

/// One application the suggestions screen lists, and the name it is listed under.
public struct SuggestionApplication: Sendable, Equatable, Hashable {
    /// Lowercased, because a bundle identifier is compared and never read out.
    public let bundleIdentifier: String

    /// What the list calls it, since a bundle identifier is not a name anybody recognises.
    public let name: String

    public init(bundleIdentifier: String, name: String) {
        self.bundleIdentifier = bundleIdentifier.lowercased()
        self.name = name
    }
}

/// The applications tab-to-complete ships switched off in, and how any application is named.
public enum SuggestionApplications {
    /// The four editors that already complete from the whole file, named rather than matched so every one of them stays findable.
    public static let offByDefault: [SuggestionApplication] = [
        SuggestionApplication(bundleIdentifier: "com.microsoft.vscode", name: "Visual Studio Code"),
        SuggestionApplication(bundleIdentifier: "com.todesktop.230313mzl4w4u92", name: "Cursor"),
        SuggestionApplication(bundleIdentifier: "com.apple.dt.xcode", name: "Xcode"),
        SuggestionApplication(bundleIdentifier: "dev.zed.zed", name: "Zed"),
    ]

    /// Whether this application is one of the four, compared the way identifiers compare.
    public static func isOffByDefault(_ bundleIdentifier: String) -> Bool {
        let identifier = bundleIdentifier.lowercased()
        return offByDefault.contains { $0.bundleIdentifier == identifier }
    }

    /// What to call an application: the shipped name where there is one, else the identifier's tail.
    public static func name(of bundleIdentifier: String) -> String {
        let identifier = bundleIdentifier.lowercased()
        if let known = offByDefault.first(where: { $0.bundleIdentifier == identifier }) {
            return known.name
        }
        guard let tail = bundleIdentifier.split(separator: ".").last, !tail.isEmpty else {
            return bundleIdentifier
        }
        return tail.prefix(1).uppercased() + tail.dropFirst()
    }
}

/// Whether suggestions run in one application, and which of the three reasons it is.
public enum SuggestionApplicationState: Sendable, Equatable, CaseIterable {
    /// Nothing says otherwise, so suggestions run here.
    case on
    /// The user switched this application off, and it stays off across launches.
    case turnedOff
    /// One of the shipped editors, off until the user asks for it.
    case offByDefault

    public var isOn: Bool { self == .on }
}

/// Everything the user has decided about tab-to-complete, off until they ask for it.
public struct SuggestionPreferences: Sendable, Equatable, Codable {
    /// How long a pause everywhere lasts before it lifts itself.
    public static let pause: TimeInterval = 30 * 60

    /// Whether tab-to-complete runs at all, which it does not until the user turns it on.
    public var isEnabled: Bool

    /// The applications the user switched off, keyed lowercased as identifiers compare.
    public var turnedOff: Set<String>

    /// The applications the user switched back on, which is the only way out of ``SuggestionApplications/offByDefault``.
    public var turnedOn: Set<String>

    /// The accept key the user chose per application, over the shipped answer.
    public var chosenAcceptKeys: [String: AcceptKey]

    /// Whether only a completion it is sure of may be drawn, never a list to choose from.
    public var isQuiet: Bool

    /// When a pause everywhere runs out, held as a deadline so it expires by being compared against the moment rather than by a timer remembering to fire.
    public var pausedUntil: Date?

    public init(
        isEnabled: Bool = false,
        turnedOff: Set<String> = [],
        turnedOn: Set<String> = [],
        chosenAcceptKeys: [String: AcceptKey] = [:],
        isQuiet: Bool = false,
        pausedUntil: Date? = nil
    ) {
        self.isEnabled = isEnabled
        self.turnedOff = Set(turnedOff.map { $0.lowercased() })
        self.turnedOn = Set(turnedOn.map { $0.lowercased() })
        self.chosenAcceptKeys = chosenAcceptKeys.reduce(into: [:]) {
            $0[$1.key.lowercased()] = $1.value
        }
        self.isQuiet = isQuiet
        self.pausedUntil = pausedUntil
    }

    /// What a user gets before they have chosen anything, which is a feature that draws nothing.
    public static let `default` = SuggestionPreferences()

    // MARK: - Reading

    /// Whether a pause is still running at this moment.
    public func isPaused(at moment: Date) -> Bool {
        guard let pausedUntil else { return false }
        return moment < pausedUntil
    }

    /// How much of a pause is left, or nothing once it has run out.
    public func pauseRemaining(at moment: Date) -> TimeInterval? {
        guard let pausedUntil, moment < pausedUntil else { return nil }
        return pausedUntil.timeIntervalSince(moment)
    }

    /// Why suggestions do or do not run in one application, the master switch aside.
    public func state(of bundleIdentifier: String) -> SuggestionApplicationState {
        let identifier = bundleIdentifier.lowercased()
        if turnedOff.contains(identifier) { return .turnedOff }
        if turnedOn.contains(identifier) { return .on }
        return SuggestionApplications.isOffByDefault(identifier) ? .offByDefault : .on
    }

    /// Whether anything may be drawn in one application right now, which is the whole rule.
    public func isEnabled(in bundleIdentifier: String, at moment: Date) -> Bool {
        isEnabled && !isPaused(at: moment) && state(of: bundleIdentifier).isOn
    }

    /// The accept keys in force: the shipped answer with the user's choices on top.
    public var acceptKeys: AcceptKeys {
        AcceptKeys(overrides: chosenAcceptKeys)
    }

    /// Every application the screen has something to say about, the shipped editors always among them so a switch that ships off can still be found.
    public func knownApplications(learnedIn learned: Set<String> = []) -> [SuggestionApplication] {
        var identifiers = Set(SuggestionApplications.offByDefault.map(\.bundleIdentifier))
        identifiers.formUnion(turnedOff)
        identifiers.formUnion(turnedOn)
        identifiers.formUnion(chosenAcceptKeys.keys)
        identifiers.formUnion(learned.map { $0.lowercased() })
        return
            identifiers
            .map {
                SuggestionApplication(
                    bundleIdentifier: $0, name: SuggestionApplications.name(of: $0))
            }
            .sorted {
                ($0.name.lowercased(), $0.bundleIdentifier)
                    < ($1.name.lowercased(), $1.bundleIdentifier)
            }
    }

    // MARK: - Writing

    /// Switches one application on or off, dropping whichever of the two it said before.
    public mutating func set(_ bundleIdentifier: String, isOn: Bool) {
        let identifier = bundleIdentifier.lowercased()
        turnedOff.remove(identifier)
        turnedOn.remove(identifier)
        if isOn {
            turnedOn.insert(identifier)
        } else {
            turnedOff.insert(identifier)
        }
    }

    /// Chooses the key that accepts a suggestion in one application.
    public mutating func setAcceptKey(_ key: AcceptKey, in bundleIdentifier: String) {
        chosenAcceptKeys[bundleIdentifier.lowercased()] = key
    }

    /// Starts a pause everywhere, or lifts one that is still running.
    public mutating func setPaused(_ isPaused: Bool, at moment: Date) {
        pausedUntil = isPaused ? moment.addingTimeInterval(Self.pause) : nil
    }
}
