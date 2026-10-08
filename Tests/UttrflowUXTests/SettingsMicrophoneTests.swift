// Tests the microphone choice: what the menu offers and what choosing one stores.
import Testing
import UttrflowSettings

@testable import UttrflowUX

@Suite("Settings microphone choice")
struct SettingsMicrophoneTests {
    private let builtIn = SettingsMicrophone(uid: "fixture-built-in", name: "Built-in Microphone")
    private let headset = SettingsMicrophone(uid: "fixture-headset", name: "Example Headset")

    private func capabilities(_ microphones: [SettingsMicrophone]) -> SettingsCapabilities {
        var capabilities = SettingsCapabilities.everything
        capabilities.microphones = microphones
        return capabilities
    }

    private func options(_ row: SettingsRow) -> (ids: [String], selected: String)? {
        guard case .menu(let options, let selected) = row.control else { return nil }
        return (options.map(\.id), selected)
    }

    @Test("nothing chosen selects the system default, listed first, then every input")
    func defaultIsSelected() throws {
        let row = SettingsPresenter.microphoneRow(.default, capabilities([builtIn, headset]))
        let menu = try #require(options(row))
        #expect(menu.ids == [SettingsPresenter.systemDefaultMicrophone, builtIn.uid, headset.uid])
        #expect(menu.selected == SettingsPresenter.systemDefaultMicrophone)
    }

    @Test("a chosen device that is present is selected")
    func presentChoiceIsSelected() throws {
        var settings = Settings.default
        settings.microphoneUID = headset.uid
        let row = SettingsPresenter.microphoneRow(settings, capabilities([builtIn, headset]))
        let menu = try #require(options(row))
        #expect(menu.selected == headset.uid)
        #expect(menu.ids.count == 3)
    }

    @Test("a chosen device that is absent stays selected and is said to be not connected")
    func absentChoiceIsKept() throws {
        var settings = Settings.default
        settings.microphoneUID = headset.uid
        let row = SettingsPresenter.microphoneRow(settings, capabilities([builtIn]))
        guard case .menu(let offered, let selected) = row.control else {
            Issue.record("the microphone row is not a menu")
            return
        }
        #expect(selected == headset.uid)
        #expect(offered.last?.title == "Chosen microphone (not connected)")
    }

    @Test("choosing a device stores its UID, and the system default clears it")
    func choosingStoresTheUID() throws {
        let chosen = try SettingsEditor.apply(.microphone(uid: headset.uid), to: .default, given: .everything)
        #expect(chosen.microphoneUID == headset.uid)
        let cleared = try SettingsEditor.apply(.microphone(uid: nil), to: chosen, given: .everything)
        #expect(cleared.microphoneUID == nil)
    }
}
