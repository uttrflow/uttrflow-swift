import UttrflowCore
public import UttrflowSettings

/// The whole window, as the view is given it.
public struct SettingsWindowPresentation: Sendable, Equatable {
    public let tabs: [SettingsTabItem]
    public let selected: SettingsTab
    public let pane: SettingsPane
}

/// Turns the user's settings into what the Settings window draws.
///
/// The same pattern as `DictationPresenter`, and for the same reason: every decision
/// about what appears, what it says and whether it can be touched is made here, where a
/// test can read it back, rather than in a view where it can only be looked at. No
/// string this produces names an engine, a model or a file — §16 applies to the
/// settings screen exactly as it does to the floating button, so choosing "how much
/// help" never becomes choosing "which implementation".
public enum SettingsPresenter {
    /// Every tab, in sidebar order.
    ///
    /// Driven by ``SettingsTab/allCases`` so that adding a case adds a tab. The switch
    /// below is exhaustive, so adding one without giving it a name will not compile.
    public static func tabs() -> [SettingsTabItem] {
        SettingsTab.allCases.map { tab in
            switch tab {
            case .general:
                SettingsTabItem(tab: tab, title: "General", symbolName: "gearshape")
            case .languages:
                SettingsTabItem(tab: tab, title: "Languages", symbolName: "globe")
            case .dictation:
                SettingsTabItem(tab: tab, title: "Dictation", symbolName: "mic")
            case .privacy:
                SettingsTabItem(tab: tab, title: "Privacy", symbolName: "lock")
            }
        }
    }

    public static func window(
        showing tab: SettingsTab,
        settings: Settings,
        capabilities: SettingsCapabilities = .everything,
        personalisation: SettingsPersonalisation = .nothing
    ) -> SettingsWindowPresentation {
        SettingsWindowPresentation(
            tabs: tabs(),
            selected: tab,
            pane: pane(
                for: tab, settings: settings, capabilities: capabilities,
                personalisation: personalisation)
        )
    }

    public static func pane(
        for tab: SettingsTab,
        settings: Settings,
        capabilities: SettingsCapabilities = .everything,
        personalisation: SettingsPersonalisation = .nothing
    ) -> SettingsPane {
        switch tab {
        case .general: general(settings, capabilities)
        case .languages: languages(settings, capabilities)
        case .dictation: dictation(settings, capabilities, personalisation)
        case .privacy: privacy(settings, personalisation)
        }
    }

    // MARK: - General

    private static func general(
        _ settings: Settings, _ capabilities: SettingsCapabilities
    ) -> SettingsPane {
        SettingsPane(
            tab: .general,
            title: "General",
            banner: nil,
            groups: [
                SettingsGroup(
                    id: "shortcut",
                    title: nil,
                    rows: [
                        SettingsRow(
                            id: "hotkey",
                            label: "Dictation shortcut",
                            // Only when Fn is the shortcut, because it is the only one
                            // macOS has its own plans for. Uttrflow watches Fn rather
                            // than registering it — nothing can register a modifier —
                            // and watching cannot stop the emoji picker or Apple's own
                            // dictation opening on the same press. Saying so here is the
                            // difference between a setting somebody adjusts once and a
                            // shortcut that looks broken.
                            explanation: settings.hotkey.heldModifier == nil
                                ? nil
                                : """
                                If pressing fn also opens Emoji or Apple's dictation, \
                                set System Settings → Keyboard → "Press 🌐 key to" to \
                                Do Nothing.
                                """,
                            control: .shortcut(keys: SettingsShortcut.keycaps(for: settings.hotkey))
                        ),
                        SettingsRow(
                            id: "activation",
                            label: "Activation",
                            explanation:
                                "Hold: release to finish. Toggle: press once to start, again to stop.",
                            control: .segmented(
                                options: HotkeyActivation.allCases.map(activationOption),
                                selectedID: settings.hotkeyActivation.rawValue)
                        ),
                    ]),
                SettingsGroup(
                    id: "floatingButton",
                    title: "Floating button",
                    rows: [
                        toggleRow(
                            .showsFloatingButton,
                            label: "Show the floating button",
                            explanation: "Press and hold it to dictate, exactly like the shortcut.",
                            settings, capabilities),
                        SettingsRow(
                            id: "anchor",
                            label: "Position",
                            control: .anchorPicker(selected: settings.floatingButtonAnchor),
                            // The same dependency the grip switch has, said the same way:
                            // there is nothing to position while there is no button.
                            unavailability: settings.showsFloatingButton
                                ? nil : "Turn the floating button on before choosing where it sits."
                        ),
                        toggleRow(
                            .shrinksToGripWhenIdle,
                            label: "Shrink it to a grip until I point at it",
                            settings, capabilities),
                        toggleRow(
                            .minimisesWhileDictating,
                            label: "Get Uttrflow out of the way while I dictate",
                            explanation:
                                "Minimises the window so you can see what you are typing into.",
                            settings, capabilities),
                    ]),
                SettingsGroup(
                    id: "appearance",
                    title: nil,
                    rows: [appearanceRow(settings)]),
                SettingsGroup(
                    id: "system",
                    title: nil,
                    rows: [
                        toggleRow(
                            .playsSoundWhenRecordingStarts,
                            label: "Play a sound when recording starts",
                            settings, capabilities),
                        toggleRow(
                            .opensAtLogin, label: "Open at login", settings, capabilities),
                    ]),
                updates(settings, capabilities),
            ],
            callout: nil)
    }

    /// Updating: which build this is, a way to ask now, and whether to be asked first.
    ///
    /// The group stays present in a build with no feed, showing the version and saying
    /// why the rest cannot act, rather than vanishing. A section that disappears leaves
    /// somebody hunting for a control they remember seeing; one that explains itself
    /// answers the question they usually came with, which is "what version am I on?"
    private static func updates(
        _ settings: Settings, _ capabilities: SettingsCapabilities
    ) -> SettingsGroup {
        // Both of the acting rows fail together and for one reason, so they say it the
        // same way rather than inventing two sentences for one situation.
        let noFeed = "This build has no update feed, so there is nothing to check."

        var rows: [SettingsRow] = []

        if let version = capabilities.versionDescription {
            rows.append(SettingsRow(id: "version", label: "Version", control: .text(version)))
        }

        rows.append(
            SettingsRow(
                id: "checkForUpdates",
                label: "Check for updates",
                explanation: capabilities.canCheckForUpdates
                    ? "Uttrflow also checks on its own every six hours." : nil,
                control: .action(title: "Check Now", change: .checkForUpdatesNow),
                unavailability: capabilities.canCheckForUpdates ? nil : noFeed))

        rows.append(
            toggleRow(
                .installsUpdatesAutomatically,
                label: "Install updates automatically",
                explanation:
                    "Off means Uttrflow asks first. Either way it never installs mid-dictation.",
                settings, capabilities))

        return SettingsGroup(id: "updates", title: "Updates", rows: rows)
    }

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

    private static func languages(
        _ settings: Settings, _ capabilities: SettingsCapabilities
    ) -> SettingsPane {
        let spoken = settings.profile.preferredLanguages
        let level = SettingsTidyingLevel(preference: settings.engines.transformerPreference)
        return SettingsPane(
            tab: .languages,
            title: "Languages",
            banner: nil,
            groups: [
                SettingsGroup(
                    id: "spoken",
                    title: "Languages you speak",
                    rows: SettingsLanguage.offered.map { language in
                        let isSpoken = spoken.contains(language.code)
                        return SettingsRow(
                            id: language.id,
                            label: language.name,
                            explanation: language.endonym,
                            control: .tick(
                                isTicked: isSpoken,
                                change: .spokenLanguage(language.code, isSpoken: !isSpoken)),
                            // The last one cannot come off, so it says so before it is
                            // tried rather than refusing afterwards.
                            unavailability: isSpoken && spoken.count == 1
                                ? "Uttrflow needs at least one language to listen for." : nil)
                    }),
                SettingsGroup(
                    id: "tidying",
                    title: "Tidying up",
                    rows: [
                        SettingsRow(
                            id: "tidyingLevel",
                            label: SettingsTidyingLevel.rowLabel,
                            explanation: SettingsTidyingLevel.rowExplanation,
                            control: .segmented(
                                options: SettingsTidyingLevel.allCases.map { option in
                                    SettingsOption(
                                        id: option.rawValue, title: option.title,
                                        change: .tidying(option))
                                },
                                selectedID: level.rawValue),
                            unavailability: SettingsEditor.unavailability(
                                ofTidying: .standard, given: capabilities))
                    ]),
            ],
            callout: SettingsCallout(
                symbolName: "globe",
                message:
                    "Mixing English and Hindi in one sentence is expected and handled. Tidying up "
                    + "is strongest in English today — Hindi gets punctuation and spacing, not "
                    + "rewriting."))
    }

    // MARK: - Dictation

    private static func dictation(
        _ settings: Settings,
        _ capabilities: SettingsCapabilities,
        _ personalisation: SettingsPersonalisation
    ) -> SettingsPane {
        let quality = SettingsTranscriptionQuality(engine: settings.engines.speech)
        return SettingsPane(
            tab: .dictation,
            title: "Dictation",
            banner: nil,
            groups: [
                SettingsGroup(
                    id: "recognition",
                    title: "Speech recognition",
                    rows: [
                        SettingsRow(
                            id: "quality",
                            label: "Speed and accuracy",
                            explanation:
                                "Most accurate takes a second or two longer and gets more names, "
                                + "numbers and technical terms right.",
                            control: .segmented(
                                options: SettingsTranscriptionQuality.allCases.map(qualityOption),
                                selectedID: quality.rawValue),
                            // Off only when neither option can run, which is the one
                            // case where moving the control could achieve nothing.
                            unavailability: capabilities.readySpeechEngines.isEmpty
                                ? "This option needs a download that has not finished yet." : nil)
                    ]),
                SettingsGroup(
                    id: "learned",
                    title: "What Uttrflow has picked up",
                    rows: [forgetLearnedRow(personalisation)]),
            ],
            callout: SettingsCallout(
                symbolName: "gauge",
                message:
                    "Dictation runs on this Mac, so it works with or without an internet "
                    + "connection."))
    }

    private static func qualityOption(_ quality: SettingsTranscriptionQuality) -> SettingsOption {
        SettingsOption(
            id: quality.rawValue, title: quality.title, change: .transcription(quality))
    }

    // MARK: - Privacy

    private static func privacy(
        _ settings: Settings, _ personalisation: SettingsPersonalisation
    ) -> SettingsPane {
        SettingsPane(
            tab: .privacy,
            title: "Privacy",
            banner: SettingsBanner(
                symbolName: "lock",
                title: "Your words stay on your Mac",
                message: SettingsPresenter.privacyPromise),
            groups: [
                SettingsGroup(
                    id: "retention",
                    title: nil,
                    rows: [retentionRow(settings)]),
                SettingsGroup(
                    id: "reset",
                    title: nil,
                    rows: [resetRow(personalisation)]),
            ],
            callout: SettingsCallout(
                symbolName: "person.crop.circle",
                message: SettingsPresenter.signingOutKeepsEverything))
    }

    /// Signing out is not a reset, said where the user might otherwise assume it is.
    ///
    /// Everything Uttrflow holds is a file on this Mac and none of it belongs to an
    /// account, so signing out has nothing to take. A user who believes otherwise makes
    /// one of two mistakes and both are bad: they sign out to clear their history and it
    /// is still there, or they avoid signing out on a shared Mac because they think it
    /// would erase their dictionary. This says which button does which.
    static let signingOutKeepsEverything =
        "Signing out takes nothing away. Your history, your dictionary and these settings "
        + "are files on this Mac; resetting is the only thing that removes them."

    /// The promise, written once.
    ///
    /// Every screen that repeats it repeats this, because a promise the user meets in
    /// three wordings is a promise they have to work out for themselves. It says what
    /// is true: audio is held in memory for the length of one dictation and is never
    /// written anywhere, and the text of it is the only thing there is a period for.
    /// It stops short of claiming Uttrflow never reaches the network, which would be a
    /// second inaccuracy in place of the one it replaces — the speech model arrives
    /// over one.
    ///
    /// It no longer claims there is no account either. There is one, and the sentence
    /// that denied it was the same kind of over-promise as the audio claim: comfortable,
    /// in the user's favour, and false the moment the Account page shipped. What is true
    /// is that the text is not attached to it, which is also what makes signing out
    /// harmless — see ``signingOutKeepsEverything``.
    static let privacyPromise =
        "\(recordingsPromise) The text is kept on this Mac and deleted automatically. We "
        + "never see it, and it is not tied to your account."

    /// What happens to the audio, in the one wording every screen repeats. See `Docs/recordings.md`.
    public static let recordingsPromise =
        "Audio is deleted the moment it becomes text, and kept on this Mac for a day only "
        + "if it couldn’t be, so you can retry."

    /// The one period there is: how long the text of a dictation survives.
    ///
    /// The pop-up offers only periods the store keeps exactly as they are given, so
    /// there is no choice the user can make here that reopens showing something else.
    /// Light, dark, or whatever the Mac is set to.
    ///
    /// Offered rather than assumed, and defaulted to light — see ``AppAppearance``. The
    /// row sits in General beside the other things about how the app looks rather than in
    /// a pane of its own, because it is one choice and a pane for it would be a pane
    /// nobody opens twice.
    static func appearanceRow(_ settings: Settings) -> SettingsRow {
        SettingsRow(
            id: "appearance",
            label: "Appearance",
            explanation:
                "Uttrflow is drawn dark unless you would rather have it light, or the same as your Mac.",
            control: .menu(
                options: AppAppearance.allCases.map { offered in
                    SettingsOption(
                        id: offered.rawValue, title: offered.title,
                        change: .appearance(offered))
                },
                selectedID: settings.appearance.rawValue))
    }

    private static func retentionRow(_ settings: Settings) -> SettingsRow {
        let days = settings.transcriptRetentionDays
        return SettingsRow(
            id: "transcripts",
            label: "Keep transcripts for",
            explanation:
                "How long the finished text stays in your history, so you can copy or "
                + "re-insert it. Deleted automatically after that.",
            control: .menu(
                options: SettingsRetention.offeredDays.map { offered in
                    SettingsOption(
                        id: String(offered), title: SettingsRetention.title(days: offered),
                        change: .retention(days: offered))
                },
                selectedID: String(days)))
    }

    // MARK: - Forgetting

    /// The third level: everything automatic goes, everything deliberate stays.
    ///
    /// The one that will actually be used, so it is the one that must not need a
    /// dialogue. The count is in the row itself, above the button, which is what makes
    /// the button safe to press without being asked to confirm: the user has already
    /// read what it will take by the time they reach it.
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
                of: .learnedWords, given: personalisation))
    }

    /// What forgetting would take, counted, before it is taken.
    ///
    /// Both halves of the trade are named, because the reason this level exists at all
    /// is that the words the user typed in survive it. A sentence that mentioned only
    /// what goes would describe the reset instead, and they would not press it.
    private static func forgetLearnedSentence(
        _ personalisation: SettingsPersonalisation
    ) -> String {
        let learned = counted(personalisation.learnedWords, "learned word", "learned words")
        switch (personalisation.learnedWords, personalisation.addedWords) {
        case (0, _):
            // The row is off in this state, so this is what VoiceOver reads alongside
            // the reason: what the button would do, rather than a count of nothing.
            return "Words Uttrflow worked out for itself go. Words you added yourself stay."
        case (_, 0):
            return "Forget \(learned). You have not added any of your own."
        case (_, let added):
            return "Forget \(learned), keeping \(added) you added yourself."
        }
    }

    /// The fourth level, and the only one that asks first.
    ///
    /// Available even when there is nothing saved: preferences are always there to put
    /// back, so there is no state in which this achieves nothing, and greying it out
    /// would strand the user who has come here precisely to start again.
    private static func resetRow(_ personalisation: SettingsPersonalisation) -> SettingsRow {
        SettingsRow(
            id: "resetPersonalisation",
            label: "Reset personalisation",
            explanation:
                "Puts Uttrflow back to a fresh install: your dictionary, your history and "
                + "every preference on this screen.",
            control: .removal(
                SettingsRemoval(
                    reset: .everything,
                    // The ellipsis is the platform's promise that pressing it asks
                    // first, and it is kept: this is the one removal with a dialogue.
                    title: "Reset…",
                    confirmation: resetConfirmation(personalisation))),
            unavailability: SettingsEditor.unavailability(
                of: .everything, given: personalisation))
    }

    /// The question, with the real numbers in it.
    private static func resetConfirmation(
        _ personalisation: SettingsPersonalisation
    ) -> SettingsConfirmation {
        SettingsConfirmation(
            title: "Reset personalisation?",
            message: resetSentence(personalisation),
            confirmTitle: "Reset",
            // Named here rather than assumed by the window, so that the button which
            // does nothing is the default by decision and a test can say so.
            cancelTitle: "Cancel")
    }

    /// What a reset would take, counted.
    ///
    /// Built from the parts there actually are. A dialogue that offers to remove "0
    /// transcripts" is a dialogue nobody finishes reading, and it also quietly misstates
    /// the case: with nothing saved, a reset really is only the preferences.
    private static func resetSentence(_ personalisation: SettingsPersonalisation) -> String {
        let preferences = "puts every preference back to its default. It cannot be undone."
        let parts = [wordsPhrase(personalisation), transcriptsPhrase(personalisation)]
            .compactMap(\.self)
        guard !parts.isEmpty else {
            return "There is nothing of yours saved, so this only \(preferences)"
        }
        return "This removes \(parts.joined(separator: " and ")), and \(preferences)"
    }

    /// The dictionary half, split the same way the gentler level splits it, so the user
    /// can see what a reset takes that forgetting would have left them.
    private static func wordsPhrase(_ personalisation: SettingsPersonalisation) -> String? {
        switch (personalisation.learnedWords, personalisation.addedWords) {
        case (0, 0):
            nil
        case (0, let added):
            "\(counted(added, "word", "words")) you added yourself"
        case (let learned, 0):
            "\(counted(learned, "learned word", "learned words")) from your dictionary"
        case (let learned, let added):
            // Bracketed rather than set off with dashes, because this phrase is joined
            // to another one and a dash left open mid-sentence reads as a break in it.
            "\(counted(personalisation.words, "word", "words")) from your dictionary "
                + "(\(learned) it learned, \(added) you added yourself)"
        }
    }

    private static func transcriptsPhrase(_ personalisation: SettingsPersonalisation) -> String? {
        guard personalisation.transcripts > 0 else { return nil }
        return counted(personalisation.transcripts, "saved transcript", "saved transcripts")
    }

    /// A number and the noun that agrees with it, in one place, because "1 words" is the
    /// kind of thing that survives every review and undermines every count beside it.
    private static func counted(_ count: Int, _ singular: String, _ plural: String) -> String {
        "\(count) \(count == 1 ? singular : plural)"
    }

    // MARK: - Rows

    /// Every switch, from one description of what a switch row is.
    ///
    /// The reason a switch is off comes from ``SettingsEditor``, which is also what
    /// refuses the change, so a row drawn as operable and a change accepted as valid
    /// cannot come apart.
    private static func toggleRow(
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

    static func value(of field: SettingsToggleField, in settings: Settings) -> Bool {
        switch field {
        case .showsFloatingButton: settings.showsFloatingButton
        case .shrinksToGripWhenIdle: settings.shrinksToGripWhenIdle
        case .minimisesWhileDictating: settings.minimisesWhileDictating
        case .playsSoundWhenRecordingStarts: settings.playsSoundWhenRecordingStarts
        case .opensAtLogin: settings.opensAtLogin
        case .installsUpdatesAutomatically: settings.installsUpdatesAutomatically
        }
    }
}
