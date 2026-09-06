import Testing
import UttrflowPredict

@testable import UttrflowPredictCapture

@Suite("Telling one field from another by what it publishes")
struct FieldReadingTests {
    @Test("A field with a bundle identifier and a role is enough to be a surface.")
    func minimalReadingIsASurface() {
        let reading = FieldReading(bundleIdentifier: "com.example.terminal", role: "AXTextArea")
        #expect(reading.surface == Surface(bundleIdentifier: "com.example.terminal", role: "AXTextArea"))
    }

    @Test("A field whose application does not name itself is no surface at all.")
    func namelessApplicationIsNoSurface() {
        #expect(FieldReading(bundleIdentifier: "  ", role: "AXTextArea").surface == nil)
    }

    @Test("A field with no role is no surface, because a search box would collapse into a document.")
    func rolelessIsNoSurface() {
        #expect(FieldReading(bundleIdentifier: "com.example.app", role: "").surface == nil)
    }

    @Test("The identifier is the locator when the field publishes one.")
    func identifierWins() {
        let reading = FieldReading(
            bundleIdentifier: "com.example.app", role: "AXTextField", identifier: "omnibox",
            placeholder: "Search", accessibilityDescription: "Address")
        #expect(reading.locator == "omnibox")
    }

    @Test("The placeholder names the field when there is no identifier.")
    func placeholderIsSecond() {
        let reading = FieldReading(
            bundleIdentifier: "com.example.app", role: "AXTextField", identifier: "  ",
            placeholder: "Search", accessibilityDescription: "Address")
        #expect(reading.locator == "Search")
    }

    @Test("The description is the last resort for a name.")
    func descriptionIsLast() {
        let reading = FieldReading(
            bundleIdentifier: "com.example.app", role: "AXTextField",
            accessibilityDescription: " Address ")
        #expect(reading.locator == "Address")
    }

    @Test("A field that publishes no name at all has no locator.")
    func nothingIsNoLocator() {
        #expect(FieldReading(bundleIdentifier: "com.example.app", role: "AXTextField").locator == nil)
    }

    @Test("A web field is scoped to the page's host, without the subdomain every site answers on.")
    func webScopeIsTheHost() {
        let reading = FieldReading(
            bundleIdentifier: "com.example.browser", role: "AXTextField",
            document: "https://WWW.Example.com/search?q=one")
        #expect(reading.scope == "example.com")
    }

    @Test("Two pages on one host are one surface, because the same field is on both.")
    func pathsDoNotSeparate() {
        func scope(_ url: String) -> String? {
            FieldReading(bundleIdentifier: "com.example.browser", role: "AXTextField", document: url)
                .scope
        }
        #expect(scope("http://example.com/one") == scope("http://example.com/two"))
    }

    @Test("A terminal is scoped to its working directory, however the directory is written.")
    func terminalScopeIsTheDirectory() {
        func scope(_ document: String) -> String? {
            FieldReading(bundleIdentifier: "com.example.terminal", role: "AXTextArea", document: document)
                .scope
        }
        #expect(scope("/Users/someone/work/") == "/Users/someone/work")
        #expect(scope("file:///Users/someone/work") == "/Users/someone/work")
        #expect(scope("file:///Users/someone/with%20space") == "/Users/someone/with space")
        #expect(scope("~/work") == "~/work")
        #expect(scope("/") == "/")
    }

    @Test("A document is scoped to the folder it sits in, so a project's files share one corpus.")
    func documentScopeIsTheContainingDirectory() {
        func scope(_ document: String) -> String? {
            FieldReading(bundleIdentifier: "com.example.editor", role: "AXTextArea", document: document)
                .scope
        }
        #expect(scope("file:///Users/someone/work/notes.rtf") == "/Users/someone/work")
        #expect(scope("/Users/someone/work/notes.rtf") == scope("/Users/someone/work/plan.rtf"))
        #expect(scope("file:///Users/someone/with%20space/notes.txt") == "/Users/someone/with space")
        #expect(scope("~/work/notes.md") == "~/work")
        #expect(scope("/notes.txt") == "/")
    }

    @Test("A document that is neither an address nor a path scopes nothing, rather than guessing.")
    func unrecognisedDocumentIsNoScope() {
        func scope(_ document: String?) -> String? {
            FieldReading(bundleIdentifier: "com.example.app", role: "AXTextField", document: document)
                .scope
        }
        #expect(scope("Untitled Note") == nil)
        #expect(scope("mailto:someone@example.com") == nil)
        #expect(scope("https:///nohost") == nil)
        #expect(scope("   ") == nil)
        #expect(scope(nil) == nil)
    }

    @Test("A composer that owns no document is scoped by its window, so one conversation is not the next.")
    func windowNamesTheConversation() {
        func composer(_ title: String?) -> Surface? {
            FieldReading(
                bundleIdentifier: "com.example.chat", role: "AXTextArea", placeholder: "Type a message",
                windowTitle: title
            ).surface
        }
        #expect(composer("Priya")?.scope == "Priya")
        #expect(composer("Papa")?.scope == "Papa")
        #expect(composer("Priya") != composer("Papa"))
        #expect(composer(nil)?.scope == nil)
    }

    @Test("A window's own marks and counts are not part of what it names, so a thread stays one thread.")
    func windowMarksAreNotTheName() {
        #expect(FieldReading.conversation("Priya (3)") == "Priya")
        #expect(FieldReading.conversation("Priya [12]") == "Priya")
        #expect(FieldReading.conversation("Draft • ") == "Draft")
        #expect(FieldReading.conversation("• Notes") == "Notes")
        #expect(FieldReading.conversation("  Priya  ") == "Priya")
        #expect(FieldReading.conversation("Priya (unread)") == "Priya (unread)")
        #expect(FieldReading.conversation("   ") == nil)
        // A window called after its own application names no thread: every conversation in it would share one name.
        #expect(FieldReading.conversation("Claude", of: "Claude") == nil)
        #expect(FieldReading.conversation("whatsapp", of: "WhatsApp") == nil)
        #expect(FieldReading.conversation("Priya", of: "Messages") == "Priya")
        #expect(FieldReading.conversation(nil) == nil)
        // A title long enough to be a document's first line names nothing, so it is not made an identity.
        #expect(FieldReading.conversation(String(repeating: "a", count: 200)) == nil)
    }

    @Test("A field that owns a document keeps its document's scope, whatever the window is called.")
    func documentsOutrankTheWindow() {
        let page = FieldReading(
            bundleIdentifier: "com.example.browser", role: "AXTextField",
            document: "https://example.com/inbox", windowTitle: "Inbox (12)")
        #expect(page.scope == "example.com")
        let terminal = FieldReading(
            bundleIdentifier: "com.example.terminal", role: "AXTextArea", document: "/Users/me/projects/api",
            windowTitle: "api — zsh")
        #expect(terminal.scope == "/Users/me/projects/api")
    }

    @Test("A password field says so as a role or as a subrole, and either counts.")
    func secureIsEitherRoleOrSubrole() {
        #expect(FieldReading(bundleIdentifier: "com.example.app", role: "AXSecureTextField").isSecure)
        #expect(
            FieldReading(
                bundleIdentifier: "com.example.app", role: "AXTextField", subrole: "AXSecureTextField"
            ).isSecure)
        #expect(!FieldReading(bundleIdentifier: "com.example.app", role: "AXTextField").isSecure)
    }

    @Test("Two fields of the same role in one application become two surfaces.")
    func locatorSeparatesSurfaces() {
        let one = FieldReading(
            bundleIdentifier: "com.example.browser", role: "AXTextField", identifier: "omnibox")
        let other = FieldReading(
            bundleIdentifier: "com.example.browser", role: "AXTextField", identifier: "find")
        #expect(one.surface != other.surface)
    }
}

@Suite("A field that hides what is typed is refused")
struct FieldReadingSecrecyTests {
    @Test("The secure role and subrole are both recognised.")
    func rolesAreSecure() {
        #expect(FieldReading(bundleIdentifier: "com.example.app", role: "AXSecureTextField").isSecure)
        #expect(
            FieldReading(
                bundleIdentifier: "com.example.app", role: "AXTextField",
                subrole: "AXSecureTextField"
            ).isSecure)
    }

    @Test("A password field that names itself is secure even without the role, as web fields are.")
    func namedPasswordIsSecure() {
        #expect(
            FieldReading(
                bundleIdentifier: "com.example.app", role: "AXTextField", identifier: "user_password"
            ).isSecure)
    }

    @Test("An ordinary field is not treated as secure.")
    func ordinaryIsNotSecure() {
        #expect(
            !FieldReading(
                bundleIdentifier: "com.example.app", role: "AXTextField", identifier: "search"
            ).isSecure)
    }
}
