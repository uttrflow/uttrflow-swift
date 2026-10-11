import UttrflowCore
import UttrflowSettings

extension SettingsPresenter {
    /// Said before anything else: a key that is not claimed does nothing, and the refusal says why.
    static func unarmed(_ cause: HotkeyError) -> String {
        "Unavailable, so this shortcut does nothing. \(cause.userMessage)"
    }

    /// Said once a modifier held alone has been put back, so the change is not a mystery.
    static let returnedToDefault = """
        This was a key held on its own, which also fired on every shortcut using that key, \
        so it is back to the default. Choose another any time.
        """

    /// What the Dictate row says under its name: the user's own keys, and how they are held.
    static func dictateExplanation(_ activation: HotkeyActivation, keys: String) -> String {
        switch activation {
        case .holdToTalk: "Hold \(keys) to talk, anywhere"
        case .pressToToggle: "Press \(keys) once to start talking, and again to stop"
        }
    }

    /// The tile beside each shortcut's row.
    static func icon(for action: ShortcutAction) -> SettingsIcon {
        switch action {
        case .dictate: .symbol("mic", .dictation)
        case .clipboard: .symbol("list.clipboard", .suggestion)
        case .pasteLastTranscript: .symbol("text.insert", .info)
        case .copyLastTranscript: .symbol("doc.on.doc", .mint)
        case .editCommand: .symbol("wand.and.stars", .dictation)
        }
    }

    /// Said under a claimed shortcut, since other apps stop receiving its keys while it is set.
    static let claimsTheKeys = "While set, it takes these keys from other apps."

    /// One shortcut's row, drawn the same way whichever shortcut it is.
    static func shortcutRow(
        _ descriptor: ShortcutDescriptor, _ settings: Settings,
        _ capabilities: SettingsCapabilities
    ) -> SettingsRow {
        let binding = settings.shortcuts.first(for: descriptor.action)
        let control = SettingsControl.shortcut(
            action: descriptor.action, keys: binding.map(SettingsShortcut.keycaps(for:)) ?? [])
        let explanation: String? =
            if let cause = capabilities.unarmedShortcuts[descriptor.action] {
                unarmed(cause)
            } else if settings.shortcutsReturnedToDefault.contains(descriptor.action) {
                returnedToDefault
            } else if binding?.isFunctionHold == true {
                // Only Fn, which macOS has its own plans for. See `Docs/ux-settings-model.md`.
                """
                If pressing fn also opens Emoji or Apple's dictation, \
                set System Settings → Keyboard → "Press 🌐 key to" to \
                Do Nothing.
                """
            } else if descriptor.action == .dictate, let binding {
                dictateExplanation(settings.hotkeyActivation, keys: SettingsShortcut.compact(binding))
            } else if descriptor.delivery == .claimed, binding != nil, let sentence = descriptor.explanation {
                sentence + " " + claimsTheKeys
            } else {
                descriptor.explanation
            }
        return SettingsRow(
            id: "shortcut.\(descriptor.action.rawValue)",
            label: descriptor.label,
            explanation: explanation,
            control: control,
            icon: icon(for: descriptor.action))
    }

    /// Double-tapping the Dictate keys keeps the microphone open, which only holding to talk offers.
    static func handsFreeRow(_ settings: Settings) -> SettingsRow? {
        guard settings.hotkeyActivation == .holdToTalk,
            let binding = settings.shortcuts.first(for: .dictate)
        else { return nil }
        return SettingsRow(
            id: SettingsToggleField.handsFreeEnabled.rawValue,
            label: "Hands-free",
            control: .toggle(field: .handsFreeEnabled, isOn: settings.handsFreeEnabled),
            badge: "NEW",
            keyedExplanation: SettingsKeyedSentence(
                before: "Double-tap", keys: SettingsShortcut.keycaps(for: binding),
                after: "to keep listening · tap once to stop"),
            style: .inset)
    }

    /// One way of holding the shortcut, as a segmented option.
    static func activationOption(_ activation: HotkeyActivation) -> SettingsOption {
        let title: String =
            switch activation {
            case .holdToTalk: "Hold to talk"
            case .pressToToggle: "Press to toggle"
            }
        return SettingsOption(
            id: activation.rawValue, title: title, change: .activation(activation))
    }
}
