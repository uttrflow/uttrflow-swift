/// One app the user has told Uttrflow to treat as somewhere else than the table says.
public struct DestinationOverride: Sendable, Equatable, Codable, Identifiable {
    /// The app this is about; the whole identifier, not a prefix, because it names one app.
    public let bundleIdentifier: String
    /// What the screen called the app, so the list can show a name rather than an identifier.
    public let applicationName: String?
    public let destination: Destination
    /// Which adapter formats this app's words; an entry stored before modes existed reads as `auto`.
    public let mode: AdapterMode

    public var id: String { ApplicationKey.of(bundleIdentifier) }

    public init(
        bundleIdentifier: String, applicationName: String? = nil, destination: Destination,
        mode: AdapterMode = .auto
    ) {
        self.bundleIdentifier = bundleIdentifier
        self.applicationName = applicationName
        self.destination = destination
        self.mode = mode
    }

    /// What to call this app on screen.
    public var title: String {
        guard let applicationName, !applicationName.isEmpty else { return bundleIdentifier }
        return applicationName
    }

    private enum CodingKeys: String, CodingKey {
        case bundleIdentifier, applicationName, destination, mode, adapter
    }

    private static let proseWord = "prose"
    private static let forcedWord = "forced"

    /// Reads entries written before modes existed, and a mode this build has no word for, as `auto`.
    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        bundleIdentifier = try container.decode(String.self, forKey: .bundleIdentifier)
        applicationName = try container.decodeIfPresent(String.self, forKey: .applicationName)
        destination = try container.decode(Destination.self, forKey: .destination)
        let word = try? container.decodeIfPresent(String.self, forKey: .mode)
        let adapter = try? container.decodeIfPresent(AdapterID.self, forKey: .adapter)
        switch (word, adapter) {
        case (Self.proseWord, _): mode = .prose
        case (Self.forcedWord, .some(let adapter)): mode = .forced(adapter)
        default: mode = .auto
        }
    }

    /// Writes `auto` as no mode at all, so an entry nobody changed is stored in the form that predates modes.
    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(bundleIdentifier, forKey: .bundleIdentifier)
        try container.encodeIfPresent(applicationName, forKey: .applicationName)
        try container.encode(destination, forKey: .destination)
        switch mode {
        case .auto: break
        case .prose: try container.encode(Self.proseWord, forKey: .mode)
        case .forced(let adapter):
            try container.encode(Self.forcedWord, forKey: .mode)
            try container.encode(adapter, forKey: .adapter)
        }
    }
}

/// The overrides the user has made, consulted before the table and never editing it. See `Docs/cleanup.md`.
public struct DestinationOverrides: Sendable, Equatable, Codable {
    /// One entry per app, in the order they read on screen.
    public private(set) var overrides: [DestinationOverride]

    public init(_ overrides: [DestinationOverride] = []) {
        self.overrides = Self.ordered(Self.deduplicated(overrides))
    }

    /// No app is overridden, which is what every user starts with.
    public static let none = DestinationOverrides()

    public var isEmpty: Bool { overrides.isEmpty }

    /// What the user says this app is, or nothing when they have said nothing about it.
    public func destination(for app: AppContext) -> Destination? {
        guard let bundle = app.bundleIdentifier else { return nil }
        return destination(forBundleIdentifier: bundle)
    }

    /// The same by identifier, matched whole and without regard to case.
    public func destination(forBundleIdentifier bundle: String) -> Destination? {
        let wanted = bundle.lowercased()
        return overrides.first { $0.id == wanted }?.destination
    }

    /// How this app's words are to be formatted; `auto` when no override names the app.
    public func mode(forBundleIdentifier bundle: String) -> AdapterMode {
        let wanted = bundle.lowercased()
        return overrides.first { $0.id == wanted }?.mode ?? .auto
    }

    /// The same overrides with this app treated as `destination`, replacing any earlier answer but keeping its mode.
    public func setting(
        _ destination: Destination, for bundleIdentifier: String, named applicationName: String?
    ) -> DestinationOverrides {
        DestinationOverrides(
            [
                DestinationOverride(
                    bundleIdentifier: bundleIdentifier, applicationName: applicationName,
                    destination: destination, mode: mode(forBundleIdentifier: bundleIdentifier))
            ] + overrides)
    }

    /// The same overrides with this app back on the table's answer.
    public func removing(_ bundleIdentifier: String) -> DestinationOverrides {
        let unwanted = ApplicationKey.of(bundleIdentifier)
        return DestinationOverrides(overrides.filter { $0.id != unwanted })
    }

    /// Normalises what it reads, so a hand-edited file cannot leave two answers for one app.
    public init(from decoder: any Decoder) throws {
        guard let container = try? decoder.container(keyedBy: CodingKeys.self) else {
            self.init()
            return
        }
        let read = (try? container.decodeIfPresent([Readable].self, forKey: .overrides)) ?? []
        self.init(read.compactMap(\.override))
    }

    /// One entry read on its own, so an app named as somewhere this build has no word for costs only itself.
    private struct Readable: Decodable {
        let override: DestinationOverride?

        init(from decoder: any Decoder) throws {
            override = try? DestinationOverride(from: decoder)
        }
    }

    /// The first entry for each app wins, which is what makes ``setting(_:for:named:)`` a replacement.
    private static func deduplicated(_ overrides: [DestinationOverride]) -> [DestinationOverride] {
        var seen: Set<String> = []
        return overrides.filter { seen.insert($0.id).inserted }
    }

    /// Sorted by what the list shows, so the same set of overrides always reads the same way.
    private static func ordered(_ overrides: [DestinationOverride]) -> [DestinationOverride] {
        overrides.sorted { ($0.title.lowercased(), $0.id) < ($1.title.lowercased(), $1.id) }
    }
}
