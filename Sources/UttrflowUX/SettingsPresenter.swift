public import struct Foundation.Date
public import struct Foundation.Locale
public import struct Foundation.ByteCountFormatStyle
import UttrflowCore
import UttrflowPredict
public import UttrflowSettings

/// The whole Settings page, as the view is given it.
public struct SettingsWindowPresentation: Sendable, Equatable {
    public let tabs: [SettingsTabItem]
    public let selected: SettingsTab
    /// The selected tab, or every row matching the search while one is typed.
    public let pane: SettingsPane
    /// What is typed in the search field.
    public let query: String
}

/// Turns the user's settings into what the Settings page draws, naming no engine or file.
public enum SettingsPresenter {
    /// What the empty search field says.
    public static let searchPlaceholder = "Search settings"

    /// Every tab, in the design's order, driven by ``SettingsTab/allCases`` so a new case adds a tab.
    public static func tabs() -> [SettingsTabItem] {
        SettingsTab.allCases.map { tab in
            SettingsTabItem(
                tab: tab, title: title(of: tab), symbolName: symbolName(of: tab),
                badge: tab == .suggestions ? BetaFeature.label : nil)
        }
    }

    /// What a tab is called.
    public static func title(of tab: SettingsTab) -> String {
        switch tab {
        case .general: "General"
        case .languages: "Languages"
        case .dictation: "Dictation"
        case .suggestions: "AI suggestions"
        case .privacy: "Privacy"
        case .diagnostics: "Diagnostics"
        }
    }

    /// The SF Symbol beside a tab's name.
    static func symbolName(of tab: SettingsTab) -> String {
        switch tab {
        case .general: "gearshape"
        case .languages: "globe"
        case .dictation: "mic"
        case .suggestions: "sparkles"
        case .privacy: "checkmark.shield"
        case .diagnostics: "waveform.path.ecg"
        }
    }

    /// The whole page: every tab, which one is showing, and what that one draws or the search found.
    public static func window(
        showing tab: SettingsTab,
        settings: Settings,
        capabilities: SettingsCapabilities = .everything,
        personalisation: SettingsPersonalisation = .nothing,
        at moment: Date = Date(),
        query: String = ""
    ) -> SettingsWindowPresentation {
        let searching = !SearchQuery.needle(in: query).isEmpty
        return SettingsWindowPresentation(
            tabs: tabs(),
            selected: tab,
            pane: searching
                ? search(
                    query, settings: settings, capabilities: capabilities,
                    personalisation: personalisation, at: moment)
                : pane(
                    for: tab, settings: settings, capabilities: capabilities,
                    personalisation: personalisation, at: moment),
            query: query)
    }

    /// One tab, drawn from the settings and what this Mac can do.
    public static func pane(
        for tab: SettingsTab,
        settings: Settings,
        capabilities: SettingsCapabilities = .everything,
        personalisation: SettingsPersonalisation = .nothing,
        at moment: Date = Date()
    ) -> SettingsPane {
        switch tab {
        case .general: general(settings, capabilities)
        case .languages: languages(settings, capabilities)
        case .dictation: dictation(settings, capabilities, personalisation)
        case .suggestions: suggestions(settings, personalisation, capabilities, moment)
        case .privacy: privacy(settings, capabilities, personalisation)
        // Drawn from the diagnostics the main window already holds, so there are no rows here.
        case .diagnostics:
            SettingsPane(
                tab: .diagnostics, title: title(of: .diagnostics), banner: nil, groups: [], callout: nil)
        }
    }

    // MARK: - Search

    /// Every row on every tab that mentions the query, grouped under its tab and card.
    public static func search(
        _ query: String,
        settings: Settings,
        capabilities: SettingsCapabilities = .everything,
        personalisation: SettingsPersonalisation = .nothing,
        at moment: Date = Date(),
        locale: Locale = .autoupdatingCurrent
    ) -> SettingsPane {
        let groups = SettingsTab.allCases.flatMap { tab in
            let pane = pane(
                for: tab, settings: settings, capabilities: capabilities,
                personalisation: personalisation, at: moment)
            return pane.groups.compactMap { group -> SettingsGroup? in
                let heading = [pane.title, group.title].compactMap(\.self).joined(separator: " · ")
                // A card whose heading matches keeps every row, since the heading is what was looked for.
                let rows =
                    SearchQuery.matches([heading], query: query, locale: locale) { [$0] }.isEmpty
                    ? SearchQuery.matches(group.rows, query: query, locale: locale) {
                        [$0.label, $0.explanation, $0.keyedExplanation?.text]
                    }
                    : group.rows
                let kept = rows.filter { $0.style != .add }
                guard !kept.isEmpty else { return nil }
                return SettingsGroup(id: "\(tab.rawValue).\(group.id)", title: heading, rows: kept)
            }
        }
        let needle = SearchQuery.needle(in: query)
        return SettingsPane(
            tab: .general, title: "Search", banner: nil, groups: groups, callout: nil,
            emptySearch: groups.isEmpty ? "No setting mentions “\(needle)”." : nil)
    }

    // MARK: - General

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

    /// One shortcut's row, drawn the same way whichever shortcut it is.
    private static func shortcutRow(
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

    /// General: the shortcuts, the floating button, sound and login, updating, and the two features.
    private static func general(
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

    /// Updating: the version, a way to ask now, and whether to be asked first, feed or no feed.
    private static func updates(
        _ settings: Settings, _ capabilities: SettingsCapabilities
    ) -> SettingsGroup {
        // Both acting rows fail together and for one reason, so they say it the same way.
        let noFeed = "This build has no update feed, so there is nothing to check."

        var rows: [SettingsRow] = []

        if let version = capabilities.versionDescription {
            rows.append(
                SettingsRow(
                    id: "version", label: "Version", control: .text(version),
                    icon: .symbol("cpu", .mint)))
        }

        rows.append(
            SettingsRow(
                id: "checkForUpdates",
                label: "Check for updates",
                explanation: capabilities.canCheckForUpdates
                    ? "Check now even when automatic checks are off." : nil,
                control: .action(title: "Check Now", change: .checkForUpdatesNow),
                unavailability: capabilities.canCheckForUpdates ? nil : noFeed,
                icon: .symbol("arrow.triangle.2.circlepath", .info)))

        rows.append(
            toggleRow(
                .checksForUpdatesAutomatically,
                label: "Check for updates automatically",
                explanation: "Checks the update feed every six hours.",
                settings, capabilities
            ).with(icon: .symbol("arrow.triangle.2.circlepath", .info)))

        rows.append(
            toggleRow(
                .installsUpdatesAutomatically,
                label: "Install updates automatically",
                explanation:
                    "Off means Uttrflow asks first. Either way it never installs mid-dictation.",
                settings, capabilities
            ).with(icon: .symbol("checkmark.shield", .dictation)))

        return SettingsGroup(id: "updates", title: "Updates", rows: rows)
    }

    /// One way of holding the shortcut, as a segmented option.
    private static func activationOption(_ activation: HotkeyActivation) -> SettingsOption {
        let title: String =
            switch activation {
            case .holdToTalk: "Hold to talk"
            case .pressToToggle: "Press to toggle"
            }
        return SettingsOption(
            id: activation.rawValue, title: title, change: .activation(activation))
    }

    // MARK: - Languages

    /// The row saying which languages Uttrflow listens for, as chips with the rest to add.
    static func listenForRow(_ settings: Settings) -> SettingsRow {
        let spoken = settings.profile.preferredLanguages
        let offered = SettingsLanguage.offered
        return SettingsRow(
            id: "spokenLanguages",
            label: "Listen for",
            explanation: "Uttrflow needs at least one",
            control: .languages(
                chips: offered.filter { spoken.contains($0.code) }.map { language in
                    SettingsChip(
                        id: language.id, title: language.name,
                        // The last language cannot come off, so its chip offers no ×.
                        removal: spoken.count > 1 ? .spokenLanguage(language.code, isSpoken: false) : nil)
                },
                add: offered.filter { !spoken.contains($0.code) }.map { language in
                    SettingsOption(
                        id: language.id, title: language.name,
                        change: .spokenLanguage(language.code, isSpoken: true))
                }),
            icon: .symbol("globe", .info))
    }

    /// The row saying how long the user pauses while speaking, so a long pause does not end a sentence.
    static func pausesRow(_ settings: Settings) -> SettingsRow {
        SettingsRow(
            id: "pauses",
            label: "Pauses while you speak",
            explanation: "Longer means Uttrflow waits longer before a pause ends a sentence",
            control: .segmented(
                options: PauseLength.allCases.map { pauses in
                    let title: String =
                        switch pauses {
                        case .usual: "Usual"
                        case .long: "Long"
                        case .veryLong: "Very long"
                        }
                    return SettingsOption(id: pauses.rawValue, title: title, change: .pauses(pauses))
                },
                selectedID: settings.profile.pauses.rawValue),
            icon: .symbol("pause.circle", .info))
    }

    /// The tidying row, shared by every screen that offers the level.
    static func tidyingRow(
        _ level: SettingsTidyingLevel, _ capabilities: SettingsCapabilities
    ) -> SettingsRow {
        SettingsRow(
            id: "tidyingLevel",
            label: SettingsTidyingLevel.rowLabel,
            explanation: SettingsTidyingLevel.rowExplanation,
            control: .segmented(
                options: SettingsTidyingLevel.allCases.map { option in
                    SettingsOption(id: option.rawValue, title: option.title, change: .tidying(option))
                },
                selectedID: level.rawValue),
            unavailability: SettingsEditor.unavailability(ofTidying: .standard, given: capabilities),
            icon: .symbol("wand.and.stars", .suggestion))
    }

    /// The Apple Intelligence cause and its recovery, shown beside the tidying level when it is unavailable.
    static func foundationModelAvailabilityRow(_ capabilities: SettingsCapabilities) -> SettingsRow? {
        guard case .unavailable(let reason) = capabilities.foundationModelAvailability else { return nil }
        let label: String
        let explanation: String
        let control: SettingsControl
        switch reason {
        case .appleIntelligenceDisabled:
            label = "Apple Intelligence is switched off"
            explanation = "Turn it on in System Settings to use full tidying."
            control = .action(
                title: "Open System Settings", change: .openSystemSettings(.appleIntelligence))
        case .modelNotReady:
            label = "Apple Intelligence model is downloading"
            explanation = "Full tidying will be available when the download finishes."
            control = .status("Downloading")
        case .deviceNotEligible:
            label = "This Mac cannot run Apple Intelligence"
            explanation = "Uttrflow will continue tidying with its built-in rules."
            control = .status("Unavailable")
        case .other(let detail):
            label = "Apple Intelligence is unavailable"
            explanation = detail
            control = .status("Unavailable")
        }
        return SettingsRow(
            id: "foundationModelAvailability", label: label, explanation: explanation,
            control: control, icon: .symbol("sparkles", .suggestion))
    }

    /// The sentence the example is spoken as; it needs filler and a slip to show anything.
    static let exampleSpoken = "um so i think we should uh ship it on friday"

    /// The example as the rules every level ends in write it; a test runs them and fails when the two differ.
    static let exampleWritten = "So I think we should ship it on Friday."

    /// The example under the level in force.
    static func tidyExample(_ level: SettingsTidyingLevel) -> SettingsTidyExample {
        SettingsTidyExample(
            groupID: "tidying", spoken: exampleSpoken,
            writtenLabel: "Uttrflow writes · \(level.title)", written: exampleWritten)
    }

    /// Languages: which languages Uttrflow listens for, and how much it tidies, shown on an example.
    private static func languages(
        _ settings: Settings, _ capabilities: SettingsCapabilities
    ) -> SettingsPane {
        let level = SettingsTidyingLevel(preference: settings.engines.transformerPreference)
        return SettingsPane(
            tab: .languages,
            title: title(of: .languages),
            banner: nil,
            groups: [
                SettingsGroup(
                    id: "spoken", title: "Languages you speak",
                    rows: [listenForRow(settings), pausesRow(settings)]),
                SettingsGroup(
                    id: "tidying", title: "Tidying up",
                    rows: [tidyingRow(level, capabilities)]
                        + [foundationModelAvailabilityRow(capabilities)].compactMap(\.self)),
            ],
            callout: SettingsCallout(
                symbolName: "info.circle",
                message:
                    "Mixing English and Hindi in one sentence is expected and handled. Hindi is "
                    + "written in Latin letters the way people type it, never Devanagari, never "
                    + "translated."),
            example: tidyExample(level))
    }

    // MARK: - Dictation

    /// Dictation: how it is transcribed, where the words go, the clean-up steps, and what was learned.
    private static func dictation(
        _ settings: Settings,
        _ capabilities: SettingsCapabilities,
        _ personalisation: SettingsPersonalisation
    ) -> SettingsPane {
        let availabilityGroups = [foundationModelAvailabilityRow(capabilities)].compactMap { row in
            row.map { SettingsGroup(id: "tidyingAvailability", title: "Tidying availability", rows: [$0]) }
        }
        return SettingsPane(
            tab: .dictation,
            title: title(of: .dictation),
            banner: nil,
            groups: [
                SettingsDestinations.places(
                    settings.destinations, recentApps: personalisation.recentDictationApps),
                SettingsDestinations.plainTextApps(
                    personalisation.plainTextApps, overrides: settings.destinations),

                SettingsDestinations.steps(settings.cleaning),
                SettingsGroup(
                    id: "learned",
                    title: "What Uttrflow has picked up",
                    rows: [learnedWordsRow(personalisation)]),
                personalDataTransferGroup,
                pages,
            ].compactMap(\.self) + availabilityGroups,
            callout: SettingsCallout(
                symbolName: "info.circle",
                message:
                    "Dictation runs on this Mac, so it works with or without an internet "
                    + "connection.",
                tint: .dictation))
    }

    /// How many words Uttrflow knows from the user, and the way to the page that lists them.
    static func learnedWordsRow(_ personalisation: SettingsPersonalisation) -> SettingsRow {
        let words = personalisation.learnedWords + personalisation.addedWords
        return SettingsRow(
            id: "learnedWords",
            label: "Words it learned from you",
            explanation: words == 0
                ? "Names and terms appear here as you dictate them"
                : counted(words, "name or term", "names and terms"),
            control: .action(title: "Open Dictionary", change: .openPage(.dictionary)),
            icon: .symbol("book.closed", .amber))
    }

    /// Local backup and restore controls for the words and snippets a person has built up.
    static let personalDataTransferGroup = SettingsGroup(
        id: "personalDataTransfer",
        title: "Your words and snippets",
        rows: [
            SettingsRow(
                id: "exportPersonalData",
                label: "Export personal data",
                explanation: "Save your dictionary and snippets as a local JSON file.",
                control: .action(title: "Export…", change: .exportPersonalData),
                icon: .symbol("square.and.arrow.up", .info)),
            SettingsRow(
                id: "importPersonalData",
                label: "Import personal data",
                explanation: "Merge a local backup. Existing words and triggers are kept.",
                control: .action(title: "Import…", change: .importPersonalData),
                icon: .symbol("square.and.arrow.down", .info)),
        ])

    /// The main window's page that has no sidebar row and no tab here, as a row that opens it.
    static let pages = SettingsGroup(
        id: "pages",
        title: "More in the Uttrflow window",
        rows: [
            pageRow(.corrections, explanation: "What your dictionary changed after it heard you.")
        ])

    /// A row that opens one page of the main window.
    private static func pageRow(_ page: MainTab, explanation: String) -> SettingsRow {
        SettingsRow(
            id: "page.\(page.rawValue)", label: SidebarPresenter.title(for: page),
            explanation: explanation, control: .action(title: "Open", change: .openPage(page)),
            icon: .symbol("text.badge.checkmark", .info))
    }

    // MARK: - Privacy

    /// Privacy: what stays on this Mac and for how long, how Uttrflow looks, and starting over.
    private static func privacy(
        _ settings: Settings, _ capabilities: SettingsCapabilities,
        _ personalisation: SettingsPersonalisation
    ) -> SettingsPane {
        SettingsPane(
            tab: .privacy,
            title: title(of: .privacy),
            banner: nil,
            groups: [
                SettingsGroup(
                    id: "retention",
                    title: "Your data",
                    rows: [retentionRow(settings)] + storageRows(personalisation.storage) + [
                        toggleRow(
                            .sharesUsageStatistics,
                            label: "Share usage statistics",
                            explanation:
                                "Counts and timings, linked to your account when you are signed in. "
                                + "Never what you dictate.",
                            settings, capabilities
                        ).with(icon: .symbol("chart.bar", .info)),
                        toggleRow(
                            .sendsCrashReports,
                            label: "Send crash reports",
                            explanation: SettingsPresenter.crashReportsExplanation,
                            settings, .everything
                        ).with(icon: .symbol("exclamationmark.bubble", .neutral)),
                    ]),
                SettingsGroup(id: "context", title: "Context", rows: [contextLevelRow(settings)]),
                SettingsGroup(
                    id: "network", title: "Network, last \(NetworkActivity.windowDays) days",
                    rows: networkRows(personalisation.network)),
                SettingsGroup(id: "appearance", title: "Appearance", rows: [appearanceRow(settings)]),
                personaGroup(personalisation),
                SettingsGroup(
                    id: "reset",
                    title: "Start over",
                    rows: [forgetLearnedRow(personalisation), resetRow(personalisation)]),
            ],
            callout: SettingsCallout(
                symbolName: "lock",
                message: "\(privacyPromise) \(signingOutKeepsEverything)",
                tint: .dictation))
    }

    /// Dictation first, which no purpose belongs to, then every purpose with its count from the ledger.
    static func networkRows(_ network: [NetworkPurpose: NetworkTally]) -> [SettingsRow] {
        let dictation = SettingsRow(
            id: "network.dictation",
            label: "Dictation",
            explanation: "Nothing you say is uploaded",
            control: .status(counted(0, "request", "requests")),
            icon: .symbol("checkmark.shield", .dictation))
        return [dictation]
            + NetworkPurpose.allCases.map { purpose in
                SettingsRow(
                    id: "network.\(purpose.rawValue)",
                    label: networkLabel(purpose),
                    control: .status(counted(network[purpose]?.count ?? 0, "request", "requests")))
            }
    }

    /// The name each purpose goes by in the Privacy pane.
    static func networkLabel(_ purpose: NetworkPurpose) -> String {
        switch purpose {
        case .account: "Account and sign-in"
        case .modelDownload: "Downloads"
        case .updateCheck: "Update checks"
        case .crashReport: "Crash reports"
        case .usageStatistics: "Usage statistics"
        }
    }

    /// What a crash report carries, in the words the row shows. See `Docs/crash-reporting.md`.
    static let crashReportsExplanation =
        "When Uttrflow crashes or freezes, sends where in its code it happened, the app and macOS "
        + "versions, and nothing you dictated, copied or opened. Off until you turn it on."

    /// Says that signing out is not a reset. See `Docs/ux-settings-model.md`.
    static let signingOutKeepsEverything =
        "Signing out takes nothing away. Your history, your dictionary and these settings "
        + "are files on this Mac; resetting is the only thing that removes them."

    /// The privacy promise, written once for every screen. See `Docs/ux-settings-model.md`.
    static let privacyPromise =
        "\(recordingsPromise) The text is kept on this Mac until you delete it, or for the period you choose. We "
        + "never see it, and it is not tied to your account. Local history, clips, "
        + "suggestions and retry recordings kept on this Mac until deleted are excluded "
        + "from Mac backups that honour that setting."

    /// What happens to the audio, in the one wording every screen repeats. See `Docs/recordings.md`.
    public static let recordingsPromise =
        "Audio is deleted the moment it becomes text, and kept on this Mac for a day only "
        + "if some of it couldn’t be, so you can retry."

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

    /// The order the theme is offered in: following the Mac first, then the two fixed looks.
    static let offeredAppearances: [AppAppearance] = [.system, .light, .dark]

    /// What a theme is called on the segmented control.
    static func title(of appearance: AppAppearance) -> String {
        switch appearance {
        case .system: "System"
        case .light: "Light"
        case .dark: "Dark"
        }
    }

    /// Light, dark, or the same as the Mac.
    static func appearanceRow(_ settings: Settings) -> SettingsRow {
        SettingsRow(
            id: "appearance",
            label: "Theme",
            explanation:
                "Uttrflow is drawn dark unless you would rather have it light, or the same as your Mac.",
            control: .segmented(
                options: offeredAppearances.map { offered in
                    SettingsOption(
                        id: offered.rawValue, title: title(of: offered), change: .appearance(offered))
                },
                selectedID: settings.appearance.rawValue),
            icon: .symbol("moon", .suggestion))
    }

    /// What each context level is called in its menu.
    static func title(of level: ContextLevel) -> String {
        switch level {
        case .identity: "App name only"
        case .nearCaret: "Text near the cursor"
        }
    }

    /// How much of the app in front a dictation reads: its name only, or the text around the cursor too.
    static func contextLevelRow(_ settings: Settings) -> SettingsRow {
        SettingsRow(
            id: "contextLevel",
            label: "What dictation reads",
            explanation: settings.contextLevel == .identity
                ? "Only the name of the app you dictate into. Formatting falls back to its defaults."
                : "The app's name, its window title and the text around your cursor, to format your words.",
            control: .segmented(
                options: ContextLevel.allCases.map { level in
                    SettingsOption(id: level.rawValue, title: title(of: level), change: .contextLevel(level))
                },
                selectedID: settings.contextLevel.rawValue),
            icon: .symbol("eye", .info))
    }

    /// How long the text of a dictation survives, offering only periods the store round-trips.
    private static func retentionRow(_ settings: Settings) -> SettingsRow {
        let days = settings.transcriptRetentionDays
        return SettingsRow(
            id: "transcripts",
            label: "Keep transcripts for",
            explanation: "Choose a limit to delete older ones automatically",
            control: .menu(
                options: SettingsRetention.offeredDays.map { offered in
                    SettingsOption(
                        id: String(offered), title: SettingsRetention.title(days: offered),
                        change: .retention(days: offered))
                },
                selectedID: String(days)),
            icon: .symbol("clock", .info))
    }

    /// One read-only row per store a person would recognise, saying what it occupies on this Mac.
    static func storageRows(_ storage: [LocalStoreUsage]) -> [SettingsRow] {
        storage.sorted { storageRank($0.entry) < storageRank($1.entry) }.compactMap { usage in
            storageLabel(usage.entry).map { label in
                SettingsRow(
                    id: "storage.\(usage.entry.rawValue)",
                    label: label,
                    control: .status(usage.bytes.formatted(.byteCount(style: .file))))
            }
        }
    }

    /// Where a store sits in the list: the order ``storageLabel(_:)`` names them in, speech first.
    private static func storageRank(_ entry: LocalStoreEntry) -> Int {
        storageOrder.firstIndex(of: entry) ?? storageOrder.count
    }

    private static let storageOrder: [LocalStoreEntry] = [
        .dictationHistory, .recordings, .personalDictionary, .snippets, .evidenceLedger, .predict,
        .predictConsent, .clipboard, .clipboardImages, .savedClips, .notSecretClips, .clipboardPreferences,
        .networkActivity,
        .speechModels, .speechModelLoads,
    ]

    /// The name each store goes by in the Privacy pane; the key and the lock are the app's own, so they have none.
    static func storageLabel(_ entry: LocalStoreEntry) -> String? {
        switch entry {
        case .dictationHistory: "Transcripts"
        case .recordings: "Recordings"
        case .personalDictionary: "Dictionary"
        case .snippets: "Snippets"
        case .evidenceLedger: "What Uttrflow has learned about you"
        case .predict: "AI suggestions"
        case .predictConsent: "AI suggestion choices"
        case .clipboard: "Clipboard history"
        case .clipboardImages: "Copied images"
        case .savedClips: "Saved clips"
        case .notSecretClips: "Clips marked not secret"
        case .clipboardPreferences: "Clipboard settings"
        case .networkActivity: "Network log"
        case .speechModels: "Speech recognition"
        case .speechModelLoads: "Speech start-up times"
        case .encryptionKey, .legacyMigrationMarker, .instanceLock: nil
        }
    }

    // MARK: - Persona

    /// Every fact the evidence ledger records, each with its own Remove, and a reset for all of them.
    static func personaGroup(_ personalisation: SettingsPersonalisation) -> SettingsGroup {
        let items = personalisation.persona.map { item in
            SettingsRow(
                id: "persona.\(item.id)", label: item.title, explanation: item.detail,
                control: .removal(
                    SettingsRemoval(reset: .personaFact(item.fact), title: "Remove", confirmation: nil)),
                style: .inset)
        }
        guard !personalisation.persona.isEmpty else {
            return SettingsGroup(
                id: "persona", title: "What Uttrflow noticed about you",
                rows: [
                    SettingsRow(
                        id: "resetPersona", label: "Nothing noticed yet",
                        explanation:
                            "Words you use and how you write in each kind of app appear here as you dictate.",
                        control: .status("Empty"), icon: .symbol("person.crop.circle", .amber))
                ])
        }
        let count = counted(personalisation.persona.count, "thing", "things")
        let reset = SettingsRow(
            id: "resetPersona",
            label: "Reset what Uttrflow noticed",
            explanation: "Forget \(count) noticed from your dictations. Your dictionary and history stay.",
            control: .removal(
                SettingsRemoval(
                    reset: .persona, title: "Reset…",
                    confirmation: SettingsConfirmation(
                        title: "Reset what Uttrflow noticed?",
                        message:
                            "This removes \(count) Uttrflow noticed from your dictations. "
                            + "Your dictionary and history stay. This cannot be undone.",
                        confirmTitle: "Reset", cancelTitle: "Cancel"))),
            unavailability: SettingsEditor.unavailability(of: .persona, given: personalisation),
            icon: .symbol("person.crop.circle", .amber))
        return SettingsGroup(id: "persona", title: "What Uttrflow noticed about you", rows: [reset] + items)
    }

    // MARK: - Forgetting

    /// Everything automatic goes and everything deliberate stays, counted in the row so it asks nothing.
    private static func forgetLearnedRow(
        _ personalisation: SettingsPersonalisation
    ) -> SettingsRow {
        SettingsRow(
            id: "forgetLearned",
            label: "Forget what was learned",
            explanation: forgetLearnedSentence(personalisation),
            control: .removal(
                SettingsRemoval(reset: .learnedWords, title: "Forget", confirmation: nil)),
            unavailability: SettingsEditor.unavailability(
                of: .learnedWords, given: personalisation),
            icon: .symbol("book.closed", .amber))
    }

    /// What forgetting takes and what it keeps, counted. See `Docs/ux-settings-model.md`.
    private static func forgetLearnedSentence(
        _ personalisation: SettingsPersonalisation
    ) -> String {
        let learned = counted(personalisation.learnedWords, "learned word", "learned words")
        switch (personalisation.learnedWords, personalisation.addedWords) {
        case (0, _):
            // The row is off here, so VoiceOver reads what the button would do, not a count of nothing.
            return "Words Uttrflow worked out for itself go. Words you added yourself stay."
        case (_, 0):
            return "Forget \(learned). You have not added any of your own."
        case (_, let added):
            return "Forget \(learned), keeping \(added) you added yourself."
        }
    }

    /// A fresh install, and the only level that asks first; never greyed out.
    private static func resetRow(_ personalisation: SettingsPersonalisation) -> SettingsRow {
        SettingsRow(
            id: "resetPersonalisation",
            label: "Reset personalisation",
            explanation:
                "Puts Uttrflow back to a fresh install: your dictionary, history, clipboard, "
                + "snippets, learned completions and the apps they may learn from, recordings "
                + "kept for a retry and every preference on this screen are deleted from this Mac.",
            control: .removal(
                SettingsRemoval(
                    reset: .everything,
                    // The ellipsis is the platform's promise that pressing it asks first.
                    title: "Reset…",
                    confirmation: resetConfirmation(personalisation))),
            unavailability: SettingsEditor.unavailability(
                of: .everything, given: personalisation),
            icon: .symbol("trash", .danger))
    }

    /// The question, with the real numbers in it.
    private static func resetConfirmation(
        _ personalisation: SettingsPersonalisation
    ) -> SettingsConfirmation {
        SettingsConfirmation(
            title: "Reset personalisation?",
            message: resetSentence(personalisation),
            confirmTitle: "Reset",
            // Named rather than assumed, so a test can say which button Return presses.
            cancelTitle: "Cancel")
    }

    /// What a reset takes, built only from the parts there are. See `Docs/ux-settings-model.md`.
    private static func resetSentence(_ personalisation: SettingsPersonalisation) -> String {
        let preferences = "puts every preference back to its default. It cannot be undone."
        // Uncounted, as no count reaches here, but always named: the loss least expected.
        let uncounted =
            "your whole clipboard history, pinned clips included, your snippets and learned "
            + "completions"
        let parts = [wordsPhrase(personalisation), transcriptsPhrase(personalisation)]
            .compactMap(\.self)
        guard !parts.isEmpty else {
            return "This removes \(uncounted), and \(preferences)"
        }
        return "This removes \(parts.joined(separator: ", ")), \(uncounted), and \(preferences)"
    }

    /// The dictionary half, split the way the gentler level splits it, or `nil` when it is empty.
    private static func wordsPhrase(_ personalisation: SettingsPersonalisation) -> String? {
        switch (personalisation.learnedWords, personalisation.addedWords) {
        case (0, 0):
            nil
        case (0, let added):
            "\(counted(added, "word", "words")) you added yourself"
        case (let learned, 0):
            "\(counted(learned, "learned word", "learned words")) from your dictionary"
        case (let learned, let added):
            // Bracketed, because this phrase is joined to another and a loose dash reads as a break.
            "\(counted(personalisation.words, "word", "words")) from your dictionary "
                + "(\(learned) it learned, \(added) you added yourself)"
        }
    }

    /// The transcript half, or `nil` when there are none saved.
    private static func transcriptsPhrase(_ personalisation: SettingsPersonalisation) -> String? {
        guard personalisation.transcripts > 0 else { return nil }
        return counted(personalisation.transcripts, "saved transcript", "saved transcripts")
    }

    /// A number and the noun that agrees with it, in one place, so "1 words" cannot appear.
    static func counted(_ count: Int, _ singular: String, _ plural: String) -> String {
        "\(count) \(count == 1 ? singular : plural)"
    }

    // MARK: - Rows

    /// A switch row, taking its reason for being off from the ``SettingsEditor`` that refuses it.
    static func toggleRow(
        _ field: SettingsToggleField,
        label: String,
        explanation: String? = nil,
        _ settings: Settings,
        _ capabilities: SettingsCapabilities
    ) -> SettingsRow {
        let isOn = value(of: field, in: settings)
        return SettingsRow(
            id: field.rawValue,
            label: label,
            explanation: explanation,
            control: .toggle(field: field, isOn: isOn),
            unavailability: SettingsEditor.unavailability(
                of: field, given: capabilities, in: settings))
    }

    /// Where a switch reads its state from, in the one place that knows.
    static func value(of field: SettingsToggleField, in settings: Settings) -> Bool {
        switch field {
        case .dictationEnabled: settings.dictationEnabled
        case .handsFreeEnabled: settings.handsFreeEnabled
        case .clipboardEnabled: settings.clipboardEnabled
        case .showsFloatingButton: settings.showsFloatingButton
        case .shrinksToGripWhenIdle: settings.shrinksToGripWhenIdle
        case .minimisesWhileDictating: settings.minimisesWhileDictating
        case .playsSoundWhenRecordingStarts: settings.playsSoundWhenRecordingStarts
        case .opensAtLogin: settings.opensAtLogin
        case .checksForUpdatesAutomatically: settings.checksForUpdatesAutomatically
        case .installsUpdatesAutomatically: settings.installsUpdatesAutomatically
        case .sharesUsageStatistics: settings.sharesUsageStatistics
        case .sendsCrashReports: settings.sendsCrashReports
        case .suggestionsEnabled: settings.suggestions.isEnabled
        case .quietSuggestions: settings.suggestions.isQuiet
        }
    }
}
