// Tests for what a button asks before it does something that cannot be taken back.
import Testing

@testable import UttrflowUX

@Suite("What a button asks first")
struct MainConfirmationTests {
    /// Signing out stops the app until the user signs in again, so every Sign Out button asks first.
    @Test("signing out asks first, and nothing else in the window does")
    func signingOutAsksFirst() {
        #expect(MainConfirmation.before(.signOut) == .signOut)
        #expect(MainConfirmation.before(.deleteAccount) == .deleteAccount)
        #expect(MainConfirmation.deleteAccount.isDestructive)
        #expect(MainAction(title: "Sign Out", intent: .signOut).confirmation == .signOut)
        #expect(MainAction(title: "Add", intent: .addWord).confirmation == nil)
        #expect(MainConfirmation.before(.dismissNotice) == nil)
        #expect(MainConfirmation.signOut.isDestructive)
        #expect(MainConfirmation.signOut.cancelTitle == "Cancel")
        #expect(MainConfirmation.signOut.confirmTitle == "Sign out")
        #expect(MainConfirmation.signOut.symbolName == "rectangle.portrait.and.arrow.forward")
    }

    /// Settings' question keeps its words and is drawn as the destructive sheet it always is.
    @Test("a settings question becomes the same sheet with the same words")
    func settingsQuestion() {
        let asked = SettingsConfirmation(
            title: "Reset personalisation?", message: "This removes everything.",
            confirmTitle: "Reset", cancelTitle: "Cancel")
        let sheet = MainConfirmation(asked)
        #expect(sheet.title == asked.title)
        #expect(sheet.message == asked.message)
        #expect(sheet.confirmTitle == "Reset")
        #expect(sheet.cancelTitle == "Cancel")
        #expect(sheet.tone == .critical)
        #expect(sheet.isDestructive)
    }
}
