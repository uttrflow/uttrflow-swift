import UttrflowSettings

extension SettingsPresenter {
    /// The menu id of following the system default input.
    static let systemDefaultMicrophone = "system-default"

    /// System default first, then every input present; a chosen device that is absent stays listed as missing.
    static func microphoneRow(_ settings: Settings, _ capabilities: SettingsCapabilities) -> SettingsRow {
        let present = capabilities.microphones.map { device in
            SettingsOption(id: device.uid, title: device.name, change: .microphone(uid: device.uid))
        }
        let chosen = settings.microphoneUID
        let absent =
            chosen.flatMap { uid in
                present.contains { $0.id == uid }
                    ? nil
                    : SettingsOption(
                        id: uid, title: "Chosen microphone (not connected)", change: .microphone(uid: uid))
            }
        let systemDefault = SettingsOption(
            id: systemDefaultMicrophone, title: "System default", change: .microphone(uid: nil))
        return SettingsRow(
            id: "microphone",
            label: "Microphone",
            explanation: "When the chosen one is not connected, dictation uses the system default.",
            control: .menu(
                options: [systemDefault] + present + [absent].compactMap(\.self),
                selectedID: chosen ?? systemDefaultMicrophone),
            icon: .symbol("mic", .dictation))
    }
}
