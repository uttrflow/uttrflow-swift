import Foundation

extension MacDeviceIdentity {
    /// This Mac, as the system describes it.
    ///
    /// `Host.current().localizedName` is what the person named their computer in System
    /// Settings — "Naveen's MacBook Pro" — which is exactly the string that makes a device
    /// list recognisable, and the reason the field is free text on the server. It is
    /// occasionally `nil` before the network stack is up early in launch, so the hostname
    /// stands in; a device called `Naveens-MacBook-Pro.local` is still recognisable, and a
    /// sign-in that failed because a name was momentarily unavailable would not be.
    public static func system() -> MacDeviceIdentity {
        MacDeviceIdentity(
            storage: SystemDefaultsStorage(),
            name: {
                Host.current().localizedName ?? ProcessInfo.processInfo.hostName
            },
            appVersion: Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String)
    }
}
