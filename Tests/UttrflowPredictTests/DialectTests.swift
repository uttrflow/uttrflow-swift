import Testing

@testable import UttrflowPredict

@Suite("Knowing what a field holds")
struct DialectTests {
    @Test("A terminal holds a command line, and its branches and subcommands are worth consulting.")
    func terminalsAreShells() {
        let dialect = DialectRegistry.dialect(for: "com.googlecode.iterm2")
        #expect(dialect.kind == .shell)
        #expect(dialect.consultations.contains(.machine(.branch)))
        #expect(dialect.consultations.contains(.machine(.gitSubcommand)))
        #expect(dialect.consultations.contains(.shellHistory))
    }

    @Test("A database client holds a query, and its schema is the first thing to consult.")
    func databaseClientsAreSQL() {
        let dialect = DialectRegistry.dialect(for: "com.tinyapp.TablePlus")
        #expect(dialect.kind == .sql)
        #expect(dialect.consultations.first == .databaseSchema)
    }

    @Test("A browser holds an address, and only what has been visited is worth consulting.")
    func browsersAreAddresses() {
        let dialect = DialectRegistry.dialect(for: "com.google.Chrome")
        #expect(dialect.kind == .url)
        #expect(dialect.consultations == [.browsingHistory])
    }

    @Test("An editor holds code, and an API client holds a request.")
    func editorsAndClients() {
        #expect(DialectRegistry.dialect(for: "com.microsoft.VSCode").kind == .code)
        #expect(DialectRegistry.dialect(for: "com.apple.dt.Xcode").kind == .code)
        #expect(DialectRegistry.dialect(for: "com.postmanlabs.mac").kind == .url)
    }

    @Test("An application nobody has described holds prose and consults nothing.")
    func unknownApplicationsAreProse() {
        let dialect = DialectRegistry.dialect(for: "com.example.unheard-of")
        #expect(dialect == DialectRegistry.prose)
        #expect(dialect.kind == .prose)
        #expect(dialect.consultations.isEmpty)
    }

    @Test("A text area in a browser holds prose, because it is a page rather than the address bar.")
    func browserTextAreasArePlainWriting() {
        let addressBar = Surface(bundleIdentifier: "com.google.Chrome", role: "AXTextField")
        let page = Surface(bundleIdentifier: "com.google.Chrome", role: "AXTextArea")
        #expect(DialectRegistry.dialect(for: addressBar).kind == .url)
        #expect(DialectRegistry.dialect(for: page).kind == .prose)
    }

    @Test("A text area anywhere else keeps its application's dialect.")
    func otherTextAreasAreUnchanged() {
        let terminal = Surface(bundleIdentifier: "com.apple.Terminal", role: "AXTextArea")
        #expect(DialectRegistry.dialect(for: terminal).kind == .shell)
    }

    @Test("Every described application names a dialect this registry defines.")
    func theTableIsWellFormed() {
        let known = [
            DialectRegistry.terminal, DialectRegistry.databaseClient, DialectRegistry.browser,
            DialectRegistry.editor, DialectRegistry.apiClient, DialectRegistry.prose,
        ]
        for (identifier, dialect) in DialectRegistry.byBundleIdentifier {
            #expect(known.contains(dialect), "\(identifier) names a dialect nothing defines")
            #expect(!dialect.briefing.isEmpty)
            #expect(!dialect.name.isEmpty)
        }
    }

    @Test("Every kind of text is spoken by something that ships.")
    func everyKindIsReachable() {
        let kinds = Set(DialectRegistry.byBundleIdentifier.values.map(\.kind))
        #expect(kinds == Set(TextKind.allCases))
    }

    @Test("A dialect is a value, so two descriptions of the same thing are one.")
    func dialectsAreValues() {
        #expect(DialectRegistry.fallback == DialectRegistry.prose)
        #expect(Set([DialectRegistry.terminal, DialectRegistry.terminal]).count == 1)
    }
}
