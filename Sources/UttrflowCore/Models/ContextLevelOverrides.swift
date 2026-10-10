/// One application the user lets a dictation read more or less of than every other.
public struct ContextLevelOverride: Sendable, Equatable, Codable, Identifiable {
    /// The application this is about, matched whole and without regard to case.
    public let bundleIdentifier: String
    /// What the application is called, so the list can show a name rather than an identifier.
    public let applicationName: String?
    public let level: ContextLevel

    public var id: String { ApplicationKey.of(bundleIdentifier) }

    public init(bundleIdentifier: String, applicationName: String? = nil, level: ContextLevel) {
        self.bundleIdentifier = bundleIdentifier
        self.applicationName = applicationName
        self.level = level
    }

    /// What to call this application on screen.
    public var title: String {
        guard let applicationName, !applicationName.isEmpty else { return bundleIdentifier }
        return applicationName
    }
}

/// The per-application context levels, consulted before ``Settings/contextLevel``. See `Docs/context-accessibility.md`.
public struct ContextLevelOverrides: Sendable, Equatable, Codable {
    /// One entry per application, in the order they read on screen.
    public private(set) var overrides: [ContextLevelOverride]

    public init(_ overrides: [ContextLevelOverride] = []) {
        var seen: Set<String> = []
        // The first entry for an application wins, which is what makes ``setting(_:for:named:)`` a replacement.
        self.overrides = overrides.filter { seen.insert($0.id).inserted }
            .sorted { ($0.title.lowercased(), $0.id) < ($1.title.lowercased(), $1.id) }
    }

    /// No application has its own level, which is what every user starts with.
    public static let none = ContextLevelOverrides()

    /// The level for this application: its own when it has one, otherwise `fallback`.
    public func level(forBundleIdentifier bundle: String?, default fallback: ContextLevel) -> ContextLevel {
        guard let bundle else { return fallback }
        let wanted = ApplicationKey.of(bundle)
        return overrides.first { $0.id == wanted }?.level ?? fallback
    }

    /// The same overrides with this application read at `level`, replacing any earlier answer.
    public func setting(
        _ level: ContextLevel, for bundleIdentifier: String, named applicationName: String?
    ) -> ContextLevelOverrides {
        ContextLevelOverrides(
            [ContextLevelOverride(bundleIdentifier: bundleIdentifier, applicationName: applicationName, level: level)]
                + overrides)
    }

    /// The same overrides with this application back on the level every application gets.
    public func removing(_ bundleIdentifier: String) -> ContextLevelOverrides {
        let unwanted = ApplicationKey.of(bundleIdentifier)
        return ContextLevelOverrides(overrides.filter { $0.id != unwanted })
    }

    private enum CodingKeys: String, CodingKey {
        case overrides
    }

    /// Reads entry by entry, so an unreadable one costs only itself. See `Docs/settings-decoding.md`.
    public init(from decoder: any Decoder) throws {
        guard let container = try? decoder.container(keyedBy: CodingKeys.self) else {
            self.init()
            return
        }
        self.init(container.readableElements(of: ContextLevelOverride.self, forKey: .overrides, fallback: []))
    }
}
