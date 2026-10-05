// Owns the Settings page's model, which the main window draws beside its sidebar.

import UttrflowCore
import UttrflowPredict
import UttrflowSettings
import UttrflowUX

/// Owns the Settings page's model, kept alive between visits so a tab and a recording survive them.
@MainActor
final class SettingsPageController {
    /// What the main window draws when it shows Settings.
    let model: SettingsViewModel
    /// What the suggestion model is doing, kept so a capability refresh cannot drop it.
    private var suggestionModel: SuggestionModelReadiness = .notAsked
    private var suggestionRuntime: SuggestionRuntimeStatus = .idle
    /// Which shortcuts the window server refused, kept for the same reason.
    private var unarmedShortcuts: [ShortcutAction: HotkeyError] = [:]
    /// Asks this Mac which clean-up engines are ready for a profile; injected so a test can order the answers.
    private let probe: @Sendable (UserProfile) async -> SettingsCapabilities
    /// Counts capability probes, so only the most recently started one may apply its answer.
    private var probeGeneration = 0
    /// The probe in flight, cancelled when a newer one starts.
    private(set) var capabilityRefresh: Task<Void, Never>?

    /// `personalisation` has no default: a fresh store here would be a second actor racing over each file.
    init(
        store: any SettingsStore,
        personalisation: any SettingsPersonalisationStore,
        capabilities: SettingsCapabilities = .thisMac(),
        onChange: @escaping (UttrflowSettings.Settings) -> Void = { _ in },
        onRequest: @escaping (SettingsChange) -> Void = { _ in },
        onReset: @escaping (SettingsReset) -> Void = { _ in },
        onShortcutRecording: @escaping (Bool) -> Void = { _ in },
        readGlobeKeyAction: @escaping () -> GlobeKeyAction = { GlobeKeySettings.action },
        readIsDictating: @escaping () -> Bool = { DictationInProgress.shared.isDictating },
        probe: @escaping @Sendable (UserProfile) async -> SettingsCapabilities = {
            await SettingsCapabilities.refreshed(for: $0)
        }
    ) {
        self.probe = probe
        model = SettingsViewModel(
            store: store, personalisation: personalisation, capabilities: capabilities,
            onChange: onChange, onRequest: onRequest, onReset: onReset,
            onShortcutRecording: onShortcutRecording, readGlobeKeyAction: readGlobeKeyAction,
            readIsDictating: readIsDictating)
    }

    /// The tab the page is on, which the sidebar lights its Settings row for.
    var tab: SettingsTab { model.session.tab }

    /// Applies settings changed elsewhere while preserving the page's current tab and UI state.
    func synchronize(settings: UttrflowSettings.Settings) {
        model.synchronize(settings: settings)
    }

    /// Points the page at `tab` and reads again what may have changed since it was last shown.
    func open(_ tab: SettingsTab = .general) {
        route(to: tab)
        model.refreshPersonalisation()
        refreshCapabilities()
    }

    /// Re-probes the engines for the current profile; an answer from a superseded probe is discarded.
    func refreshCapabilities() {
        capabilityRefresh?.cancel()
        probeGeneration += 1
        let generation = probeGeneration
        let profile = model.session.settings.profile
        let probe = probe
        capabilityRefresh = Task { [weak self] in
            var refreshed = await probe(profile)
            guard let self, !Task.isCancelled, generation == probeGeneration else { return }
            // Re-applied, because the probe asks this Mac and only the app knows about the fetch.
            refreshed.suggestionModel = suggestionModel
            refreshed.suggestionRuntime = suggestionRuntime
            refreshed.unarmedShortcuts = unarmedShortcuts
            refreshed.clipboardCapturePaused = model.session.capabilities.clipboardCapturePaused
            model.session.capabilities = refreshed
        }
    }

    /// Points the page at `tab`, through the one tab change that ends a recording.
    func route(to tab: SettingsTab) {
        model.select(tab)
    }

    /// Told by the app as the weights are fetched and read, so a page already showing redraws.
    func setSuggestionModel(_ readiness: SuggestionModelReadiness) {
        suggestionModel = readiness
        model.session.capabilities.suggestionModel = readiness
    }

    /// Tells the Suggestions screen whether its key tap can receive keystrokes.
    func setSuggestionRuntime(_ status: SuggestionRuntimeStatus) {
        suggestionRuntime = status
        model.session.capabilities.suggestionRuntime = status
    }

    /// Told by the app when a shortcut could not be claimed, so its row stops advertising a dead key.
    func setUnarmedShortcuts(_ unarmed: [ShortcutAction: HotkeyError]) {
        unarmedShortcuts = unarmed
        model.session.capabilities.unarmedShortcuts = unarmed
    }

    /// Redraws the clipboard pause action from the live one-hour timer.
    func setClipboardCapturePaused(_ paused: Bool) {
        model.session.capabilities.clipboardCapturePaused = paused
    }

    /// Applies a change the app worked out on the page's behalf, through the page's own session.
    func apply(_ change: SettingsChange) {
        model.apply(change)
    }

    /// The page went out of sight or its window lost the keyboard, so a recording there ends.
    func surfaceDidLoseFocus() {
        model.shortcutRecordingSurfaceDidLoseFocus()
    }
}
