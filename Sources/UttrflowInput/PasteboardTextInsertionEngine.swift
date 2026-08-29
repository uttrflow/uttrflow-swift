public import UttrflowCore

/// Puts text into the focused app by pasting it.
///
/// Works anywhere ⌘V works, which is almost everywhere, so it is the strategy that
/// catches what the Accessibility API cannot reach.
///
/// It borrows the user's clipboard to do it, and gives it back. That matters more than
/// it sounds: someone who copied a paragraph, dictated a sentence, then pressed ⌘V
/// would otherwise find their paragraph gone. The restore is skipped if anything else
/// changed the clipboard in the meantime — replacing a newer copy would be the same
/// theft in the other direction.
public actor PasteboardTextInsertionEngine: TextInsertionEngine {
    /// How long to let the paste land before taking the clipboard back.
    ///
    /// The paste is asynchronous: the keystroke returns immediately and the target app
    /// reads the clipboard a moment later. Restoring too early pastes the old contents.
    /// Kept as the record of a decision that was reversed, and as the number to reach
    /// for if a way is ever found to tell whether a paste landed.
    public static let restoreDelay = Duration.milliseconds(250)

    public nonisolated let method: TextInsertionMethod = .pasteboard

    private let focus: any AccessibilityFocus
    private let pasteboard: any Pasteboard
    private let keystrokes: any KeystrokeSender
    private let clock: any Clock<Duration>

    public init(
        focus: any AccessibilityFocus,
        pasteboard: any Pasteboard,
        keystrokes: any KeystrokeSender,
        clock: any Clock<Duration> = ContinuousClock()
    ) {
        self.focus = focus
        self.pasteboard = pasteboard
        self.keystrokes = keystrokes
        self.clock = clock
    }

    /// Always, unless Uttrflow itself is in front.
    ///
    /// This asked whether the Accessibility API could see a focused element, which
    /// sounded prudent and was wrong twice over. Editors built on Electron — Cursor is
    /// the one this was reported from — expose no focused element at all and accept a
    /// ⌘V perfectly well, so the check refused to try in exactly the applications
    /// pasting exists to serve, and their dictations fell to the clipboard for the user
    /// to paste by hand.
    ///
    /// The reason it was ever narrowed is gone. Pasting used to put the borrowed
    /// clipboard back afterwards, so a paste into nowhere destroyed the dictation; it no
    /// longer restores anything, so the worst an attempt can now do is leave the words
    /// on the clipboard — which is precisely what the strategy below it would do.
    /// Trying and failing costs nothing; declining costs the user their insertion.
    public func canInsert() async -> Bool { !focus.isSelfFrontmost() }

    public func insert(_ text: String) async throws(TextInsertionError) {
        try await insert(text, richText: nil)
    }

    /// E2 — both flavours go up together and the receiving application takes the one it
    /// understands. Choosing for it would mean guessing what it can read, and guessing
    /// wrong towards HTML is how a tag ends up in a commit message.
    public func insert(_ text: String, richText: String?) async throws(TextInsertionError) {
        pasteboard.setText(text, richText: richText)
        // Thrown onwards with the text left on the clipboard on purpose: the caller
        // falls through to the floor, which would only put the same words back.
        try keystrokes.sendPaste()

        // Deliberately NOT restored. There is no way to find out whether the ⌘V landed:
        // `post` reports nothing, and the target application is under no obligation to
        // react. Putting the borrowed clipboard back is therefore a bet, and it is the
        // wrong way round — when the paste did land the user loses a clipboard they can
        // usually reproduce, and when it did not they lose the words they just spoke,
        // from the document AND the clipboard, with the app reporting success. That is
        // the "it does nothing at all" report this came from.
        //
        // §19 decides it: the words must survive. So the dictation stays on the
        // clipboard, and the cost is the previous contents.
    }

}
