import UttrflowCore
import UttrflowSettings

extension SettingsPresenter {
    // MARK: - General

    /// General: the shortcuts, the floating button, sound and login, updating, and the two features.
    static func general(
        _ settings: Settings, _ capabilities: SettingsCapabilities
    ) -> SettingsPane {
        var shortcuts = ShortcutRegistry.all.map { shortcutRow($0, settings, capabilities) }
        if let handsFree = handsFreeRow(settings) {
            shortcuts.insert(handsFree, at: 1)
            shortcuts.insert(
                SettingsRow(
                    id: "handsFreeDoubleTapMilliseconds",
                    label: "Double-tap speed",
                    explanation: "Choose how far apart your taps can be.",
                    control: .menu(
                        options: Settings.handsFreeDoubleTapChoices.map { milliseconds in
                            SettingsOption(
                                id: String(milliseconds), title: "\(milliseconds) ms",
                                change: .handsFreeDoubleTap(milliseconds: milliseconds))
                        },
                        selectedID: String(settings.handsFreeDoubleTapMilliseconds)),
                    style: .inset),
                at: 2)
            shortcuts.insert(
                SettingsRow(
                    id: "handsFreeHoldMilliseconds",
                    label: "Hold length",
                    explanation: "Choose how long a press can last and still count as a tap.",
                    control: .menu(
                        options: Settings.handsFreeHoldChoices.map { milliseconds in
                            SettingsOption(
                                id: String(milliseconds), title: "\(milliseconds) ms",
                                change: .handsFreeHold(milliseconds: milliseconds))
                        },
                        selectedID: String(settings.handsFreeHoldMilliseconds)),
                    style: .inset),
                at: 3)
        }
        shortcuts.append(
            SettingsRow(
                id: "restoreDefaultShortcuts",
                label: "Restore default shortcuts",
                explanation: "Puts every shortcut back and leaves everything else as it is.",
                control: .action(title: "Restore Defaults", change: .restoreDefaultShortcuts),
                unavailability: settings.shortcuts == .default
                    ? "Every shortcut is already the default." : nil,
                icon: .symbol("arrow.counterclockwise", .neutral)))
        shortcuts.append(
            SettingsRow(
                id: "activation",
                label: "How holding works",
                control: .segmented(
                    options: HotkeyActivation.allCases.map(activationOption),
                    selectedID: settings.hotkeyActivation.rawValue),
                icon: .symbol("hand.raised", .info)))
        shortcuts.append(
            SettingsRow(
                id: "endOnSilenceSeconds",
                label: "End on silence",
                explanation: "Finishes the dictation once you stop talking, unless you are holding the keys.",
                control: .menu(
                    options: ([0] + SilenceStop.choices).map { seconds in
                        SettingsOption(
                            id: String(seconds), title: seconds == 0 ? "Off" : "After \(seconds) s",
                            change: .endOnSilence(seconds: seconds))
                    },
                    selectedID: String(settings.endOnSilenceSeconds)),
                icon: .symbol("timer", .info)))

        return SettingsPane(
            tab: .general,
            title: title(of: .general),
            banner: nil,
            groups: [
                SettingsGroup(id: "shortcut", title: "Shortcuts", rows: shortcuts),
                SettingsGroup(
                    id: "floatingButton",
                    title: "Floating button",
                    rows: [
                        toggleRow(
                            .showsFloatingButton,
                            label: "Show the floating button",
                            explanation: "Press and hold it to dictate",
                            settings, capabilities
                        ).with(icon: .symbol("waveform", .dictation)),
                        SettingsRow(
                            id: "anchor",
                            label: "Position",
                            control: .menu(
                                options: DockAnchor.allCases.map(anchorOption),
                                selectedID: settings.floatingButtonAnchor.rawValue),
                            // The grip switch's dependency: nothing to position while there is no button.
                            unavailability: settings.showsFloatingButton
                                ? nil : "Turn the floating button on before choosing where it sits.",
                            icon: .symbol("macbook", .neutral)),
                        toggleRow(
                            .shrinksToGripWhenIdle,
                            label: "Shrink to a grip until I point at it",
                            settings, capabilities
                        ).with(icon: .symbol("waveform.path.ecg", .info)),
                        toggleRow(
                            .minimisesWhileDictating,
                            label: "Get Uttrflow out of the way while I dictate",
                            explanation:
                                "Minimises the window so you can see what you are typing into.",
                            settings, capabilities
                        ).with(icon: .symbol("sparkles", .suggestion)),
                    ]),
                SettingsGroup(
                    id: "system",
                    title: "Sound & startup",
                    rows: [
                        microphoneRow(settings, capabilities),
                        toggleRow(
                            .playsSoundWhenRecordingStarts,
                            label: "Play a sound when recording starts",
                            settings, capabilities
                        ).with(icon: .symbol("speaker.wave.2", .amber)),
                        toggleRow(
                            .opensAtLogin, label: "Open at login", settings, capabilities
                        ).with(icon: .symbol("power", .dictation)),
                    ]),
                updates(settings, capabilities),
                SettingsGroup(
                    id: "features",
                    title: "Features",
                    rows: [
                        toggleRow(
                            .dictationEnabled,
                            label: "Dictation",
                            explanation: "Off, the shortcut and the floating button do nothing.",
                            settings, capabilities
                        ).with(icon: .symbol("mic", .dictation)),
                        toggleRow(
                            .clipboardEnabled,
                            label: "Clipboard",
                            explanation:
                                "Off, copies are not kept and the clipboard shortcut is released. Exclusions use the declared writer when available, or the frontmost app.",
                            settings, capabilities
                        ).with(icon: .symbol("list.clipboard", .suggestion))
                            .with(badge: BetaFeature.label),
                        SettingsRow(
                            id: "clipboard-exclusions", label: "Excluded apps",
                            explanation: "Copies attributed to these apps are skipped.",
                            control: .action(title: "Manage…", change: .manageClipboardExclusions),
                            icon: .symbol("hand.raised", .amber)),
                        toggleRow(
                            .confirmsHiddenClipPaste,
                            label: "Confirm hidden clips",
                            explanation:
                                "Ask before a hidden clip is pasted into a field that may show it. Hidden fields still paste at once.",
                            settings, capabilities
                        ).with(icon: .symbol("eye.slash", .amber)),
                        SettingsRow(
                            id: "clipboard-pause", label: "Clipboard capture",
                            explanation: capabilities.clipboardCapturePaused
                                ? "Paused temporarily. Copies are skipped until resumed or the hour ends."
                                : "Pause copying for one hour without changing this switch.",
                            control: .action(
                                title: capabilities.clipboardCapturePaused ? "Resume" : "Pause for 1 hour",
                                change: .pauseClipboardCapture(isOn: !capabilities.clipboardCapturePaused)),
                            icon: .symbol(
                                capabilities.clipboardCapturePaused ? "play" : "pause", .neutral)),
                        SettingsRow(
                            id: "clipboard-terminal-paste",
                            label: "Ask before pasting several lines into a terminal",
                            explanation:
                                "A new line runs the command before it. Off, a multi-line clip pastes into a terminal without a question.",
                            control: .action(
                                title: capabilities.confirmsMultilinePaste ? "Turn off" : "Turn on",
                                change: .confirmMultilinePaste(isOn: !capabilities.confirmsMultilinePaste)),
                            icon: .symbol("terminal", .amber)),
                    ]),
            ],
            callout: nil)
    }

    /// One place the floating button can park, as a pop-up option.
    private static func anchorOption(_ anchor: DockAnchor) -> SettingsOption {
        SettingsOption(id: anchor.rawValue, title: title(of: anchor), change: .anchor(anchor))
    }

    /// What a parking place is called.
    static func title(of anchor: DockAnchor) -> String {
        switch anchor {
        case .bottomLeft: "Bottom left"
        case .bottomCentre: "Bottom centre"
        case .bottomRight: "Bottom right"
        case .rightEdge: "Right edge"
        }
    }

}
