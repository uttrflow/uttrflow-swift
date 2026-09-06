// This Mac's device identity as the system describes it.
import Foundation

extension MacDeviceIdentity {
    /// This Mac, named as System Settings names it, or by hostname while that is `nil` early in launch.
    public static func system() -> MacDeviceIdentity {
        MacDeviceIdentity(
            storage: SystemDefaultsStorage(),
            name: {
                Host.current().localizedName ?? ProcessInfo.processInfo.hostName
            },
            appVersion: Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String)
    }
}
