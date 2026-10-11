import Foundation

/// Identifies application variants without changing the folders owned by each build.
public enum UttrflowBuildIdentity {
    /// The executable every build ships as, whatever identifier it was signed with.
    static let executableName = "Uttrflow"

    /// Whether a process is a build of the app: by identifier prefix, or by executable for a build outside the prefix.
    public static func isUttrflow(_ identifier: String?, executableName: String? = nil) -> Bool {
        identifier?.hasPrefix(LocalStore.productionIdentifier) == true
            || executableName == Self.executableName
    }

    /// Whether an identifier maps to a distinct Application Support folder.
    public static func isDevelopmentBuild(_ identifier: String?) -> Bool {
        !usesProductionFolder(identifier)
    }

    /// Whether an identifier uses the installed app's data folder.
    public static func usesProductionFolder(_ identifier: String?) -> Bool {
        LocalStore.folder(for: identifier) == LocalStore.productionFolder
    }
}
