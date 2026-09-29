import Foundation

/// Identifies application variants without changing the folders owned by each build.
public enum UttrflowBuildIdentity {
    /// Whether an identifier belongs to the shipped app or one of its named variants.
    public static func isUttrflow(_ identifier: String?) -> Bool {
        identifier?.hasPrefix(LocalStore.productionIdentifier) == true
    }

    /// Whether an identifier maps to a distinct Application Support folder.
    public static func isDevelopmentBuild(_ identifier: String?) -> Bool {
        !usesProductionFolder(identifier)
    }

    /// The first running Uttrflow identifier that is different from this build.
    public static func otherRunningIdentifier(current: String?, running: [String]) -> String? {
        running.first { $0 != current && isUttrflow($0) }
    }

    /// Whether an identifier uses the installed app's data folder.
    public static func usesProductionFolder(_ identifier: String?) -> Bool {
        LocalStore.folder(for: identifier) == LocalStore.productionFolder
    }
}
