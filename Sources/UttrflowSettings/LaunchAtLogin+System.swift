import ServiceManagement

/// Wires the setting to the real macOS login-item database.
///
/// Everything here is untestable by construction: these calls write to the database
/// that decides what the user's Mac launches at login, so no test may run them.
/// Excluded from the coverage gate for the same reason as the permission gates, and
/// kept short enough that reading it is a sufficient review. All the behaviour worth
/// testing lives in `LaunchAtLogin` itself.
extension LaunchAtLogin {
    /// The setting as the app uses it.
    ///
    /// `SMAppService.mainApp` is the app's own login item, so there is no helper
    /// bundle to install and nothing to keep in step with it. It replaces
    /// `SMLoginItemSetEnabled`, deprecated since macOS 13.
    public init() {
        self.init(
            readStatus: {
                LaunchAtLogin.launchAtLoginStatus(for: SMAppService.mainApp.status)
            },
            register: { try SMAppService.mainApp.register() },
            unregister: { try SMAppService.mainApp.unregister() }
        )
    }
}
