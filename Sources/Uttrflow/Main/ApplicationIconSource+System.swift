import AppKit

extension ApplicationIconSource {
    /// The lookups, against the real Mac.
    ///
    /// The identifier first, which `LaunchServices` resolves to the app's real bundle
    /// wherever it is on the disk. The two name lookups behind it are for dictations
    /// recorded before identifiers were kept: exact for every app whose bundle is named
    /// as it presents itself, which is nearly all of them, and falling back to the
    /// lettered tile rather than to a wrong icon for the rest.
    static let system = ApplicationIconSource(
        identified: { identifier in
            NSWorkspace.shared.urlForApplication(withBundleIdentifier: identifier)
                .map { NSWorkspace.shared.icon(forFile: $0.path) }
        },
        running: { name in
            NSWorkspace.shared.runningApplications
                .first { $0.localizedName == name }?
                .icon
        },
        installed: { name in
            let folders = [
                "/Applications", "/Applications/Utilities",
                "/System/Applications", "/System/Applications/Utilities",
                NSHomeDirectory() + "/Applications",
            ]
            let manager = FileManager.default
            for folder in folders {
                let path = folder + "/" + name + ".app"
                if manager.fileExists(atPath: path) {
                    return NSWorkspace.shared.icon(forFile: path)
                }
            }
            return nil
        })
}
