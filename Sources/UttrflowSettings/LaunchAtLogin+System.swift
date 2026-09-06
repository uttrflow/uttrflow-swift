import ServiceManagement

/// Wires the setting to the real login-item database; excluded from coverage, so kept short enough to read.
extension LaunchAtLogin {
    /// The setting as the app uses it: `SMAppService.mainApp`, the app's own login item, no helper bundle.
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
