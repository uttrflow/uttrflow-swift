// Tests for AppContext.

import Foundation
import Testing

@testable import UttrflowCore

@Suite("AppContext")
struct AppContextTests {
    @Test("reports an all-nil context as empty so the prompt can omit it")
    func unknownContextIsEmpty() {
        #expect(AppContext.unknown.isEmpty)
        #expect(AppContext().isEmpty)
    }

    @Test("reports a context as non-empty when any single field is present")
    func anyFieldMakesItNonEmpty() {
        #expect(!AppContext(applicationName: "Slack").isEmpty)
        #expect(!AppContext(bundleIdentifier: "com.example").isEmpty)
        #expect(!AppContext(documentName: "notes.md").isEmpty)
        #expect(!AppContext(selectedText: "hello").isEmpty)
        #expect(!AppContext(precedingText: "").isEmpty, "an empty field is still something learnt")
        #expect(!AppContext(followingText: "later").isEmpty)
    }

    @Test("keeps every field it was given")
    func retainsFields() {
        let context = AppContext(
            applicationName: "Visual Studio Code",
            bundleIdentifier: "com.microsoft.VSCode",
            documentName: "main.py",
            selectedText: "def main():"
        )

        #expect(context.applicationName == "Visual Studio Code")
        #expect(context.bundleIdentifier == "com.microsoft.VSCode")
        #expect(context.documentName == "main.py")
        #expect(context.selectedText == "def main():")
        #expect(context.precedingText == nil)
        #expect(context.followingText == nil)
    }

    @Test("carries the text either side of the caret when a reader supplies it")
    func retainsCaretText() {
        let context = AppContext(applicationName: "Notes", precedingText: "before ", followingText: " after")
        #expect(context.precedingText == "before ")
        #expect(context.followingText == " after")
    }

    @Test("prints and mirrors only the application, never the field's text")
    func redactsFieldText() {
        let context = AppContext(
            applicationName: "Notes", bundleIdentifier: "com.example.notes", documentName: "title-marker",
            selectedText: "selected-marker", precedingText: "before-marker", followingText: "after-marker")
        var dumped = ""
        dump(context, to: &dumped)
        let printed = [String(describing: context), String(reflecting: context), "\(context)", dumped]

        for line in printed {
            #expect(line.contains("Notes"))
            for marker in ["title-marker", "selected-marker", "before-marker", "after-marker"] {
                #expect(!line.contains(marker), "\(marker) leaked into \(line)")
            }
        }
    }

    @Test("the storable identity keeps the application and drops the title and field text")
    func identityDropsText() throws {
        let context = AppContext(
            applicationName: "Notes", bundleIdentifier: "com.example.notes", documentName: "title",
            precedingText: "before")
        let decoded = try JSONDecoder().decode(
            AppIdentity.self, from: try JSONEncoder().encode(context.identity))

        #expect(decoded == AppIdentity(applicationName: "Notes", bundleIdentifier: "com.example.notes"))
        #expect(
            AppContext(identity: decoded)
                == AppContext(applicationName: "Notes", bundleIdentifier: "com.example.notes"))
    }

    @Test("no stored type can encode a value that holds field text")
    func storedTypesCannotHoldFieldText() {
        #expect(!(AppContext.unknown is any Encodable))
        #expect(!(AppContext.unknown is any Decodable))
        let kept = KeptRecording(id: UUID(), when: Date(), duration: .seconds(1), destination: AppIdentity())
        for child in Mirror(reflecting: kept).children {
            #expect(!(child.value is AppContext), "\(child.label ?? "?") holds an AppContext")
        }
    }

    @Test("a secure field alone does not make a context worth a prompt")
    func secureAloneIsEmpty() {
        #expect(AppContext(isSecure: true).isEmpty)
    }

    @Test("availability tells a read screen, a skipped read, a refused read and a secure field apart")
    func availabilityKinds() {
        #expect(AppContext(applicationName: "Notes").availability == .present)
        #expect(AppContext(applicationName: "Notes").readingSkipped().availability == .absentByDesign)
        #expect(AppContext(unavailable: .refused).availability == .unreadable)
        #expect(AppContext(unavailable: .secure).availability == .secure)
        #expect(AppContext(isSecure: true).readingSkipped().availability == .secure)
        #expect(ContextAvailability.present.emptyTextIsEvidence)
        #expect(!ContextAvailability.absentByDesign.emptyTextIsEvidence)
        #expect(!ContextAvailability.unreadable.emptyTextIsEvidence)
    }
}
