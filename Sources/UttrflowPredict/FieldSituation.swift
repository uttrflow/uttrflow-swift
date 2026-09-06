/// What is true of a field right now, which decides which remembered entries win rather than which corpus they belong to.
public struct FieldSituation: Sendable, Hashable, Codable {
    /// The checked-out branch, when something says which one it is.
    public let branch: String?
    /// The database, schema or host a tab is connected to.
    public let connection: String?
    /// The deployment that connection belongs to.
    public let environment: DeploymentEnvironment?
    /// The file open in front of the user.
    public let file: String?

    /// Facets are lowercased and trimmed here, so a tag written once matches a situation read later.
    public init(
        branch: String? = nil, connection: String? = nil, environment: DeploymentEnvironment? = nil,
        file: String? = nil
    ) {
        self.branch = FieldSituation.normalised(branch)
        self.connection = FieldSituation.normalised(connection)
        self.environment = environment
        self.file = FieldSituation.normalised(file)
    }

    /// The situation that knows nothing, which is what an unrecognisable window amounts to.
    public static let unknown = FieldSituation()

    /// Whether nothing at all is known, in which case no candidate may be preferred over another.
    public var isEmpty: Bool {
        branch == nil && connection == nil && environment == nil && file == nil
    }

    /// What two situations with nothing in common to compare agree to, which is neither help nor harm.
    public static let unknownAgreement = 0.5

    /// How much the branch counts, below a connection because a stale branch tag is common and cheap.
    public static let branchWeight = 0.8

    /// How much the connection counts, which is the facet that keeps production names out of a QA tab.
    public static let connectionWeight = 1.0

    /// How much the deployment counts, weighed level with the connection it belongs to.
    public static let environmentWeight = 1.0

    /// How much the open file counts, least because it changes many times an hour.
    public static let fileWeight = 0.4

    /// How far this situation agrees with another, 1 for full agreement, 0 for full conflict, 0.5 for ignorance.
    public func similarity(to other: FieldSituation) -> Double {
        let facets = [
            (FieldSituation.agreement(branch, other.branch), FieldSituation.branchWeight),
            (FieldSituation.agreement(connection, other.connection), FieldSituation.connectionWeight),
            (FieldSituation.agreement(environment, other.environment), FieldSituation.environmentWeight),
            (FieldSituation.agreement(file, other.file), FieldSituation.fileWeight),
        ]
        let comparable = facets.compactMap { agreement, weight in agreement.map { ($0, weight) } }
        let total = comparable.reduce(0) { $0 + $1.1 }
        guard total > 0 else { return FieldSituation.unknownAgreement }
        return comparable.reduce(0) { $0 + $1.0 * $1.1 } / total
    }

    /// This situation with another's facets filling its gaps, the receiver winning wherever both know.
    public func completed(by other: FieldSituation) -> FieldSituation {
        FieldSituation(
            branch: branch ?? other.branch,
            connection: connection ?? other.connection,
            environment: environment ?? other.environment,
            file: file ?? other.file)
    }

    /// What one facet is worth, absent whenever either side is silent about it so it counts for nothing.
    static func agreement<Facet: Equatable>(_ mine: Facet?, _ theirs: Facet?) -> Double? {
        guard let mine, let theirs else { return nil }
        return mine == theirs ? 1 : 0
    }

    /// A facet as it is stored, with blank strings treated as nothing said.
    static func normalised(_ facet: String?) -> String? {
        guard let facet else { return nil }
        let cleaned = Whitespace.trimmed(facet).lowercased()
        return cleaned.isEmpty ? nil : cleaned
    }
}
