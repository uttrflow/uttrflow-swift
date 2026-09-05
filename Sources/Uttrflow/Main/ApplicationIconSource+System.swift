// The real icon lookups against LaunchServices, running apps and the app folders.

import AppKit

extension ApplicationIconSource {
    /// The lookups against the real Mac: identifier via LaunchServices, then running apps, then app folders.
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
