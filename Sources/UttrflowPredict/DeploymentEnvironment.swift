/// Which deployment a field is pointed at, since one editor tab may be on production and the next on QA.
public enum DeploymentEnvironment: String, Sendable, Hashable, Codable, CaseIterable {
    case production
    case staging
    case quality
    case development
    case local

    /// The environment a single word names, absent when the word names none.
    public init?(word: String) {
        let normalised = word.lowercased().filter { $0 != "-" && $0 != "_" && $0 != " " }
        switch normalised {
        case "prod", "production", "prd", "live": self = .production
        case "staging", "stage", "stg", "preprod": self = .staging
        case "qa", "uat", "qc": self = .quality
        case "dev", "development", "sandbox": self = .development
        case "local", "localhost": self = .local
        default: return nil
        }
    }
}
