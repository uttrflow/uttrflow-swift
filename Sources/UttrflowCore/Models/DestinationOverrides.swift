/// One app the user has told Uttrflow to treat as somewhere else than the table says.
public struct DestinationOverride: Sendable, Equatable, Codable, Identifiable {
    /// The app this is about; the whole identifier, not a prefix, because it names one app.
    public let bundleIdentifier: String
    /// What the screen called the app, so the list can show a name rather than an identifier.
    public let applicationName: String?
    public let destination: Destination

    public var id: String { bundleIdentifier.lowercased() }

    public init(bundleIdentifier: String, applicationName: String? = nil, destination: Destination) {
        self.bundleIdentifier = bundleIdentifier
        self.applicationName = applicationName
        self.destination = destination
    }

    /// What to call this app on screen.
    public var title: String {
        guard let applicationName, !applicationName.isEmpty else { return bundleIdentifier }
        return applicationName
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

    /// The same overrides with this app treated as `destination`, replacing any earlier answer.
    public func setting(
        _ destination: Destination, for bundleIdentifier: String, named applicationName: String?
    ) -> DestinationOverrides {
        DestinationOverrides(
            [
                DestinationOverride(
                    bundleIdentifier: bundleIdentifier, applicationName: applicationName,
                    destination: destination)
            ] + overrides)
    }

    /// The same overrides with this app back on the table's answer.
    public func removing(_ bundleIdentifier: String) -> DestinationOverrides {
        let unwanted = bundleIdentifier.lowercased()
        return DestinationOverrides(overrides.filter { $0.id != unwanted })
    }

    /// Normalises what it reads, so a hand-edited file cannot leave two answers for one app.
    public init(from decoder: any Decoder) throws {
        guard let container = try? decoder.container(keyedBy: CodingKeys.self) else {
            self.init()
            return
        }
        self.init(
            (try? container.decodeIfPresent([DestinationOverride].self, forKey: .overrides)) ?? [])
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
