import Synchronization
import UttrflowCore
public import struct Foundation.Date
public import struct Foundation.TimeInterval

/// One application the suggestions screen lists, and the name it is listed under.
public struct SuggestionApplication: Sendable, Equatable, Hashable {
    /// Lowercased, because a bundle identifier is compared and never read out.
    public let bundleIdentifier: String

    /// What the list calls it, since a bundle identifier is not a name anybody recognises.
    public let name: String

    /// One application as the screen lists it, its identifier lowercased for comparing.
    public init(bundleIdentifier: String, name: String) {
        self.bundleIdentifier = ApplicationKey.of(bundleIdentifier)
        self.name = name
    }
}

/// The applications tab-to-complete ships switched off in, and how any application is named.
public enum SuggestionApplications {
    /// Editors with suggestions of their own, named rather than matched so each stays findable.
    public static let offByDefault: [SuggestionApplication] = DestinationRules.inlineCompletionEditors
        .map { SuggestionApplication(bundleIdentifier: $0.bundleIdentifier, name: $0.name) }

    /// Password managers, remote-desktop clients and virtual machines, whose ordinary fields still hold what is private.
    public static let privateByDefault: [SuggestionApplication] = [
        SuggestionApplication(bundleIdentifier: "com.1password.1password", name: "1Password"),
        SuggestionApplication(bundleIdentifier: "com.agilebits.onepassword7", name: "1Password 7"),
        SuggestionApplication(bundleIdentifier: "com.bitwarden.desktop", name: "Bitwarden"),
        SuggestionApplication(bundleIdentifier: "org.keepassxc.keepassxc", name: "KeePassXC"),
        SuggestionApplication(bundleIdentifier: "com.apple.keychainaccess", name: "Keychain Access"),
        SuggestionApplication(bundleIdentifier: "com.apple.Passwords", name: "Passwords"),
        SuggestionApplication(bundleIdentifier: "com.apple.ScreenSharing", name: "Screen Sharing"),
        SuggestionApplication(bundleIdentifier: "com.microsoft.rdc.macos", name: "Windows App"),
        SuggestionApplication(bundleIdentifier: "com.parallels.desktop.console", name: "Parallels Desktop"),
        SuggestionApplication(bundleIdentifier: "com.vmware.fusion", name: "VMware Fusion"),
        SuggestionApplication(bundleIdentifier: "com.utmapp.UTM", name: "UTM"),
    ]

    /// Every application that ships switched off, for whichever reason.
    public static var shippedOff: [SuggestionApplication] { offByDefault + privateByDefault }

    /// Whether this application ships switched off, compared the way identifiers compare.
    public static func isOffByDefault(_ bundleIdentifier: String) -> Bool {
        let identifier = ApplicationKey.of(bundleIdentifier)
        return shippedOff.contains { $0.bundleIdentifier == identifier }
    }

    /// Whether this application ships switched off because what it holds is private.
    public static func isPrivateByDefault(_ bundleIdentifier: String) -> Bool {
        let identifier = ApplicationKey.of(bundleIdentifier)
        return privateByDefault.contains { $0.bundleIdentifier == identifier }
    }

    /// Where the app looks up an installed application's own name; nothing installed means the fallback alone.
    private static let installedNames = Mutex<(@Sendable (String) -> String?)?>(nil)

    /// Sets how an installed application's own name is found, which the app does once at launch.
    public static func lookUpInstalledNames(with lookup: @escaping @Sendable (String) -> String?) {
        installedNames.withLock { $0 = lookup }
    }

    /// What to call an application: its installed name, else the shipped name, else the identifier's tail.
    public static func name(of bundleIdentifier: String) -> String {
        let lookup = installedNames.withLock { $0 }
        return name(of: bundleIdentifier, installed: [lookup?(bundleIdentifier)])
    }

    /// Names an application by the first usable installed name, trusted in the order given, before any fallback.
    public static func name(of bundleIdentifier: String, installed candidates: [String?]) -> String {
        if let installed = firstUsable(candidates) { return installed }
        return fallbackName(of: bundleIdentifier)
    }

    /// The first candidate with something in it once trimmed, and without a trailing ".app".
    public static func firstUsable(_ candidates: [String?]) -> String? {
        for case let text? in candidates {
            guard let start = text.firstIndex(where: { !$0.isWhitespace }),
                let end = text.lastIndex(where: { !$0.isWhitespace })
            else { continue }
            var name = String(text[start...end])
            if name.lowercased().hasSuffix(".app") { name = String(name.dropLast(4)) }
            if !name.isEmpty { return name }
        }
        return nil
    }

    /// The shipped name where there is one, else the identifier's tail capitalised.
    static func fallbackName(of bundleIdentifier: String) -> String {
        let identifier = ApplicationKey.of(bundleIdentifier)
        if let known = shippedOff.first(where: { $0.bundleIdentifier == identifier }) {
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
    /// One of the shipped private applications, off until the user asks for it.
    case offAsPrivate

    /// Whether suggestions run here.
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

    /// Everything the user has decided, each of them defaulted to having decided nothing.
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
            $0[ApplicationKey.of($1.key)] = $1.value
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

    /// Whether the feature is globally available, before an application's choice is applied.
    public func isEnabled(at moment: Date) -> Bool {
        isEnabled && !isPaused(at: moment)
    }

    /// Why suggestions do or do not run in one application, the master switch aside.
    public func state(of bundleIdentifier: String) -> SuggestionApplicationState {
        let identifier = ApplicationKey.of(bundleIdentifier)
        if turnedOff.contains(identifier) { return .turnedOff }
        if turnedOn.contains(identifier) { return .on }
        if SuggestionApplications.isPrivateByDefault(identifier) { return .offAsPrivate }
        return SuggestionApplications.isOffByDefault(identifier) ? .offByDefault : .on
    }

    /// Whether anything may be drawn in one application right now, which is the whole rule.
    public func isEnabled(in bundleIdentifier: String, at moment: Date) -> Bool {
        isEnabled(at: moment) && state(of: bundleIdentifier).isOn
    }

    /// The accept keys in force: the shipped answer with the user's choices on top.
    public var acceptKeys: AcceptKeys {
        AcceptKeys(overrides: chosenAcceptKeys)
    }

    /// Every application the screen has something to say about, the shipped editors always among them so a switch that ships off can still be found.
    public func knownApplications(learnedIn learned: Set<String> = []) -> [SuggestionApplication] {
        var identifiers = Set(SuggestionApplications.shippedOff.map(\.bundleIdentifier))
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
        let identifier = ApplicationKey.of(bundleIdentifier)
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
        chosenAcceptKeys[ApplicationKey.of(bundleIdentifier)] = key
    }

    /// Removes the per-application off override and keeps the chosen accept key.
    public mutating func removePreferences(for bundleIdentifier: String) {
        let identifier = ApplicationKey.of(bundleIdentifier)
        turnedOff.remove(identifier)
        turnedOn.remove(identifier)
        if SuggestionApplications.isOffByDefault(identifier) {
            turnedOn.insert(identifier)
        }
    }

    /// Starts a pause everywhere, or lifts one that is still running.
    public mutating func setPaused(_ isPaused: Bool, at moment: Date) {
        pausedUntil = isPaused ? moment.addingTimeInterval(Self.pause) : nil
    }
}

extension SuggestionPreferences {
    /// Keeps readable choices and app overrides when a saved suggestion preference cannot be decoded.
    public init(from decoder: any Decoder) throws {
        guard let container = try? decoder.container(keyedBy: CodingKeys.self) else {
            self = .default
            return
        }
        let turnedOff = container.readableElements(
            of: String.self, forKey: .turnedOff, fallback: Array(Self.default.turnedOff))
        let turnedOn = container.readableElements(
            of: String.self, forKey: .turnedOn, fallback: Array(Self.default.turnedOn))
        self.init(
            isEnabled: (try? container.decode(Bool.self, forKey: .isEnabled)) ?? Self.default.isEnabled,
            turnedOff: Set(turnedOff),
            turnedOn: Set(turnedOn),
            chosenAcceptKeys: (try? container.decode(
                [String: ReadableSetting<AcceptKey>].self, forKey: .chosenAcceptKeys))?
                .compactMapValues(\.value) ?? Self.default.chosenAcceptKeys,
            isQuiet: (try? container.decode(Bool.self, forKey: .isQuiet)) ?? Self.default.isQuiet,
            pausedUntil: try? container.decode(Date.self, forKey: .pausedUntil))
    }
}
