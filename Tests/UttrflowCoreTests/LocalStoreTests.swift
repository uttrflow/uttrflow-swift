import Foundation
import Testing

@testable import UttrflowCore

@Suite("Where a build keeps its own files")
struct LocalStoreTests {
    @Test("The shipped identifier keeps the folder every installed copy already writes to.")
    func shippedIdentifierKeepsItsFolder() {
        #expect(LocalStore.folder(for: LocalStore.productionIdentifier) == "Uttrflow")
    }

    @Test("A build with no identifier at all is treated as the shipped one.")
    func noIdentifierIsTheShippedFolder() {
        #expect(LocalStore.folder(for: nil) == "Uttrflow")
    }

    @Test("An identifier that merely resembles the shipped one is not a variant of it.")
    func onlyAnExtensionOfTheShippedIdentifierIsAVariant() {
        #expect(LocalStore.folder(for: "com.example.Uttrflow") == "Uttrflow")
        #expect(LocalStore.folder(for: "com.uttrflow.UttrflowDev") == "Uttrflow")
        #expect(LocalStore.folder(for: "\(LocalStore.productionIdentifier).") == "Uttrflow")
    }

    @Test("The development identifier writes beside the shipped folder rather than into it.")
    func developmentIdentifierGetsItsOwnFolder() {
        #expect(LocalStore.folder(for: "com.uttrflow.Uttrflow.dev") == "Uttrflow.dev")
    }

    @Test("A file lands under this build's folder, in the container it was given.")
    func filesLandUnderTheFolder() {
        let container = URL(filePath: "/tmp/container", directoryHint: .isDirectory)
        let file = LocalStore.file("clipboard.v1.json", in: container)
        #expect(file.path(percentEncoded: false) == "/tmp/container/Uttrflow/clipboard.v1.json")
    }

    @Test("A directory lands under this build's folder and is known to be one.")
    func directoriesLandUnderTheFolder() {
        let container = URL(filePath: "/tmp/container", directoryHint: .isDirectory)
        let models = LocalStore.directory("Models", in: container)
        #expect(models.path(percentEncoded: false) == "/tmp/container/Uttrflow/Models/")
        #expect(models.hasDirectoryPath)
    }

    @Test("A test runner is not a variant, so the suite reads the folder the app reads.")
    func theTestRunnerIsNotAVariant() {
        #expect(LocalStore.folder == "Uttrflow")
    }
}
