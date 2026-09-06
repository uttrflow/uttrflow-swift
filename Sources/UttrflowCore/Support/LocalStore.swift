public import struct Foundation.URL
public import class Foundation.Bundle

/// Where this build keeps its own files, named after the bundle so a development build never writes into the shipped app's folder.
public enum LocalStore {
    /// The folder the shipped app writes under, and what every other build is named against.
    public static let productionFolder = "Uttrflow"

    /// The identifier the shipped app is signed with.
    public static let productionIdentifier = "com.uttrflow.Uttrflow"

    /// The folder this process writes under, which follows the bundle it is running from.
    public static var folder: String { folder(for: Bundle.main.bundleIdentifier) }

    /// The folder one identifier writes under: the shipped name, plus whatever the identifier adds after it, so anything that is not the shipped identifier extended keeps the files it already has.
    public static func folder(for identifier: String?) -> String {
        guard let identifier, identifier.hasPrefix(productionIdentifier + ".") else {
            return productionFolder
        }
        let variant = identifier.dropFirst(productionIdentifier.count + 1)
        guard !variant.isEmpty else { return productionFolder }
        return "\(productionFolder).\(variant)"
    }

    /// One of this build's files inside `directory`, which is Application Support unless a test says otherwise.
    public static func file(_ name: String, in directory: URL) -> URL {
        directory.appending(path: "\(folder)/\(name)", directoryHint: .notDirectory)
    }

    /// One of this build's directories inside `directory`.
    public static func directory(_ name: String, in directory: URL) -> URL {
        directory.appending(path: "\(folder)/\(name)", directoryHint: .isDirectory)
    }
}
