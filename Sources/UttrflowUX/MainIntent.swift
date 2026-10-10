// The main window's shared intent and action vocabulary.
public import Foundation
public import UttrflowCore
public import UttrflowHistory

/// What clicking something in the main window means, named so a page compares in a test.
public enum MainIntent: Sendable, Equatable {
    /// Something only macOS can grant, in the same vocabulary a failure uses.
    case recover(RecoveryAction)
    /// Somewhere else in the app.
    case go(AppLocation)
    /// Another page of this window; separate from ``go(_:)`` only because ``MainTab`` cannot name every page.
    case show(MainTab)
    /// Read the current page's list in the order this identifier names.
    case sort(String)
    /// Put this text on the clipboard.
    case copy(String)
    /// Put this text back into whatever the user is typing in.
    case insert(String)
    /// Start a dictation, or stop the one running; the same toggle the menu bar and the Dock use.
    case dictate
    /// Open History with the caret in its search field.
    case search
    /// Remove the locally downloaded suggestion model.
    case removeSuggestionModel

    /// This dictation came out wrong: the honest input to teaching.
    case flagDictation(UUID)
    /// This dictation came out wrong in this way: a flag that names its error class.
    case flagDictationAs(UUID, FlagReason)
    /// Open a masked, editable report of this dictation to copy or save; nothing is sent.
    case reportDictation(UUID)
    /// Open the word editor with this spelling as "Say it like", so the right spelling is typed once.
    case fixWord(String)
    /// Keep this dictation in clipboard history by choice.
    case keepDictationAsClip(UUID)
    /// Delete a dictation from history.
    case forgetDictation(UUID)

    /// Run a kept recording through transcription again.
    case retryRecording(UUID)
    /// Delete a kept recording without ever hearing it.
    case forgetRecording(UUID)
    /// Play a kept recording, or stop it if it is playing.
    case playRecording(UUID)

    /// Put a changed word back to what was heard.
    case undoCorrection(UUID)
    /// Let a vetoed heard-to-meant pairing be made again.
    case allowPairing(heard: String, meant: String)

    /// Open the inline word editor; the word arrives on ``saveWord(word:pronunciation:applications:)``.
    case addWord
    /// Commit the inline word editor as a new word; an edited word arrives as ``replaceWord(_:word:pronunciation:applications:)``.
    case saveWord(word: String, pronunciation: String, applications: [String])
    /// Open the inline word editor on this word, keeping its identity and counters on save.
    case editWord(UUID)
    /// Close the inline word editor unchanged.
    case cancelWordEdit
    /// Delete the named words from the dictionary in one write, refusing each one.
    case forgetWords(Set<UUID>)
    /// Trust the named retired words again, and let them start earning their place.
    case restoreWords(Set<UUID>)
    /// Respell an existing word as typed in the editor, keeping its counters.
    case replaceWord(UUID, word: String, pronunciation: String, applications: [String])
    /// Fold the second spelling of one word into the first, summing their counters.
    case mergeWords(keeping: UUID, absorbing: UUID)
    /// Let a deleted spelling be learned again.
    case allowWord(String)
    /// Say the word typed in the editor once, to see whether it is recognised; nothing is saved.
    case tryDraft(word: String, pronunciation: String)
    /// Say a saved word once, to see whether it is recognised; nothing is saved.
    case tryWord(UUID)
    /// Say the word typed in the editor once, filling its "Say it like" with what the recogniser writes alone.
    case sayDraft(word: String)
    /// Add what a try heard as a "Say it like": to the open editor, or to this word opened in it.
    case useSayItLike(UUID?, heard: String)

    /// Open the inline snippet editor empty.
    case addSnippet
    /// Open the inline snippet editor on this snippet.
    case editSnippet(UUID)
    /// Delete a snippet.
    case forgetSnippet(UUID)
    /// Restore the snippet held by the latest deletion notice.
    case restoreSnippet(UUID)
    /// Restore valid clipboard privacy settings from their set-aside file.
    case restoreClipboardPreferences
    /// Commit the inline editor; `replacing` is the snippet being edited, or `nil` for a new one.
    case saveSnippet(trigger: String, text: String, applications: [String], replacing: UUID?)
    /// Close the inline snippet editor unchanged.
    case cancelSnippetEdit

    /// A setting changed from the main window, as the same ``SettingsChange`` the settings window reports.
    case change(SettingsChange)

    /// Open onboarding at the sign-in page.
    case signIn
    /// End the session on this Mac.
    case signOut
    /// Delete the account on the server, then end the session on this Mac.
    case deleteAccount
    /// Put away the notice in the window's corner.
    case dismissNotice
}

/// Something a page offers the user to click.
public struct MainAction: Sendable, Equatable, Identifiable {
    /// The words on the button.
    public let title: String
    /// The symbol on an icon-only button. Absent where the title is the button.
    public let symbolName: String?
    /// What pressing it means.
    public let intent: MainIntent
    /// Whether this destroys something. Drawn in red, and never the default button.
    public let isDestructive: Bool

    /// The title, which is unique within a page.
    public var id: String { title }

    /// Builds an action; icon-less and harmless unless said otherwise.
    public init(
        title: String, symbolName: String? = nil, intent: MainIntent, isDestructive: Bool = false
    ) {
        self.title = title
        self.symbolName = symbolName
        self.intent = intent
        self.isDestructive = isDestructive
    }

    /// What pressing it asks first, decided by its intent so every button for one act asks the same.
    public var confirmation: MainConfirmation? { MainConfirmation.before(intent) }
}

extension MainAction {
    /// The trash-can button every list draws: destructive, and never the default.
    static func delete(_ intent: MainIntent) -> MainAction {
        MainAction(title: "Delete", symbolName: "trash", intent: intent, isDestructive: true)
    }
}
