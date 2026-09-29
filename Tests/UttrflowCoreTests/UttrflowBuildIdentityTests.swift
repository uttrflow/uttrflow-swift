import Foundation
import Testing

@testable import UttrflowCore

@Suite("Uttrflow build identities")
struct UttrflowBuildIdentityTests {
    private func isHeldElsewhere(_ outcome: SingleInstanceLock.Outcome) -> Bool {
        if case .heldElsewhere = outcome { return true }
        return false
    }

    @Test("An app detects another running Uttrflow variant by identifier prefix")
    func detectsDifferentUttrflowIdentifier() {
        #expect(
            UttrflowBuildIdentity.otherRunningIdentifier(
                current: "com.uttrflow.Uttrflow.dev",
                running: ["com.apple.finder", "com.uttrflow.Uttrflow"]
            ) == "com.uttrflow.Uttrflow"
        )
        #expect(
            UttrflowBuildIdentity.otherRunningIdentifier(
                current: "com.uttrflow.Uttrflow.dev",
                running: ["com.uttrflow.Uttrflow.dev"]
            ) == nil
        )
    }

    @Test("Only a suffixed Uttrflow identifier identifies an isolated development build")
    func recognizesDevelopmentVariants() {
        #expect(UttrflowBuildIdentity.isDevelopmentBuild("com.uttrflow.Uttrflow.dev"))
        #expect(!UttrflowBuildIdentity.isDevelopmentBuild("com.uttrflow.Uttrflow"))
        #expect(!UttrflowBuildIdentity.isDevelopmentBuild("com.uttrflow.Uttrflow."))
        #expect(!UttrflowBuildIdentity.isDevelopmentBuild("com.example.Uttrflow.dev"))
    }

    @Test("Unknown identifiers are reported as sharing the production data folder")
    func recognizesProductionFolderFallback() {
        #expect(UttrflowBuildIdentity.usesProductionFolder("com.example.Uttrflow.dev"))
        #expect(UttrflowBuildIdentity.usesProductionFolder(nil))
        #expect(!UttrflowBuildIdentity.usesProductionFolder("com.uttrflow.Uttrflow.dev"))
    }

    @Test("Variants have separate store locks and one shared startup coordination lock")
    func separatesStoreLocksFromCoordinationLock() {
        let directory = URL(filePath: "/tmp/uttrflow-locks", directoryHint: .isDirectory)
        let productionStoreLock = LocalStore.file(
            "instance.lock", in: directory, for: "com.uttrflow.Uttrflow")
        let developmentStoreLock = LocalStore.file(
            "instance.lock", in: directory, for: "com.uttrflow.Uttrflow.dev")
        #expect(productionStoreLock != developmentStoreLock)
        #expect(
            SingleInstanceLock.coordinationFile(in: directory).path(percentEncoded: false)
                == "/tmp/uttrflow-locks/Uttrflow/instance-coordination.lock"
        )
    }

    @Test("Different data stores stay separate while the shared guard admits one running build")
    func coordinatesIndependentStoreLocks() throws {
        let directory = FileManager.default.temporaryDirectory.appending(
            path: "uttrflow-build-locks-\(UUID().uuidString)", directoryHint: .isDirectory)
        defer { try? FileManager.default.removeItem(at: directory) }
        let productionStore = SingleInstanceLock.acquire(
            at: LocalStore.file("instance.lock", in: directory, for: LocalStore.productionIdentifier))
        let developmentStore = SingleInstanceLock.acquire(
            at: LocalStore.file("instance.lock", in: directory, for: "com.uttrflow.Uttrflow.dev"))
        guard case .acquired(let productionLock) = productionStore,
            case .acquired(let developmentLock) = developmentStore
        else {
            Issue.record("separate build stores did not get independent locks")
            return
        }
        let coordinationFile = SingleInstanceLock.coordinationFile(in: directory)
        guard case .acquired(let coordinationLock) = SingleInstanceLock.acquire(at: coordinationFile) else {
            Issue.record("the first build did not take the shared coordination lock")
            return
        }

        #expect(isHeldElsewhere(SingleInstanceLock.acquire(at: coordinationFile)))
        withExtendedLifetime((productionLock, developmentLock, coordinationLock)) {}
    }
}
