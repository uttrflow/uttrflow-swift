// Builds the settings metadata for forgetting personalisation.

extension SettingsPresenter {
    // MARK: - Forgetting

    /// Everything automatic goes and everything deliberate stays, counted in the row so it asks nothing.
    static func forgetLearnedRow(
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
    static func resetRow(_ personalisation: SettingsPersonalisation) -> SettingsRow {
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
        return counted(personalisation.transcripts, "saved dictation", "saved dictations")
    }

    /// A number and the noun that agrees with it, in one place, so "1 words" cannot appear.
    static func counted(_ count: Int, _ singular: String, _ plural: String) -> String {
        "\(count) \(count == 1 ? singular : plural)"
    }

}
