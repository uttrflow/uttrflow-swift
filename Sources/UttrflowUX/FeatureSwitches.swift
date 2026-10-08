public import struct Foundation.Date
public import UttrflowSettings

// What the stored Dictation, Clipboard and AI Suggestions switches turn on and off.

extension MenuBarFeatures {
    /// The menu's three ticks, read from the settings that store them.
    public init(
        _ settings: Settings, applicationBundleIdentifier: String? = nil, at moment: Date = Date()
    ) {
        self.init(
            dictation: settings.dictationEnabled, clipboard: settings.clipboardEnabled,
            suggestions: applicationBundleIdentifier.map {
                settings.suggestions.isEnabled(in: $0, at: moment)
            } ?? settings.suggestions.isEnabled(at: moment))
    }
}

extension MenuBarFeature {
    /// The stored switch a menu tick writes, so the menu and Settings cannot disagree.
    public var setting: SettingsToggleField {
        switch self {
        case .dictation: .dictationEnabled
        case .clipboard: .clipboardEnabled
        case .suggestions: .suggestionsEnabled
        }
    }
}

extension ShortcutRegistry {
    /// The claimed shortcuts to register now; the clipboard's is released while the clipboard is off.
    public static func claimed(in settings: Settings) -> [ShortcutDescriptor] {
        claimed.filter { settings.clipboardEnabled || $0.action != .clipboard }
    }
}

extension Settings {
    /// Whether the floating button is on screen, which needs dictation on as well as the button.
    public var floatingButtonIsShown: Bool { self.dictationEnabled && self.showsFloatingButton }
}
